defmodule Hermes.Transport.SSE do
  @moduledoc """
  A transport implementation that uses Server-Sent Events (SSE) for receiving messages
  and HTTP POST requests for sending messages back to the server.

  ## Examples

      iex> Hermes.Transport.SSE.start_link(server_url: "http://localhost:4000")
      {:ok, #PID<0.123.0>}

      iex> Hermes.Transport.SSE.send_message(pid, "Hello, world!")
  """

  use GenServer

  import Peri

  alias Hermes.Transport.Behaviour, as: Transport

  alias Hermes.SSE
  alias Hermes.SSE.Event

  alias Hermes.HTTP

  require Logger

  @behaviour Transport

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
    server_url: {:required, :string},
    headers: {:map, {:default, %{}}}
  }

  @impl Transport
  @spec start_link(params_t) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    opts = options_schema!(opts)
    GenServer.start_link(__MODULE__, Map.new(opts), name: opts[:name])
  end

  @impl Transport
  def send_message(pid \\ __MODULE__, message) when is_binary(message) do
    GenServer.call(pid, {:send, message})
  end

  @impl GenServer
  def init(%{} = opts) do
    state = Map.merge(opts, %{endpoint: nil, stream_task: nil, session_id: nil})

    {:ok, state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    parent = self()

    task =
      Task.async(fn ->
        stream = SSE.connect(state.server_url, state.headers, dest: self())
        process_stream(stream, parent)
      end)

    Process.monitor(task.pid)

    {:noreply, %{state | stream_task: task}}
  end

  # this function will run indefinitely
  defp process_stream(stream, pid) do
    stream
    |> Stream.each(&handle_sse_event(&1, pid))
    |> Stream.run()
  end

  defp handle_sse_event(%Event{event: "endpoint", data: endpoint}, pid) do
    send(pid, {:endpoint, endpoint})
  end

  defp handle_sse_event(%Event{event: "message", data: data}, pid) do
    send(pid, {:message, data})
  end

  defp handle_sse_event(event, _pid) do
    Logger.warning("Unhandled SSE event from stream: #{inspect(event)}")
  end

  @impl GenServer
  def handle_call({:send, _}, _from, %{endpoint: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:send, message}, _from, %{endpoint: endpoint, server_url: base} = state) do
    request = HTTP.build(:post, Path.join(base, endpoint), state.headers, message)

    case HTTP.follow_redirect(request) do
      {:ok, %Finch.Response{status: status}} when status in 200..299 ->
        {:reply, :ok, state}

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("HTTP error: #{status}, #{body}")
        {:reply, {:error, {:http_error, status, body}}, state}

      {:error, reason} ->
        Logger.error("Failed to send message: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info({:endpoint, endpoint}, %{client: client} = state) do
    Process.send(client, :initialize, [:noconnect])
    query = URI.parse(endpoint) |> then(&URI.decode_query(&1.query))
    {:noreply, %{state | endpoint: endpoint, session_id: query["session_id"]}}
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
    Logger.debug("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, %{stream_task: task} = _state) when not is_nil(task) do
    Task.shutdown(task, :brutal_kill)
    :ok
  end

  def terminate(_reason, _state) do
    :ok
  end
end
