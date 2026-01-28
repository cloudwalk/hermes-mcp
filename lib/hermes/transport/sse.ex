defmodule Hermes.Transport.SSE do
  @moduledoc """
  A transport implementation that uses Server-Sent Events (SSE) for receiving messages
  and HTTP POST requests for sending messages back to the server.

  > #### Deprecated {: .warning}
  >
  > This transport has been deprecated as of MCP specification 2025-03-26 in favor
  > of the Streamable HTTP transport (`Hermes.Transport.StreamableHTTP`).
  >
  > The HTTP+SSE transport from protocol version 2024-11-05 has been replaced by
  > the more flexible Streamable HTTP transport which supports optional SSE streaming
  > on a single endpoint.
  >
  > For new implementations, please use `Hermes.Transport.StreamableHTTP` instead.
  > This module is maintained for backward compatibility with servers using the
  > 2024-11-05 protocol version.

  > ## Notes {: .info}
  >
  > For initialization and setup, check our [Installation & Setup](./installation.html) and
  > the [Transport options](./transport_options.html) guides for reference.
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

  @deprecated "Use Hermes.Transport.StreamableHTTP instead"

  @type t :: GenServer.server()

  @typedoc """
  The options for the MCP server.

  - `:base_url` - The base URL of the MCP server (e.g. http://localhost:8000) (required).
  - `:base_path` - The base path of the MCP server (e.g. /mcp).
  - `:sse_path` - The path to the SSE endpoint (e.g. /mcp/sse) (default `:base_path` + `/sse`).
  """
  @type server ::
          Enumerable.t(
            {:base_url, String.t()}
            | {:base_path, String.t()}
            | {:sse_path, String.t()}
          )

  @type params_t :: Enumerable.t(option)
  @typedoc """
  The options for the SSE transport.

  - `:name` - The name of the transport process, respecting the `GenServer` "Name Registration" section.
  - `:client` - The client to send the messages to, respecting the `GenServer` "Name Registration" section.
  - `:server` - The server configuration.
  - `:headers` - The headers to send with the HTTP requests.
  - `:transport_opts` - The underlying HTTP transport options to pass to the HTTP client. You can check on the [Mint docs](https://hexdocs.pm/mint/Mint.HTTP.html#connect/4-transport-options)
  - `:http_options` - The underlying HTTP client options to pass to the HTTP client. You can check on the [Finch docs](https://hexdocs.pm/finch/Finch.html#t:request_opt/0)
  """
  @type option ::
          {:name, GenServer.name()}
          | {:client, GenServer.server()}
          | {:server, server}
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
    server: [
      base_url: {:required, {:string, {:transform, &URI.new!/1}}},
      base_path: {:string, {:default, "/"}},
      sse_path: {:string, {:default, "/sse"}}
    ],
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
  def send_message(pid, message, _opts \\ []) when is_binary(message) do
    GenServer.call(pid, {:send, message})
  end

  @impl Transport
  def shutdown(pid) do
    GenServer.cast(pid, :close_connection)
  end

  @impl Transport
  def supported_protocol_versions do
    ["2024-11-05"]
  end

  @impl GenServer
  def init(%{} = opts) do
    server_url = URI.append_path(opts.server[:base_url], opts.server[:base_path])
    sse_url = URI.append_path(server_url, opts.server[:sse_path])

    state =
      opts
      |> Map.merge(%{message_url: nil, stream_task: nil})
      |> Map.put(:server_url, server_url)
      |> Map.put(:sse_url, sse_url)

    metadata = %{
      server_url: URI.to_string(server_url),
      sse_url: URI.to_string(sse_url),
      transport: :sse,
      client: opts.client
    }

    Telemetry.execute(
      Telemetry.event_transport_init(),
      %{system_time: System.system_time()},
      metadata
    )

    {:ok, state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    parent = self()
    parent_metadata = Logger.metadata()

    metadata = %{
      transport: :sse,
      sse_url: URI.to_string(state.sse_url)
    }

    Telemetry.execute(
      Telemetry.event_transport_connect(),
      %{system_time: System.system_time()},
      metadata
    )

    task =
      Task.async(fn ->
        Logger.metadata(parent_metadata)

        stream =
          SSE.connect(state.sse_url, state.headers,
            dest: self(),
            transport_opts: state.transport_opts
          )

        process_stream(stream, parent)
      end)

    Process.monitor(task.pid)

    {:noreply, %{state | stream_task: task}}
  end

  defp process_stream(stream, pid) do
    Enum.each(stream, &handle_sse_event(&1, pid))
  end

  defp handle_sse_event({:error, :halted}, pid) do
    Hermes.Logging.transport_event("sse_halted", "Transport will be restarted")
    shutdown(pid)
  end

  defp handle_sse_event(%Event{event: "endpoint", data: endpoint}, pid) do
    Hermes.Logging.transport_event("endpoint", endpoint)
    send(pid, {:endpoint, endpoint})
  end

  defp handle_sse_event(%Event{event: "message", data: data}, pid) do
    Hermes.Logging.transport_event("message", data)
    send(pid, {:message, data})
  end

  # coming from fast-mcp ruby
  # https://github.com/yjacquin/fast-mcp/issues/38
  defp handle_sse_event(%Event{event: "ping", data: data}, _) do
    Hermes.Logging.transport_event("ping", data)
  end

  defp handle_sse_event(%Event{event: "reconnect", data: data}, _pid) do
    reason =
      case JSON.decode(data) do
        {:ok, %{"reason" => reason}} -> reason
        _ -> "unknown"
      end

    Hermes.Logging.transport_event("reconnect", %{reason: reason, data: data})
  end

  defp handle_sse_event(event, _pid) do
    Hermes.Logging.transport_event("unknown", event, level: :warning)
  end

  @impl GenServer
  def handle_call({:send, _}, _from, %{message_url: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:send, message}, _from, state) do
    metadata = %{
      transport: :sse,
      message_size: byte_size(message),
      endpoint: state.message_url
    }

    Telemetry.execute(
      Telemetry.event_transport_send(),
      %{system_time: System.system_time()},
      metadata
    )

    request = make_message_request(message, state)

    case HTTP.follow_redirect(request) do
      {:ok, %Finch.Response{status: status}} when status in 200..299 ->
        {:reply, :ok, state}

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logging.transport_event("http_error", %{status: status, body: body}, level: :error)

        {:reply, {:error, {:http_error, status, body}}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info({:endpoint, endpoint}, %{client: client, server_url: server_url} = state) do
    case URI.new(endpoint) do
      {:ok, endpoint} ->
        GenServer.cast(client, :initialize)

        {:noreply, %{state | message_url: parse_message_url(URI.parse(server_url), endpoint)}}

      {:error, _} = err ->
        {:stop, err, state}
    end
  end

  def handle_info({:message, message}, %{client: client} = state) do
    Telemetry.execute(
      Telemetry.event_transport_receive(),
      %{system_time: System.system_time()},
      %{
        transport: :sse,
        message_size: byte_size(message)
      }
    )

    GenServer.cast(client, {:response, message})
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{stream_task: %Task{pid: pid}} = state) do
    Logging.transport_event("stream_terminated", %{reason: reason}, level: :error)

    Telemetry.execute(
      Telemetry.event_transport_disconnect(),
      %{system_time: System.system_time()},
      %{
        transport: :sse,
        reason: reason
      }
    )

    {:stop, {:stream_terminated, reason}, state}
  end

  def handle_info(msg, state) do
    Logging.transport_event("unexpected_message", %{message: msg})
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:close_connection, state) do
    {:stop, :normal, state}
  end

  @impl GenServer
  def terminate(reason, %{stream_task: task}) when not is_nil(task) do
    Telemetry.execute(
      Telemetry.event_transport_terminate(),
      %{system_time: System.system_time()},
      %{
        transport: :sse,
        reason: reason
      }
    )

    Telemetry.execute(
      Telemetry.event_transport_disconnect(),
      %{system_time: System.system_time()},
      %{
        transport: :sse,
        reason: reason
      }
    )

    Task.shutdown(task, :brutal_kill)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp make_message_request(message, %{message_url: endpoint} = state) do
    HTTP.build(
      :post,
      endpoint,
      state.headers,
      message,
      [transport_opts: state.transport_opts] ++ state.http_options
    )
  end

  # tries to handle multiple possibles formats for message_url URI
  # https://github.com/cloudwalk/hermes-mcp/pull/60#issuecomment-2806309443
  defp parse_message_url(%{path: base_path} = base, %{scheme: nil, path: path} = uri)
       when is_binary(base_path) and is_binary(path) do
    if path =~ base_path do
      base
      |> URI.merge(uri)
      |> URI.to_string()
    else
      base
      |> URI.append_path(URI.to_string(uri))
      |> URI.to_string()
    end
  end

  defp parse_message_url(base, uri) do
    base
    |> URI.merge(uri)
    |> URI.to_string()
  end
end
