if Code.ensure_loaded?(Plug) do
  defmodule Hermes.Server.Transport.SSE.Plug do
    @moduledoc """
    A Plug implementation for the SSE (Server-Sent Events) transport.

    > #### Deprecated {: .warning}
    >
    > This Plug has been deprecated as of MCP specification 2025-03-26 in favor
    > of the Streamable HTTP transport (`Hermes.Server.Transport.StreamableHTTP.Plug`).
    >
    > The HTTP+SSE transport from protocol version 2024-11-05 has been replaced by
    > the more flexible Streamable HTTP transport which supports optional SSE streaming
    > on a single endpoint.
    >
    > For new implementations, please use `Hermes.Server.Transport.StreamableHTTP.Plug` instead.
    > This module is maintained for backward compatibility with clients using the
    > 2024-11-05 protocol version.

    This plug handles the MCP HTTP+SSE protocol as specified in MCP 2024-11-05.
    It provides two separate endpoints:

    - SSE endpoint: Opens an SSE stream and sends "endpoint" event
    - POST endpoint: Handles JSON-RPC messages from client to server

    ## SSE Streaming Architecture

    This Plug handles SSE streaming by keeping the request process alive 
    and managing the streaming loop for server-to-client communication.

    ## Usage in Phoenix Router

        pipeline :mcp do
          plug :accepts, ["json", "event-stream"]
        end

        scope "/mcp" do
          pipe_through :mcp

          # SSE endpoint
          get "/sse", Hermes.Server.Transport.SSE.Plug,
            server: :your_server_name, mode: :sse

          # POST endpoint
          post "/messages", Hermes.Server.Transport.SSE.Plug,
            server: :your_server_name, mode: :post
        end

    ## Usage in Plug Router (Standalone)

        # When using in a standalone Plug.Router app
        plug Hermes.Server.Transport.SSE.Plug,
          server: :your_server_name,
          mode: :sse,
          at: "/sse",
          method_whitelist: ["GET"]

        plug Hermes.Server.Transport.SSE.Plug,
          server: :your_server_name,
          mode: :post,
          at: "/messages",
          method_whitelist: ["POST"]

    ## Configuration Options

    - `:server` - The server process name (required)
    - `:mode` - Either `:sse` or `:post` to determine endpoint behavior (required)
    - `:timeout` - Request timeout in milliseconds (default: 30000)
    - `:registry` - The registry to use. See `Hermes.Server.Registry.Adapter` for more information (default: Elixir's Registry implementation)

    ## Security Features

    - Origin header validation for DNS rebinding protection
    - Session-based request validation
    - Automatic session cleanup on connection loss

    ## HTTP Response Codes

    - 200: Successful request or SSE stream established
    - 202: Accepted (for notifications)
    - 400: Bad request (malformed JSON-RPC)
    - 405: Method not allowed
    - 500: Internal server error
    """

    @behaviour Plug

    use Hermes.Logging

    import Plug.Conn

    alias Hermes.MCP.Error
    alias Hermes.MCP.ID
    alias Hermes.MCP.Message
    alias Hermes.Server.Transport.SSE
    alias Hermes.SSE.Streaming
    alias Plug.Conn.Unfetched

    require Message

    @deprecated "Use Hermes.Server.Transport.StreamableHTTP.Plug instead"

    @default_timeout 30_000

    # Plug callbacks

    @impl Plug
    def init(opts) do
      server = Keyword.fetch!(opts, :server)
      mode = Keyword.fetch!(opts, :mode)

      if mode not in [:sse, :post] do
        raise ArgumentError, "SSE.Plug requires :mode to be either :sse or :post"
      end

      registry = Keyword.get(opts, :registry, Hermes.Server.Registry)
      transport = registry.transport(server, :sse)
      timeout = Keyword.get(opts, :timeout, @default_timeout)

      %{
        transport: transport,
        mode: mode,
        timeout: timeout
      }
    end

    @impl Plug
    def call(conn, %{mode: :sse} = opts) do
      handle_sse_endpoint(conn, opts)
    end

    def call(conn, %{mode: :post} = opts) do
      handle_post_endpoint(conn, opts)
    end

    # SSE endpoint handler

    defp handle_sse_endpoint(conn, opts) do
      case conn.method do
        "GET" -> establish_sse_connection(conn, opts)
        _ -> send_error(conn, 405, "Method not allowed")
      end
    end

    defp establish_sse_connection(conn, %{transport: transport}) do
      if accepts_sse?(conn) do
        session_id = ID.generate_session_id()

        case SSE.register_sse_handler(transport, session_id) do
          :ok ->
            endpoint_url = SSE.get_endpoint_url(transport)
            # Include session_id as query parameter in the endpoint URL
            endpoint_url_with_session = "#{endpoint_url}?session_id=#{session_id}"

            conn
            |> put_resp_header("cache-control", "no-cache")
            |> put_resp_header("connection", "keep-alive")
            |> Streaming.prepare_connection()
            |> send_endpoint_event(endpoint_url_with_session)
            |> Streaming.start(transport, session_id,
              on_close: fn ->
                SSE.unregister_sse_handler(transport, session_id)
              end
            )

          {:error, reason} ->
            Logging.transport_event("sse_registration_failed", %{reason: reason}, level: :error)

            send_error(conn, 500, "Could not establish SSE connection")
        end
      else
        send_error(conn, 406, "Accept header must include text/event-stream")
      end
    end

    defp send_endpoint_event(conn, endpoint_url) do
      chunk_data = format_sse_event("endpoint", endpoint_url)

      case chunk(conn, chunk_data) do
        {:ok, conn} ->
          conn

        {:error, _reason} ->
          conn
      end
    end

    defp format_sse_event(event_type, data) do
      "event: #{event_type}\ndata: #{data}\n\n"
    end

    # POST endpoint handler

    defp handle_post_endpoint(conn, opts) do
      case conn.method do
        "POST" -> handle_post_message(conn, opts)
        _ -> send_error(conn, 405, "Method not allowed")
      end
    end

    defp handle_post_message(conn, %{transport: transport} = opts) do
      with {:ok, body, conn} <- maybe_read_request_body(conn, opts),
           {:ok, [message]} <- maybe_parse_messages(body) do
        session_id = extract_session_id(conn)
        context = build_request_context(conn)

        message
        |> then(fn msg ->
          SSE.handle_message(transport, session_id, msg, context)
        end)
        |> send_response(conn)
      else
        {:error, :invalid_json} ->
          send_jsonrpc_error(
            conn,
            Error.protocol(:parse_error, %{message: "Invalid JSON"}),
            nil
          )

        {:error, reason} ->
          Logging.transport_event("post_error", %{reason: reason}, level: :error)

          send_jsonrpc_error(
            conn,
            Error.protocol(:internal_error, %{reason: reason}),
            nil
          )
      end
    end

    defp send_response({:ok, nil}, conn) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(202, "{}")
    end

    defp send_response({:ok, response}, conn) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, response)
    end

    defp send_response({:error, %Error{} = error}, conn) do
      send_jsonrpc_error(conn, error, nil)
    end

    defp send_response({:error, reason}, conn) do
      Logging.transport_event("response_error", %{reason: reason}, level: :error)

      send_jsonrpc_error(
        conn,
        Error.protocol(:internal_error, %{reason: reason}),
        nil
      )
    end

    # Helper functions

    defp accepts_sse?(conn) do
      conn
      |> get_req_header("accept")
      |> Enum.any?(fn accept ->
        String.contains?(accept, "text/event-stream")
      end)
    end

    defp extract_session_id(conn) do
      alias Plug.Conn.Query

      conn
      |> get_req_header("x-session-id")
      |> List.first()
      |> case do
        nil ->
          query_params = Query.decode(conn.query_string)
          query_params["session_id"] || ID.generate_session_id()

        session_id ->
          session_id
      end
    end

    defp maybe_parse_messages(body) when is_binary(body) do
      case Message.decode(body) do
        {:ok, messages} -> {:ok, messages}
        {:error, _} -> {:error, :invalid_json}
      end
    end

    defp maybe_parse_messages(body) when is_map(body) do
      case Message.validate_message(body) do
        {:ok, message} -> {:ok, [message]}
        {:error, _} -> {:error, :invalid_json}
      end
    end

    defp maybe_read_request_body(%{body_params: %Unfetched{aspect: :body_params}} = conn, %{timeout: timeout}) do
      case Plug.Conn.read_body(conn, read_timeout: timeout) do
        {:ok, body, conn} -> {:ok, body, conn}
        {:error, reason} -> {:error, reason}
      end
    end

    defp maybe_read_request_body(%{body_params: body} = conn, _), do: {:ok, body, conn}

    defp send_error(conn, status, message) do
      data = %{data: %{message: message, http_status: status}}

      mcp_error =
        case status do
          405 -> Error.protocol(:method_not_found, data)
          406 -> Error.protocol(:invalid_request, data)
          _ -> Error.protocol(:internal_error, data)
        end

      {:ok, error_response} = Error.to_json_rpc(mcp_error, ID.generate_error_id())

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, error_response)
    end

    defp send_jsonrpc_error(conn, %Error{} = error, id) do
      error_id = id || ID.generate_error_id()
      {:ok, encoded_error} = Error.to_json_rpc(error, error_id)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, encoded_error)
    end

    defp build_request_context(conn) do
      %{
        assigns: conn.assigns,
        type: :http,
        req_headers: conn.req_headers,
        query_params: fetch_query_params_safe(conn),
        remote_ip: conn.remote_ip,
        scheme: conn.scheme,
        host: conn.host,
        port: conn.port,
        request_path: conn.request_path
      }
    end

    defp fetch_query_params_safe(conn) do
      case conn.query_params do
        %Unfetched{} -> nil
        params -> params
      end
    end
  end
end
