defmodule Hermes.Server.Transport.StreamableHTTP.Plug do
  @moduledoc """
  A Plug implementation for the Streamable HTTP transport.

  This plug handles the MCP Streamable HTTP protocol as specified in MCP 2025-03-26.
  It provides a single endpoint that supports both GET and POST methods:

  - GET: Opens an SSE stream for server-to-client communication
  - POST: Handles JSON-RPC messages from client to server

  ## Usage in Phoenix Router

      pipeline :mcp do
        plug :accepts, ["json"]
      end

      scope "/mcp" do
        pipe_through :mcp
        forward "/", to: Hermes.Server.Transport.StreamableHTTP.Plug, init_opts: [transport: :your_transport_name]
      end

  ## Usage in Plug Router

      forward "/mcp", to: Hermes.Server.Transport.StreamableHTTP.Plug, init_opts: [transport: :your_transport_name]

  ## Configuration Options

  - `:transport` - The transport GenServer name or PID (required)
  - `:session_header` - Custom header name for session ID (default: "mcp-session-id")
  - `:timeout` - Request timeout in milliseconds (default: 30000)

  ## Security Features

  - Origin header validation for DNS rebinding protection
  - Session-based request validation
  - Automatic session cleanup on connection loss
  - Rate limiting support (when configured)

  ## HTTP Response Codes

  - 200: Successful request
  - 202: Accepted (for notifications and responses)
  - 400: Bad request (malformed JSON-RPC)
  - 404: Session not found
  - 405: Method not allowed
  - 500: Internal server error
  """

  @behaviour Plug

  import Plug.Conn

  alias Hermes.Logging
  alias Hermes.MCP.Error
  alias Hermes.MCP.ID
  alias Hermes.MCP.Message
  alias Hermes.Server.Transport.StreamableHTTP

  require Logger
  require Message

  @default_session_header "mcp-session-id"
  @default_timeout 30_000
  @keepalive_interval 15_000

  # Plug callbacks

  @impl Plug
  def init(opts) do
    transport = Keyword.fetch!(opts, :transport)
    session_header = Keyword.get(opts, :session_header, @default_session_header)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    %{transport: transport, session_header: session_header, timeout: timeout}
  end

  @impl Plug
  def call(conn, opts) do
    case conn.method do
      "GET" -> handle_get(conn, opts)
      "POST" -> handle_post(conn, opts)
      _ -> send_error(conn, 405, "Method not allowed")
    end
  end

  defp handle_get(conn, %{transport: transport} = opts) do
    accept_header = conn |> get_req_header("accept") |> List.first("")

    if String.contains?(accept_header, "text/event-stream") do
      start_sse_connection(conn, transport, opts)
    else
      send_error(conn, 406, "Accept header must include text/event-stream")
    end
  end

  defp handle_post(conn, %{transport: transport, session_header: session_header} = opts) do
    with {:ok, session_id} <- get_session_id(conn, session_header, transport),
         {:ok, body} <- read_request_body(conn, opts) do
      StreamableHTTP.record_session_activity(transport, session_id)
      request_id = extract_request_id(body)

      case StreamableHTTP.handle_message(transport, session_id, body) do
        {:ok, nil} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(202, "{}")

        {:ok, response} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, response)

        {:error, %Error{} = error} ->
          send_jsonrpc_error(conn, error, request_id)

        {:error, reason} ->
          Logging.transport_event("request_handling_failed", %{reason: reason}, level: :error)
          send_jsonrpc_error(conn, Error.internal_error(%{data: %{reason: reason}}), request_id)
      end
    else
      {:error, :missing_session} ->
        send_jsonrpc_error(conn, Error.invalid_request(%{data: %{message: "Missing session ID"}}), ID.generate_error_id())

      {:error, :session_not_found} ->
        send_jsonrpc_error(conn, Error.invalid_request(%{data: %{message: "Session not found"}}), ID.generate_error_id())

      {:error, reason} ->
        Logging.transport_event("request_error", %{reason: reason}, level: :error)
        send_jsonrpc_error(conn, Error.parse_error(%{data: %{reason: reason}}), ID.generate_error_id())
    end
  end

  defp start_sse_connection(conn, transport, %{session_header: session_header}) do
    case StreamableHTTP.create_session(transport) do
      {:ok, session_id} ->
        conn
        |> setup_sse_headers()
        |> put_resp_header(session_header, session_id)
        |> send_chunked(200)
        |> start_sse_loop(transport, session_id)

      {:error, reason} ->
        Logging.transport_event("session_creation_failed", %{reason: reason}, level: :error)
        send_error(conn, 500, "Could not create session")
    end
  end

  defp setup_sse_headers(conn) do
    conn
    |> put_resp_header("content-type", "text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("connection", "keep-alive")
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-headers", "content-type, mcp-session-id")
  end

  defp start_sse_loop(conn, transport, session_id) do
    StreamableHTTP.set_sse_connection(transport, session_id, self())

    case chunk(conn, "event: connected\ndata: {\"sessionId\":\"#{session_id}\"}\n\n") do
      {:ok, conn} ->
        schedule_keepalive()
        sse_loop(conn, transport, session_id)

      {:error, :closed} ->
        cleanup_session(session_id, transport)
        conn

      {:error, :not_chunked} ->
        conn
    end
  end

  defp sse_loop(conn, transport, session_id) do
    receive do
      {:send_sse_message, message} ->
        case send_sse_message(conn, message) do
          {:ok, conn} -> sse_loop(conn, transport, session_id)
          {:error, :closed} -> cleanup_session(session_id, transport)
        end

      :keepalive ->
        case send_sse_keepalive(conn) do
          {:ok, conn} ->
            schedule_keepalive()
            sse_loop(conn, transport, session_id)

          {:error, :closed} ->
            cleanup_session(session_id, transport)
        end

      :terminate ->
        cleanup_session(session_id, transport)
        conn
    after
      @default_timeout ->
        Logging.transport_event("sse_timeout", %{session_id: session_id})
        cleanup_session(session_id, transport)
        conn
    end
  end

  defp send_sse_message(conn, message) do
    data = JSON.encode!(message)
    sse_event = "event: message\ndata: #{data}\n\n"
    chunk(conn, sse_event)
  end

  defp send_sse_keepalive(conn) do
    chunk(conn, "event: ping\ndata: {}\n\n")
  end

  defp schedule_keepalive do
    Process.send_after(self(), :keepalive, @keepalive_interval)
  end

  defp cleanup_session(session_id, transport) do
    StreamableHTTP.terminate_session(transport, session_id)
    Logging.transport_event("sse_connection_closed", %{session_id: session_id})
  end

  defp get_session_id(conn, session_header, transport) do
    case get_req_header(conn, session_header) do
      [session_id] when is_binary(session_id) and session_id != "" ->
        case StreamableHTTP.lookup_session(transport, session_id) do
          {:ok, _} -> {:ok, session_id}
          {:error, :not_found} -> {:error, :session_not_found}
        end

      _ ->
        {:error, :missing_session}
    end
  end

  defp read_request_body(conn, %{timeout: timeout}) do
    case Plug.Conn.read_body(conn, read_timeout: timeout) do
      {:ok, body, _conn} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_error(conn, status, message) do
    data = %{data: %{message: message, http_status: status}}

    mcp_error =
      case status do
        405 -> Error.method_not_found(data)
        406 -> Error.invalid_request(data)
        _ -> Error.internal_error(data)
      end

    error_response = Error.to_json_rpc!(mcp_error, ID.generate_error_id())

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, error_response)
  end

  defp send_jsonrpc_error(conn, %Error{} = error, id) do
    error_id = id || ID.generate_error_id()
    encoded_error = Error.to_json_rpc!(error, error_id)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, encoded_error)
  end

  defp extract_request_id(body) when is_binary(body) do
    case Message.decode(body) do
      {:ok, [message | _]} when is_map(message) -> Map.get(message, "id")
      _ -> nil
    end
  end
end
