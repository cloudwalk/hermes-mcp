defmodule Hermes.Transport.StreamableHTTP do
  @moduledoc """
  A transport implementation that uses Streamable HTTP as specified in MCP 2025-03-26.

  This transport communicates with MCP servers via HTTP POST requests for sending messages
  and optionally uses Server-Sent Events (SSE) for receiving streaming responses.
  """

  @behaviour Hermes.Transport.Behaviour

  use GenServer

  import Peri

  alias Hermes.HTTP
  alias Hermes.Logging
  alias Hermes.SSE
  alias Hermes.SSE.Event
  alias Hermes.Telemetry
  alias Hermes.Transport.Behaviour, as: Transport

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
  """
  @type option ::
          {:name, GenServer.name()}
          | {:client, GenServer.server()}
          | {:base_url, String.t()}
          | {:mcp_path, String.t()}
          | {:headers, map()}
          | {:transport_opts, keyword}
          | {:http_options, Finch.request_opts()}
          | GenServer.option()

  defschema(:options_schema, %{
    name: {{:custom, &Hermes.genserver_name/1}, {:default, __MODULE__}},
    client:
      {:required,
       {:oneof,
        [
          {:custom, &Hermes.genserver_name/1},
          :pid,
          {:tuple, [:atom, :any]}
        ]}},
    base_url: {:required, {:string, {:transform, &URI.new!/1}}},
    mcp_path: {:string, {:default, "/mcp"}},
    headers: {:map, {:default, %{}}},
    transport_opts: {:any, {:default, []}},
    http_options: {:any, {:default, []}}
  })

  @impl Transport
  @spec start_link(params_t) :: GenServer.on_start()
  def start_link(opts \\ []) do
    opts = options_schema!(opts)
    GenServer.start_link(__MODULE__, Map.new(opts), name: opts[:name])
  end

  @impl Transport
  def send_message(pid \\ __MODULE__, message) when is_binary(message) do
    GenServer.call(pid, {:send, message})
  end

  @impl Transport
  def shutdown(pid \\ __MODULE__) do
    GenServer.cast(pid, :close_connection)
  end

  @impl Transport
  def supported_protocol_versions do
    ["2025-03-26"]
  end

  @impl GenServer
  def init(opts) do
    state = %{
      client: opts.client,
      mcp_url: URI.append_path(opts.base_url, opts.mcp_path),
      headers: opts.headers,
      transport_opts: opts.transport_opts,
      http_options: opts.http_options,
      session_id: nil
    }

    emit_telemetry(:init, state)
    {:ok, state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    emit_telemetry(:connect, state)
    GenServer.cast(state.client, :initialize)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:send, message}, _from, state) do
    emit_telemetry(:send, state, %{message_size: byte_size(message)})

    with {:ok, response} <- send_http_request(state, message),
         {:ok, new_state} <- handle_response(response, state) do
      {:reply, :ok, new_state}
    else
      {:error, reason} ->
        log_error(reason)
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_cast(:close_connection, state) do
    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_info(msg, state) do
    Logging.transport_event("unexpected_message", %{message: msg})
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    emit_telemetry(:terminate, state, %{reason: reason})
  end

  # Private functions

  defp send_http_request(state, message) do
    headers =
      state.headers
      |> Map.put("accept", "application/json, text/event-stream")
      |> put_session_header(state.session_id)

    options = [transport_opts: state.transport_opts] ++ state.http_options

    :post
    |> HTTP.build(
      URI.to_string(state.mcp_url),
      headers,
      message,
      options
    )
    |> HTTP.follow_redirect()
    |> case do
      {:ok, %{status: status} = response} when status in 200..299 -> {:ok, response}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      error -> error
    end
  end

  defp handle_response(%{headers: headers, body: body, status: status}, state) do
    new_state = update_session_id(state, headers)

    case {status, get_content_type(headers)} do
      {202, _} ->
        {:ok, new_state}

      {_, "application/json"} ->
        forward_to_client(body, new_state)
        {:ok, new_state}

      {_, "text/event-stream"} ->
        process_sse_response(body, new_state)
        {:ok, new_state}

      {_, content_type} ->
        {:error, {:unsupported_content_type, content_type}}
    end
  end

  defp forward_to_client(message, %{client: client} = state) do
    emit_telemetry(:receive, state, %{message_size: byte_size(message)})
    GenServer.cast(client, {:response, message})
  end

  defp process_sse_response(body, state) do
    body
    |> SSE.Parser.run()
    |> Enum.each(&handle_sse_event(&1, state))
  rescue
    e -> Logging.transport_event("sse_parse_error", %{error: e}, level: :warning)
  end

  defp handle_sse_event({:error, :halted}, _state) do
    Logging.transport_event("sse_halted", "SSE stream ended")
  end

  defp handle_sse_event(%Event{data: data}, state) do
    forward_to_client(data, state)
  end

  defp handle_sse_event(event, _state) do
    Logging.transport_event("unknown_sse_event", event, level: :warning)
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
end
