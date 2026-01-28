defmodule Hermes.Transport.StreamableHTTP do
  @moduledoc """
  A transport implementation that uses Streamable HTTP as specified in MCP 2025-03-26.

  This transport communicates with MCP servers via HTTP POST requests for sending messages
  and optionally uses Server-Sent Events (SSE) for receiving streaming responses.

  ## Usage

      # Start the transport with a base URL
      {:ok, transport} = Hermes.Transport.StreamableHTTP.start_link(
        client: client_pid,
        base_url: "http://localhost:8000",
        mcp_path: "/mcp"
      )

      # Send a message
      :ok = Hermes.Transport.StreamableHTTP.send_message(transport, encoded_message)

  ## Session Management

  The transport automatically handles MCP session IDs via the `mcp-session-id` header:
  - Extracts session ID from server responses
  - Includes session ID in subsequent requests
  - Maintains session state throughout the connection lifecycle
  - Handles session expiration (404 responses) by reinitializing

  ## Response Handling

  Based on the response status and content type:
  - 202 Accepted: Message acknowledged, no immediate response
  - 200 OK with application/json: Single JSON response forwarded to client
  - 200 OK with text/event-stream: SSE stream parsed and events forwarded to client
  - 404 Not Found: Session expired, triggers reinitialization

  ## SSE Support

  The transport can establish a separate GET connection for server-initiated messages.
  This allows the server to send requests and notifications without a client request.
  """

  @behaviour Hermes.Transport.Behaviour

  use GenServer
  use Hermes.Logging

  import Peri

  alias Hermes.HTTP
  alias Hermes.SSE
  alias Hermes.SSE.Event
  alias Hermes.Telemetry
  alias Hermes.Transport.Behaviour, as: Transport

  @default_timeout 15_000

  @type t :: GenServer.server()
  @type params_t :: Enumerable.t(option)

  @typedoc """
  The options for the Streamable HTTP transport.

  - `:base_url` - The base URL of the MCP server (e.g. http://localhost:8000) (required).
  - `:mcp_path` - The MCP endpoint path (e.g. /mcp) (default "/mcp").
  - `:client` - The client to send the messages to.
  - `:headers` - The headers to send with the HTTP requests.
  - `:transport_opts` - The underlying HTTP transport options.
  - `:http_options` - The underlying HTTP client options.
  - `:enable_sse` - Whether to establish a GET connection for server-initiated messages (default false).
  """
  @type option ::
          {:name, GenServer.name()}
          | {:client, GenServer.server()}
          | {:base_url, String.t()}
          | {:mcp_path, String.t()}
          | {:headers, map()}
          | {:transport_opts, keyword}
          | {:http_options, Finch.request_opts()}
          | {:enable_sse, boolean()}
          | GenServer.option()

  defschema(:options_schema, %{
    name: {{:custom, &Hermes.genserver_name/1}, {:default, __MODULE__}},
    client: {:required, Hermes.get_schema(:process_name)},
    base_url: {:required, {:string, {:transform, &URI.new!/1}}},
    mcp_path: {:string, {:default, "/"}},
    headers: {:map, {:default, %{}}},
    transport_opts: {:any, {:default, []}},
    http_options: {:any, {:default, []}},
    enable_sse: {:boolean, {:default, false}}
  })

  @impl Transport
  @spec start_link(params_t) :: GenServer.on_start()
  def start_link(opts \\ []) do
    opts = options_schema!(opts)
    GenServer.start_link(__MODULE__, Map.new(opts), name: opts[:name])
  end

  @impl Transport
  def send_message(pid \\ __MODULE__, message, opts \\ []) when is_binary(message) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(pid, {:send, message, opts}, timeout)
  end

  @impl Transport
  def shutdown(pid \\ __MODULE__) do
    GenServer.cast(pid, :close_connection)
  end

  @impl Transport
  def supported_protocol_versions, do: ["2025-03-26", "2025-06-18"]

  @impl GenServer
  def init(opts) do
    state = %{
      client: opts.client,
      mcp_url: URI.append_path(opts.base_url, opts.mcp_path),
      headers: opts.headers,
      transport_opts: opts.transport_opts,
      http_options: opts.http_options,
      session_id: nil,
      enable_sse: Map.get(opts, :enable_sse, false),
      sse_task: nil,
      last_event_id: nil,
      active_request: nil
    }

    emit_telemetry(:init, state)
    {:ok, state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    emit_telemetry(:connect, state)
    GenServer.cast(state.client, :initialize)
    new_state = maybe_start_sse_connection(state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call({:send, message, opts}, from, state) do
    emit_telemetry(:send, state, %{message_size: byte_size(message)})

    headers = Keyword.get(opts, :headers)
    log_event = if headers, do: "sending_http_request_with_headers", else: "sending_http_request"

    log_data = %{
      url: URI.to_string(state.mcp_url),
      size: byte_size(message)
    }

    log_data = if headers, do: Map.put(log_data, :additional_headers, Map.keys(headers)), else: log_data

    Logging.transport_event(log_event, log_data)

    new_state = %{state | active_request: from}

    case send_http_request(new_state, message, headers) do
      {:ok, response} ->
        Logging.transport_event("got_http_response", %{status: response.status})
        handle_response(response, new_state)

      {:error, {:http_error, 404, _body}} when not is_nil(state.session_id) ->
        Logging.transport_event("session_expired", %{session_id: state.session_id})
        {:reply, {:error, :session_expired}, %{new_state | session_id: nil}}

      {:error, reason} ->
        Logging.transport_event("http_request_error", %{reason: inspect(reason)}, level: :error)
        log_error(reason)
        {:reply, {:error, reason}, %{new_state | active_request: nil}}
    end
  end

  @impl GenServer
  def handle_cast(:close_connection, state) do
    if state.session_id, do: delete_session(state)
    if state.sse_task, do: Task.shutdown(state.sse_task, :brutal_kill)

    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_info({:sse_event, event}, state) do
    handle_sse_event(event, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:sse_response_event, event}, state) do
    handle_sse_event(event, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:sse_response_complete, state) do
    if state.active_request, do: GenServer.reply(state.active_request, :ok)
    {:noreply, %{state | active_request: nil}}
  end

  @impl GenServer
  def handle_info({:sse_closed, reason}, state) do
    Logging.transport_event("sse_connection_closed", %{reason: reason})
    new_state = maybe_start_sse_connection(%{state | sse_task: nil})
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) when state.sse_task != nil do
    if pid == state.sse_task.pid do
      Logging.transport_event("sse_task_down", %{reason: reason})
      new_state = maybe_start_sse_connection(%{state | sse_task: nil})
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(msg, state) do
    Logging.transport_event("unexpected_message", %{message: msg})
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    if state.sse_task, do: Task.shutdown(state.sse_task, 5000)
    if state.session_id, do: delete_session(state)

    emit_telemetry(:terminate, state, %{reason: reason})
  end

  # Private functions

  defp send_http_request(state, message, additional_headers) do
    base_headers =
      state.headers
      |> Map.put("accept", "application/json, text/event-stream")
      |> Map.put("content-type", "application/json")
      |> put_session_header(state.session_id)

    case additional_headers do
      nil ->
        do_send_http_request(state, message, base_headers)

      headers when is_map(headers) ->
        case validate_headers(headers) do
          :ok ->
            final_headers = Map.merge(base_headers, headers)
            do_send_http_request(state, message, final_headers)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # Common HTTP request logic
  defp do_send_http_request(state, message, headers) do
    options = [transport_opts: state.transport_opts] ++ state.http_options
    url = URI.to_string(state.mcp_url)

    Logging.transport_event("http_request", %{
      method: :post,
      url: url,
      headers: headers
    })

    request = HTTP.build(:post, url, headers, message, options)

    request
    |> HTTP.follow_redirect()
    |> case do
      {:ok, %{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} = error ->
        Logging.transport_event("http_request_failed", %{reason: reason}, level: :error)
        error
    end
  end

  defp handle_response(%{headers: headers, body: body, status: status}, state) do
    new_state = update_session_id(state, headers)

    Logging.transport_event("http_response", %{
      status: status,
      content_type: get_content_type(headers),
      body_size: byte_size(body),
      has_session: not is_nil(new_state.session_id)
    })

    case {status, get_content_type(headers)} do
      {202, _} ->
        {:reply, :ok, %{new_state | active_request: nil}}

      {_, "application/json"} ->
        forward_to_client(body, new_state)
        {:reply, :ok, %{new_state | active_request: nil}}

      {_, "text/event-stream"} ->
        stream_sse_response(body, new_state)
        {:noreply, new_state}

      {_, content_type} ->
        {:reply, {:error, {:unsupported_content_type, content_type}}, %{new_state | active_request: nil}}
    end
  end

  defp forward_to_client(message, %{client: client} = state) do
    emit_telemetry(:receive, state, %{message_size: byte_size(message)})
    GenServer.cast(client, {:response, message})
  end

  defp stream_sse_response(body, state) do
    parent = self()

    Task.start(fn ->
      body
      |> SSE.Parser.run()
      |> Enum.each(fn event ->
        send(parent, {:sse_response_event, event})
      end)

      send(parent, :sse_response_complete)
    end)
  rescue
    e ->
      Logging.transport_event("sse_parse_error", %{error: e}, level: :warning)

      if state.active_request do
        GenServer.reply(state.active_request, {:error, :sse_parse_error})
      end
  end

  defp handle_sse_event({:error, :halted}, _state) do
    Logging.transport_event("sse_halted", "SSE stream ended")
  end

  defp handle_sse_event(%Event{data: data, id: id}, state) do
    new_state = if id, do: %{state | last_event_id: id}, else: state
    forward_to_client(data, new_state)
  end

  defp handle_sse_event(event, _state) do
    Logging.transport_event("unknown_sse_event", event, level: :warning)
  end

  # Header validation - fail fast with clear error messages
  defp validate_headers(headers) when is_map(headers) do
    case find_invalid_header(headers) do
      nil ->
        :ok

      {key, value} ->
        {:error, "Invalid header value for '#{key}': HTTP headers must be strings, got #{inspect(value)}"}
    end
  end

  defp find_invalid_header(headers) do
    Enum.find(headers, fn {_key, value} ->
      not is_binary(value) and not is_nil(value)
    end)
  end

  defp put_session_header(headers, nil), do: headers

  defp put_session_header(headers, session_id), do: Map.put(headers, "mcp-session-id", session_id)

  defp update_session_id(state, headers) do
    case get_header(headers, "mcp-session-id") do
      nil -> state
      session_id -> %{state | session_id: session_id}
    end
  end

  defp get_header(headers, name) do
    headers
    |> Enum.find(fn {key, _} -> String.downcase(key) == String.downcase(name) end)
    |> case do
      {_, value} -> value
      nil -> nil
    end
  end

  defp get_content_type(headers) do
    headers
    |> get_header("content-type")
    |> case do
      nil -> "application/json"
      value -> value |> String.split(";") |> List.first() |> String.trim()
    end
  end

  defp emit_telemetry(event, state, extra_metadata \\ %{}) do
    metadata = %{
      transport: :streamable_http,
      mcp_url: URI.to_string(state.mcp_url),
      client: state.client
    }

    event_name =
      case event do
        :init -> Telemetry.event_transport_init()
        :connect -> Telemetry.event_transport_connect()
        :send -> Telemetry.event_transport_send()
        :receive -> Telemetry.event_transport_receive()
        :terminate -> Telemetry.event_transport_terminate()
      end

    Telemetry.execute(
      event_name,
      %{system_time: System.system_time()},
      Map.merge(metadata, extra_metadata)
    )
  end

  defp log_error({:http_error, status, body}) do
    Logging.transport_event("http_error", %{status: status, body: body}, level: :error)
  end

  defp log_error(reason) do
    Logging.transport_event("request_error", %{reason: reason}, level: :error)
  end

  # Additional helper functions for SSE support

  defp maybe_start_sse_connection(%{enable_sse: false} = state), do: state

  defp maybe_start_sse_connection(%{enable_sse: true, session_id: nil} = state), do: state

  defp maybe_start_sse_connection(%{enable_sse: true} = state) do
    task = start_sse_task(state)
    %{state | sse_task: task}
  end

  defp start_sse_task(state) do
    parent = self()
    Task.start_link(fn -> run_sse_task(parent, state) end)
  end

  defp run_sse_task(parent, state) do
    headers = build_sse_headers(state)
    options = [transport_opts: state.transport_opts] ++ state.http_options
    request = HTTP.build(:get, URI.to_string(state.mcp_url), headers, nil, options)

    process_sse_request(request, parent)
    send(parent, {:sse_closed, :normal})
  end

  defp build_sse_headers(state) do
    %{"accept" => "text/event-stream"}
    |> put_session_header(state.session_id)
    |> put_last_event_id_header(state.last_event_id)
  end

  defp process_sse_request(request, parent) do
    case HTTP.follow_redirect(request) do
      {:ok, %{status: 200, headers: resp_headers, body: body}} ->
        handle_sse_response(resp_headers, body, parent)

      {:ok, %{status: 405}} ->
        Logging.transport_event(
          "sse_not_supported",
          "Server returned 405 for GET request"
        )

      error ->
        Logging.transport_event("sse_connection_failed", %{error: error}, level: :warning)
    end
  end

  defp handle_sse_response(headers, body, parent) do
    if get_content_type(headers) == "text/event-stream" do
      body
      |> SSE.Parser.run()
      |> Enum.each(fn event -> send(parent, {:sse_event, event}) end)
    end
  end

  defp delete_session(state) do
    headers = put_session_header(%{}, state.session_id)

    options = [transport_opts: state.transport_opts] ++ state.http_options

    request =
      HTTP.build(:delete, URI.to_string(state.mcp_url), headers, nil, options)

    case HTTP.follow_redirect(request) do
      {:ok, %{status: status}} when status in [200, 405] ->
        :ok

      error ->
        Logging.transport_event("session_delete_failed", %{error: error}, level: :debug)

        :ok
    end
  end

  defp put_last_event_id_header(headers, nil), do: headers

  defp put_last_event_id_header(headers, event_id), do: Map.put(headers, "last-event-id", event_id)
end
