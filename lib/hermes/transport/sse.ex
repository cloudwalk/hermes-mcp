defmodule Hermes.Transport.SSE do
  @moduledoc """
  A transport implementation that uses Server-Sent Events (SSE) for receiving messages
  and HTTP POST requests for sending messages back to the server.

  > ## Notes {: .info}
  >
  > For initialization and setup, check our [Installation & Setup](./installation.html) and
  > the [Transport options](./transport_options.html) guides for reference.
  """

  @behaviour Hermes.Transport.Behaviour

  use GenServer

  import Peri

  alias Hermes.HTTP
  alias Hermes.SSE
  alias Hermes.SSE.Event
  alias Hermes.Transport.Behaviour, as: Transport
  alias Hermes.URI, as: HermesURI

  require Logger

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
  def send_message(pid, message) when is_binary(message) do
    GenServer.call(pid, {:send, message})
  end

  @impl Transport
  def shutdown(pid) do
    GenServer.cast(pid, :close_connection)
  end

  @impl GenServer
  def init(%{} = opts) do
    server_url = make_server_url(opts.server)
    sse_url = HermesURI.join_path(server_url, opts.server[:sse_path])

    state =
      opts
      |> Map.merge(%{message_url: nil, stream_task: nil})
      |> Map.put(:server_url, server_url)
      |> Map.put(:sse_url, sse_url)

    {:ok, state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    parent = self()
    parent_metadata = Logger.metadata()

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

  # this function will run indefinitely
  defp process_stream(stream, pid) do
    Enum.each(stream, &handle_sse_event(&1, pid))
  end

  defp handle_sse_event({:error, :halted}, pid) do
    Logger.debug("Received halt notification from SSE streaming, transport will be restarted")
    shutdown(pid)
  end

  defp handle_sse_event(%Event{event: "endpoint", data: endpoint}, pid) do
    Logger.debug("Received endpoint event from server")
    send(pid, {:endpoint, endpoint})
  end

  defp handle_sse_event(%Event{event: "message", data: data}, pid) do
    Logger.debug("Received message event from server")
    send(pid, {:message, data})
  end

  defp handle_sse_event(event, _pid) do
    Logger.warning("Unhandled SSE event from stream: #{inspect(event)}")
  end

  @impl GenServer
  def handle_call({:send, _}, _from, %{message_url: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:send, message}, _from, state) do
    request = make_message_request(message, state)

    case HTTP.follow_redirect(request) do
      {:ok, %Finch.Response{status: status}} when status in 200..299 ->
        {:reply, :ok, state}

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("HTTP error: #{status}, #{body}")
        {:reply, {:error, {:http_error, status, body}}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info({:endpoint, endpoint}, %{client: client, server_url: server_url} = state) do
    GenServer.cast(client, :initialize)
    msg_url = URI.merge(URI.parse(server_url), endpoint)
    {:noreply, %{state | message_url: to_string(msg_url)}}
  end

  def handle_info({:message, message}, %{client: client} = state) do
    GenServer.cast(client, {:response, message})
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{stream_task: %Task{pid: pid}} = state) do
    Logger.error("SSE stream task terminated: #{inspect(reason)}")
    {:stop, {:stream_terminated, reason}, state}
  end

  def handle_info(msg, state) do
    Logger.debug("Unexpected genserver message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:close_connection, state) do
    {:stop, :normal, state}
  end

  @impl GenServer
  def terminate(_reason, %{stream_task: task} = _state) when not is_nil(task) do
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

  defp make_server_url(server_opts) do
    HermesURI.join_path(server_opts[:base_url], server_opts[:base_path])
  end
end
