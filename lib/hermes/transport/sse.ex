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
    server: [
      base_url: {:required, {:string, {:transform, &URI.new!/1}}},
      base_path: {:string, {:default, ""}},
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
  def send_message(pid \\ __MODULE__, message) when is_binary(message) do
    GenServer.call(pid, {:send, message})
  end

  @impl Transport
  def shutdown(pid \\ __MODULE__) do
    GenServer.cast(pid, :close_connection)
  end

  @impl GenServer
  def init(%{} = opts) do
    state =
      opts
      |> Map.merge(%{endpoint: nil, stream_task: nil, session_id: nil})
      |> Map.put_new_lazy(:server_url, fn -> make_server_url(opts.server) end)

    {:ok, state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    parent = self()

    task =
      Task.async(fn ->
        stream =
          SSE.connect(state.server_url, state.headers,
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
    stream
    |> Stream.each(&handle_sse_event(&1, pid))
    |> Stream.run()
  end

  defp handle_sse_event(%Event{event: "endpoint", data: endpoint}, pid) do
    Logger.debug("[#{__MODULE__}] => received endpoint event from server")
    send(pid, {:endpoint, endpoint})
  end

  defp handle_sse_event(%Event{event: "message", data: data}, pid) do
    Logger.debug("[#{__MODULE__}] => received message event from server")
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
    request =
      HTTP.build(
        :post,
        Path.join(base, endpoint),
        state.headers,
        message,
        [transport_opts: state.transport_opts] ++ state.http_options
      )

    case HTTP.follow_redirect(request) do
      {:ok, %Finch.Response{status: status}} when status in 200..299 ->
        {:reply, :ok, state}

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("[#{__MODULE__}] => HTTP error: #{status}, #{body}")
        {:reply, {:error, {:http_error, status, body}}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info({:endpoint, endpoint}, %{client: client} = state) do
    Process.send(client, :initialize, [:noconnect])
    query = URI.parse(endpoint) |> then(&URI.decode_query(&1.query))
    {:noreply, %{state | endpoint: endpoint, session_id: query["sessionId"]}}
  end

  def handle_info({:message, message}, %{client: client} = state) do
    Process.send(client, {:response, message}, [:noconnect])
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{stream_task: %Task{pid: pid}} = state) do
    Logger.error("[#{__MODULE__}] => SSE stream task terminated: #{inspect(reason)}")
    {:stop, {:stream_terminated, reason}, state}
  end

  def handle_info(msg, state) do
    Logger.debug("[#{__MODULE__}] => unexpected genserver message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:close_connection, %{stream_task: task} = state) do
    Task.shutdown(task)
    {:stop, :normal, state}
  end

  @impl GenServer
  def terminate(_reason, %{stream_task: task} = _state) when not is_nil(task) do
    Task.shutdown(task, :brutal_kill)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp make_server_url(%{base_url: url, base_path: path, sse_path: sse}) do
    url
    |> URI.append_path(path)
    |> URI.append_path(sse)
  end
end
