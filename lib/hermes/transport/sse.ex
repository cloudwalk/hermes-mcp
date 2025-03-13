defmodule Hermes.Transport.SSE do
  @moduledoc """
  A transport implementation that uses Server-Sent Events (SSE) for receiving messages
  and HTTP POST requests for sending messages back to the server.

  ## Examples

      iex> Hermes.Transport.SSE.start_link(server_url: "http://localhost:4000")
      {:ok, #PID<0.123.0>}

      iex> Hermes.Transport.SSE.send_message(pid, "Hello, world!")

  ## Options

  The options schema for the SSE transport.

  - `name`: The name of the transport.
  - `client`: The client process to send messages to.
  - `server_url`: The URL of the server to connect to.
  - `headers`: Additional headers to send with the HTTP requests.
  - `transport_opts`: Additional options as keyword to pass to the HTTP client, you can reference the available options at https://hexdocs.pm/mint/Mint.HTTP.html#connect/4-transport-options
  - `http_options`: Additional HTTP request options as keyword to pass to the HTTP client, you can check the available options on https://hexdocs.pm/finch/Finch.html#t:request_opt/0
  """

  @behaviour Hermes.Transport.Behaviour

  use GenServer

  import Peri

  alias Hermes.HTTP
  alias Hermes.SSE
  alias Hermes.SSE.Event
  alias Hermes.Transport.Behaviour, as: Transport

  require Logger

  @type params_t :: Enumerable.t(option)
  @type option ::
          {:name, atom}
          | {:client, pid | atom}
          | {:server_url, String.t()}
          | {:headers, map()}
          | Supervisor.init_option()

  defschema :options_schema, %{
    name: {:atom, {:default, __MODULE__}},
    client: {:required, {:either, {:pid, :atom}}},
    server: [
      base_url: {:required, {:string, {:transform, &URI.new!/1}}},
      base_path: {:string, {:default, "/"}},
      sse_path: {:string, {:default, "/sse"}}
    ],
    headers: {:map, {:default, %{}}},
    transport_opts: {:any, {:default, []}},
    http_options: {:any, {:default, []}}
  }

  @impl Transport
  @spec start_link(params_t) :: Supervisor.on_start()
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
    sse_url = URI.append_path(server_url, opts.server[:sse_path])

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
  def handle_info({:endpoint, endpoint}, %{client: client, server: server} = state) do
    Process.send(client, :initialize, [:noconnect])
    message_url = URI.append_path(server[:base_url], endpoint)
    {:noreply, %{state | message_url: message_url}}
  end

  def handle_info({:message, message}, %{client: client} = state) do
    Process.send(client, {:response, message}, [:noconnect])
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
  def handle_cast(:close_connection, %{stream_task: task} = state) do
    Task.shutdown(task, to_timeout(second: 3))
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
    url = server_opts[:base_url]
    path = server_opts[:base_path]

    URI.append_path(url, path)
  end
end
