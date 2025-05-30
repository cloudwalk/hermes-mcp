defmodule Hermes.Server.Transport.STDIO do
  @moduledoc """
  STDIO transport implementation for MCP servers.

  This module handles communication with MCP clients via standard input/output streams,
  processing incoming JSON-RPC messages and forwarding responses.
  """

  @behaviour Hermes.Transport.Behaviour

  use GenServer

  import Peri

  alias Hermes.Logging
  alias Hermes.Telemetry
  alias Hermes.Transport.Behaviour, as: Transport

  @type t :: GenServer.server()

  @typedoc """
  STDIO transport options

  - `:server` - The server process (required)
  - `:name` - Optional name for registering the GenServer
  """
  @type option ::
          {:server, GenServer.server()}
          | {:name, GenServer.name()}
          | GenServer.option()

  defschema(:parse_options, [
    {:server, {:required, {:oneof, [{:custom, &Hermes.genserver_name/1}, :pid, {:tuple, [:atom, :any]}]}}},
    {:name, {:custom, &Hermes.genserver_name/1}}
  ])

  @doc """
  Starts a new STDIO transport process.

  ## Parameters
    * `opts` - Options
      * `:server` - (required) The server to forward messages to
      * `:name` - Optional name for the GenServer process

  ## Examples

      iex> Hermes.Server.Transport.STDIO.start_link(server: my_server)
      {:ok, pid}
  """
  @impl Transport
  @spec start_link(Enumerable.t(option())) :: GenServer.on_start()
  def start_link(opts) do
    opts = parse_options!(opts)
    server_name = Keyword.get(opts, :name)

    if server_name do
      GenServer.start_link(__MODULE__, Map.new(opts), name: server_name)
    else
      GenServer.start_link(__MODULE__, Map.new(opts))
    end
  end

  @doc """
  Sends a message to the client via stdout.

  ## Parameters
    * `transport` - The transport process
    * `message` - The message to send

  ## Returns
    * `:ok` if message was sent successfully
    * `{:error, reason}` otherwise
  """
  @impl Transport
  @spec send_message(GenServer.server(), binary()) :: :ok | {:error, term()}
  def send_message(transport, message) when is_binary(message) do
    GenServer.cast(transport, {:send, message})
  end

  @doc """
  Shuts down the transport connection.

  ## Parameters
    * `transport` - The transport process
  """
  @impl Transport
  @spec shutdown(GenServer.server()) :: :ok
  def shutdown(transport) do
    GenServer.cast(transport, :shutdown)
  end

  @impl GenServer
  def init(%{server: server}) do
    :ok = :io.setopts(encoding: :utf8)
    Process.flag(:trap_exit, true)

    state = %{server: server, reading_task: nil}

    Logger.metadata(mcp_transport: :stdio, mcp_server: server)
    Logging.transport_event("starting", %{transport: :stdio, server: server})

    Telemetry.execute(
      Telemetry.event_transport_init(),
      %{system_time: System.system_time()},
      %{transport: :stdio, server: server}
    )

    {:ok, state, {:continue, :start_reading}}
  end

  @impl GenServer
  def handle_continue(:start_reading, state) do
    task = Task.async(fn -> read_from_stdin() end)
    {:noreply, %{state | reading_task: task}}
  end

  @impl GenServer
  def handle_info({ref, result}, %{reading_task: %Task{ref: ref}} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, data} ->
        handle_incoming_data(data, state)

        task = Task.async(fn -> read_from_stdin() end)
        {:noreply, %{state | reading_task: task}}

      {:error, reason} ->
        Logging.transport_event("read_error", %{reason: reason}, level: :error)
        {:stop, {:error, reason}, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:send, message}, state) do
    Logging.transport_event(
      "outgoing",
      %{transport: :stdio, message_size: byte_size(message)},
      level: :debug
    )

    Telemetry.execute(
      Telemetry.event_transport_send(),
      %{system_time: System.system_time()},
      %{transport: :stdio, message_size: byte_size(message)}
    )

    IO.write(message)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:shutdown, %{reading_task: task} = state) do
    if task, do: Task.shutdown(task, :brutal_kill)

    Logging.transport_event("shutdown", "Transport shutting down", level: :info)

    Telemetry.execute(
      Telemetry.event_transport_disconnect(),
      %{system_time: System.system_time()},
      %{transport: :stdio, reason: :shutdown}
    )

    {:stop, :normal, state}
  end

  @impl GenServer
  def terminate(reason, _state) do
    Logging.transport_event("terminating", %{reason: reason}, level: :info)

    Telemetry.execute(
      Telemetry.event_transport_terminate(),
      %{system_time: System.system_time()},
      %{transport: :stdio, reason: reason}
    )

    :ok
  end

  # Private helper functions

  defp read_from_stdin do
    case IO.read(:stdio, :line) do
      :eof ->
        Logging.transport_event("eof", "End of input stream", level: :info)

        Telemetry.execute(
          Telemetry.event_transport_disconnect(),
          %{system_time: System.system_time()},
          %{transport: :stdio, reason: :eof}
        )

        {:error, :eof}

      {:error, reason} ->
        Logging.transport_event("read_error", %{reason: reason}, level: :error)

        Telemetry.execute(
          Telemetry.event_transport_error(),
          %{system_time: System.system_time()},
          %{transport: :stdio, reason: reason}
        )

        {:error, reason}

      data when is_binary(data) ->
        {:ok, data}
    end
  end

  defp handle_incoming_data(data, %{server: server}) do
    Logging.transport_event(
      "incoming",
      %{transport: :stdio, message_size: byte_size(data)},
      level: :debug
    )

    Telemetry.execute(
      Telemetry.event_transport_receive(),
      %{system_time: System.system_time()},
      %{transport: :stdio, message_size: byte_size(data)}
    )

    case GenServer.call(server, {:message, data}) do
      {:ok, nil} -> :ok
      {:ok, message} -> send_message(self(), message)
      {:error, reason} -> Logging.transport_event("server_error", %{reason: reason}, level: :error)
    end
  catch
    :exit, reason ->
      Logging.transport_event("server_call_failed", %{reason: reason}, level: :error)
  end
end
