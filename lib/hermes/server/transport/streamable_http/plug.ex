if Code.ensure_loaded?(Plug) do
  defmodule Hermes.Server.Transport.StreamableHTTP.Plug do
    @moduledoc """
    A Plug implementation for the Streamable HTTP transport.

    This plug handles the MCP Streamable HTTP protocol as specified in MCP 2025-03-26.
    It provides a single endpoint that supports both GET and POST methods:

    - GET: Opens an SSE stream for server-to-client communication
    - POST: Handles JSON-RPC messages from client to server
    - DELETE: Closes a session

    ## SSE Streaming Architecture

    This Plug handles SSE streaming by keeping the request process alive 
    and managing the streaming loop for server-to-client communication.

    ## Usage in Phoenix Router

        pipeline :mcp do
          plug :accepts, ["json"]
        end

        scope "/mcp" do
          pipe_through :mcp
          forward "/", to: Hermes.Server.Transport.StreamableHTTP.Plug, server: :your_server_name
        end

    ## Usage in Plug Router

        forward "/mcp", to: Hermes.Server.Transport.StreamableHTTP.Plug, init_opts: [server: :your_server_name]

    ## Configuration Options

    - `:server` - The server process name (required)
    - `:session_header` - Custom header name for session ID (default: "mcp-session-id")
    - `:timeout` - Request timeout in milliseconds (default: 30000)
    - `:registry` - The registry to use. See `Hermes.Server.Registry.Adapter` for more information (default: Elixir's Registry implementation)

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

    use Hermes.Logging

    import Plug.Conn

    alias Hermes.MCP.Error
    alias Hermes.MCP.ID
    alias Hermes.MCP.Message
    alias Hermes.Server.Transport.StreamableHTTP
    alias Hermes.SSE.Streaming
    alias Plug.Conn.Unfetched

    require Message

    @default_session_header "mcp-session-id"
    @default_timeout 30_000

    # Plug callbacks

    @impl Plug
    def init(opts) do
      server = Keyword.fetch!(opts, :server)
      registry = Keyword.get(opts, :registry, Hermes.Server.Registry)
      transport = registry.transport(server, :streamable_http)
      session_header = Keyword.get(opts, :session_header, @default_session_header)
      timeout = Keyword.get(opts, :timeout, @default_timeout)

      %{transport: transport, session_header: session_header, timeout: timeout}
    end

    @impl Plug
    def call(conn, opts) do
      case conn.method do
        "GET" -> handle_get(conn, opts)
        "POST" -> handle_post(conn, opts)
        "DELETE" -> handle_delete(conn, opts)
        _ -> send_error(conn, 405, "Method not allowed")
      end
    end

    # GET request handler - establishes SSE connection

    defp handle_get(conn, %{transport: transport, session_header: session_header}) do
      if wants_sse?(conn) do
        session_id = get_or_create_session_id(conn, session_header)

        case StreamableHTTP.register_sse_handler(transport, session_id) do
          :ok ->
            start_sse_streaming(conn, transport, session_id, session_header)

          {:error, reason} ->
            Logging.transport_event("sse_registration_failed", %{reason: reason}, level: :error)

            send_error(conn, 500, "Could not establish SSE connection")
        end
      else
        send_error(conn, 406, "Accept header must include text/event-stream")
      end
    end

    # POST request handler - processes MCP messages

    defp handle_post(conn, %{transport: transport, session_header: session_header} = opts) do
      with :ok <- validate_accept_header(conn),
           {:ok, body, conn} <- maybe_read_request_body(conn, opts),
           {:ok, [message]} <- maybe_parse_messages(body) do
        session_id = determine_session_id(conn, session_header, message)
        context = build_request_context(conn)

        Logging.transport_event("parsed_messages", %{
          message: message,
          session_id: session_id
        })

        process_message(message, conn, transport, session_id, context, session_header)
      else
        {:error, :invalid_accept_header} ->
          send_error(
            conn,
            406,
            "Not Acceptable: Client must accept both application/json and text/event-stream"
          )

        {:error, :invalid_json} ->
          send_jsonrpc_error(
            conn,
            Error.protocol(:parse_error, %{message: "Invalid JSON"}),
            nil
          )

        {:error, reason} ->
          Logging.transport_event("request_error", %{reason: reason}, level: :error)

          send_jsonrpc_error(
            conn,
            Error.protocol(:parse_error, %{reason: reason}),
            nil
          )
      end
    end

    defp process_message(message, conn, transport, session_id, context, session_header) when is_map(message) do
      if Message.is_request(message) do
        handle_request_with_possible_sse(
          conn,
          transport,
          session_id,
          message,
          context,
          session_header
        )
      else
        # Notification
        transport
        |> StreamableHTTP.handle_message(session_id, message, context)
        |> format_notification_response(conn)
      end
    end

    defp format_notification_response({:ok, _}, conn) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(202, "{}")
    end

    defp format_notification_response({:error, %Error{} = error}, conn) do
      send_jsonrpc_error(conn, error, nil)
    end

    defp format_notification_response({:error, reason}, conn) do
      Logging.transport_event("notification_handling_failed", %{reason: reason}, level: :error)

      send_jsonrpc_error(
        conn,
        Error.protocol(:internal_error, %{reason: reason}),
        nil
      )
    end

    # DELETE request handler - closes session

    defp handle_delete(conn, %{transport: transport, session_header: session_header}) do
      case get_req_header(conn, session_header) do
        [session_id] when is_binary(session_id) and session_id != "" ->
          StreamableHTTP.unregister_sse_handler(transport, session_id)

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, "{}")

        _ ->
          send_error(conn, 400, "Session ID required")
      end
    end

    # Handle requests that might need SSE streaming

    defp handle_request_with_possible_sse(conn, transport, session_id, body, context, session_header) do
      if wants_sse?(conn) do
        handle_sse_request(
          conn,
          transport,
          session_id,
          body,
          context,
          session_header
        )
      else
        handle_json_request(
          conn,
          transport,
          session_id,
          body,
          context,
          session_header
        )
      end
    end

    defp handle_sse_request(conn, transport, session_id, body, context, session_header) do
      case StreamableHTTP.handle_message_for_sse(
             transport,
             session_id,
             body,
             context
           ) do
        {:sse, response} ->
          route_sse_response(
            conn,
            transport,
            session_id,
            response,
            body,
            context,
            session_header
          )

        {:ok, response} ->
          conn
          |> put_resp_content_type("application/json")
          |> maybe_add_session_header(session_header, session_id)
          |> send_resp(200, response)

        {:error, error} ->
          handle_request_error(conn, error, body)
      end
    end

    defp handle_json_request(conn, transport, session_id, body, context, session_header) do
      case StreamableHTTP.handle_message(transport, session_id, body, context) do
        {:ok, response} ->
          conn
          |> put_resp_content_type("application/json")
          |> maybe_add_session_header(session_header, session_id)
          |> send_resp(200, response)

        {:error, error} ->
          handle_request_error(conn, error, body)
      end
    end

    defp route_sse_response(conn, transport, session_id, response, body, context, session_header) do
      if handler_pid = StreamableHTTP.get_sse_handler(transport, session_id) do
        send(handler_pid, {:sse_message, response})

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(202, "{}")
      else
        establish_sse_for_request(
          conn,
          transport,
          session_id,
          body,
          context,
          session_header
        )
      end
    end

    defp handle_request_error(conn, %Error{} = error, body) do
      send_jsonrpc_error(conn, error, extract_request_id(body))
    end

    defp handle_request_error(conn, reason, body) do
      Logging.transport_event("request_error", %{reason: reason}, level: :error)

      send_jsonrpc_error(
        conn,
        Error.protocol(:internal_error, %{reason: reason}),
        extract_request_id(body)
      )
    end

    defp establish_sse_for_request(conn, transport, session_id, body, context, session_header) do
      case StreamableHTTP.register_sse_handler(transport, session_id) do
        :ok ->
          start_background_request(transport, session_id, body, context)
          start_sse_streaming(conn, transport, session_id, session_header)

        {:error, reason} ->
          Logging.transport_event("sse_registration_failed", %{reason: reason}, level: :error)

          send_jsonrpc_error(
            conn,
            Error.protocol(:internal_error, %{reason: reason}),
            extract_request_id(body)
          )
      end
    end

    defp start_background_request(transport, session_id, body, context) do
      self_pid = self()

      Task.start(fn ->
        case StreamableHTTP.handle_message(transport, session_id, body, context) do
          {:ok, response} when is_binary(response) ->
            send(self_pid, {:sse_message, response})

          {:error, reason} ->
            Logging.transport_event(
              "sse_background_request_error",
              %{reason: reason},
              level: :error
            )
        end
      end)
    end

    defp start_sse_streaming(conn, transport, session_id, session_header) do
      conn
      |> put_resp_header(session_header, session_id)
      |> Streaming.prepare_connection()
      |> Streaming.start(transport, session_id,
        on_close: fn ->
          StreamableHTTP.unregister_sse_handler(transport, session_id)
        end
      )
    end

    # Helper functions

    defp wants_sse?(conn) do
      conn
      |> get_req_header("accept")
      |> List.first("")
      |> String.contains?("text/event-stream")
    end

    defp validate_accept_header(conn) do
      accept_header =
        conn
        |> get_req_header("accept")
        |> List.first("")

      if String.contains?(accept_header, "application/json") and
           String.contains?(accept_header, "text/event-stream") do
        :ok
      else
        {:error, :invalid_accept_header}
      end
    end

    defp get_or_create_session_id(conn, session_header) do
      case get_req_header(conn, session_header) do
        [session_id] when is_binary(session_id) and session_id != "" ->
          session_id

        _ ->
          ID.generate_session_id()
      end
    end

    defp determine_session_id(_conn, _header, [message]) when Message.is_initialize(message) do
      ID.generate_session_id()
    end

    defp determine_session_id(conn, session_header, _message) do
      get_or_create_session_id(conn, session_header)
    end

    defp maybe_parse_messages(body) when is_binary(body) do
      case Message.decode(body) do
        {:ok, messages} ->
          {:ok, messages}

        {:error, reason} ->
          Logging.transport_event(
            "parse_error",
            %{body: body, reason: inspect(reason)},
            level: :error
          )

          {:error, :invalid_json}
      end
    end

    defp maybe_parse_messages(body) when is_map(body) do
      case Message.validate_message(body) do
        {:ok, message} -> {:ok, [message]}
        {:error, _} -> {:error, :invalid_json}
      end
    end

    defp maybe_add_session_header(conn, session_header, session_id) do
      if get_req_header(conn, session_header) == [] do
        put_resp_header(conn, session_header, session_id)
      else
        conn
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

    defp extract_request_id(%{"id" => request_id}), do: request_id
    defp extract_request_id(_), do: nil

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
