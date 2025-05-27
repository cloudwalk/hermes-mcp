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
  alias Hermes.MCP.Message
  alias Hermes.Telemetry
  alias Hermes.Transport.Behaviour, as: Transport

  require Message

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

    state = %{server: server}

    Logging.context(mcp_transport: :stdio, mcp_server: server)
    Logging.transport_event("starting", %{transport: :stdio, server: server})

    Telemetry.execute(
      Telemetry.event_transport_init(),
      %{system_time: System.system_time()},
      %{transport: :stdio, server: server}
    )

    {:ok, state, {:continue, :read}}
  end

  @impl GenServer
  def handle_continue(:read, state) do
    case read_from_stdin() do
      {:error, reason} -> {:stop, reason, state}
      {:ok, data} -> {:noreply, state, {:continue, {:forward_to_server, data}}}
    end
  end

  def handle_continue({:forward_to_server, data}, %{server: server} = state) do
    Task.start(fn ->
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

      case Message.decode(data) do
        {:ok, [decoded]} -> handle_decoded_message(server, decoded)
        {:error, reason} -> handle_message_error(server, data, reason)
      end
    end)

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

    IO.write(:stdio, message)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:shutdown, state) do
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

  defp handle_decoded_message(server, message) when Message.is_request(message) do
    GenServer.cast(server, {:message, message})
  end

  defp handle_decoded_message(server, message) when Message.is_notification(message) do
    GenServer.cast(server, {:notification, message})
  end

  defp handle_decoded_message(_server, message) do
    Logging.transport_event("unknown_message", %{message: message}, level: :warning)
  end

  defp handle_message_error(_server, raw_message, reason) do
    Logging.transport_event("decode_error", %{reason: reason, message: raw_message}, level: :error)

    Telemetry.execute(
      Telemetry.event_transport_error(),
      %{system_time: System.system_time()},
      %{transport: :stdio, reason: reason, message: raw_message}
    )
  end
end
