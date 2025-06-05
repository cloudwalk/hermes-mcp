defmodule Hermes.Server.Transport.StreamableHTTP do
  @moduledoc false

  @behaviour Hermes.Transport.Behaviour

  use GenServer

  import Peri

  alias Hermes.Logging
  alias Hermes.MCP.Message
  alias Hermes.Server.Registry
  alias Hermes.Telemetry
  alias Hermes.Transport.Behaviour, as: Transport

  require Message

  @type t :: GenServer.server()

  @typedoc """
  StreamableHTTP transport options

  - `:server` - The server process (required)
  - `:name` - Name for registering the GenServer (required)
  """
  @type option ::
          {:server, GenServer.server()}
          | {:name, GenServer.name()}
          | GenServer.option()

  defschema :parse_options, [
    {:server, {:required, Hermes.get_schema(:process_name)}},
    {:name, {:required, {:custom, &Hermes.genserver_name/1}}}
  ]

  @doc """
  Starts the StreamableHTTP transport.
  """
  @impl Transport
  @spec start_link(Enumerable.t(option())) :: GenServer.on_start()
  def start_link(opts) do
    opts = parse_options!(opts)
    {name, opts} = Keyword.pop!(opts, :name)

    GenServer.start_link(__MODULE__, Map.new(opts), name: name)
  end

  @doc """
  Sends a message to the client via the active SSE connection.

  This function is used for server-initiated notifications.
  It will broadcast to all active SSE connections.

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
    GenServer.call(transport, {:send_message, message})
  end

  @doc """
  Shuts down the transport connection.

  This terminates all active sessions managed by this transport.

  ## Parameters
    * `transport` - The transport process
  """
  @impl Transport
  @spec shutdown(GenServer.server()) :: :ok
  def shutdown(transport) do
    GenServer.cast(transport, :shutdown)
  end

  @impl Transport
  def supported_protocol_versions do
    ["2024-11-05", "2025-03-26"]
  end

  @doc """
  Registers an SSE handler process for a session.

  Called by the Plug when establishing an SSE connection.
  The calling process becomes the SSE handler for the session.
  """
  @spec register_sse_handler(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def register_sse_handler(transport, session_id) do
    GenServer.call(transport, {:register_sse_handler, session_id, self()})
  end

  @doc """
  Unregisters an SSE handler process for a session.

  Called when the SSE connection is closed.
  """
  @spec unregister_sse_handler(GenServer.server(), String.t()) :: :ok
  def unregister_sse_handler(transport, session_id) do
    GenServer.cast(transport, {:unregister_sse_handler, session_id})
  end

  @doc """
  Handles an incoming message from a client.

  Called by the Plug when a message is received via HTTP POST.
  """
  @spec handle_message(GenServer.server(), String.t(), binary()) ::
          {:ok, binary() | nil} | {:error, term()}
  def handle_message(transport, session_id, message) when is_binary(message) do
    GenServer.call(transport, {:handle_message, session_id, message})
  end

  @doc """
  Handles an incoming message and returns {:sse, response} if SSE handler exists.

  This allows the Plug to know whether to stream the response via SSE
  or return it as a regular HTTP response.
  """
  @spec handle_message_for_sse(GenServer.server(), String.t(), binary()) ::
          {:ok, binary()} | {:sse, binary()} | {:error, term()}
  def handle_message_for_sse(transport, session_id, message) when is_binary(message) do
    GenServer.call(transport, {:handle_message_for_sse, session_id, message})
  end

  @doc """
  Gets the SSE handler process for a session.

  Returns the pid of the process handling SSE for this session,
  or nil if no SSE connection exists.
  """
  @spec get_sse_handler(GenServer.server(), String.t()) :: pid() | nil
  def get_sse_handler(transport, session_id) do
    GenServer.call(transport, {:get_sse_handler, session_id})
  end

  @doc """
  Routes a message to a specific session's SSE handler.

  Used for targeted server notifications to specific clients.
  """
  @spec route_to_session(GenServer.server(), String.t(), binary()) :: :ok | {:error, term()}
  def route_to_session(transport, session_id, message) do
    GenServer.call(transport, {:route_to_session, session_id, message})
  end

  # GenServer implementation

  @impl GenServer
  def init(%{server: server}) do
    Process.flag(:trap_exit, true)

    state = %{
      server: server,
      # Map of session_id => {pid, monitor_ref}
      sse_handlers: %{}
    }

    Logger.metadata(mcp_transport: :streamable_http, mcp_server: server)
    Logging.transport_event("starting", %{transport: :streamable_http, server: server})

    Telemetry.execute(
      Telemetry.event_transport_init(),
      %{system_time: System.system_time()},
      %{transport: :streamable_http, server: server}
    )

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:register_sse_handler, session_id, pid}, _from, state) do
    ref = Process.monitor(pid)

    sse_handlers = Map.put(state.sse_handlers, session_id, {pid, ref})

    Logging.transport_event("sse_handler_registered", %{
      session_id: session_id,
      handler_pid: inspect(pid)
    })

    {:reply, :ok, %{state | sse_handlers: sse_handlers}}
  end

  @impl GenServer
  def handle_call({:handle_message, session_id, message}, _from, state) do
    handle_decoded_message(message, session_id, state, false)
  end

  @impl GenServer
  def handle_call({:handle_message_for_sse, session_id, message}, _from, state) do
    handle_decoded_message(message, session_id, state, Map.has_key?(state.sse_handlers, session_id))
  end

  @impl GenServer
  def handle_call({:get_sse_handler, session_id}, _from, state) do
    case Map.get(state.sse_handlers, session_id) do
      {pid, _ref} -> {:reply, pid, state}
      nil -> {:reply, nil, state}
    end
  end

  @impl GenServer
  def handle_call({:route_to_session, session_id, message}, _from, state) do
    case Map.get(state.sse_handlers, session_id) do
      {pid, _ref} ->
        send(pid, {:sse_message, message})
        {:reply, :ok, state}

      nil ->
        {:reply, {:error, :no_sse_handler}, state}
    end
  end

  @impl GenServer
  def handle_call({:send_message, message}, _from, state) do
    Logging.transport_event("broadcast_notification", %{
      message_size: byte_size(message),
      active_handlers: map_size(state.sse_handlers)
    })

    for {_session_id, {pid, _ref}} <- state.sse_handlers do
      send(pid, {:sse_message, message})
    end

    {:reply, :ok, state}
  end

  defp handle_decoded_message(message, session_id, state, has_sse_handler) do
    server = Registry.whereis_server(state.server)

    case Message.decode(message) do
      {:ok, [decoded]} ->
        route_message(server, decoded, session_id, state, has_sse_handler)

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp route_message(server, decoded, session_id, state, has_sse_handler) do
    if Message.is_notification(decoded) do
      GenServer.cast(server, {:notification, decoded, session_id})
      {:reply, {:ok, nil}, state}
    else
      call_server_with_request(server, decoded, session_id, state, has_sse_handler)
    end
  end

  defp call_server_with_request(server, decoded, session_id, state, has_sse_handler) do
    case GenServer.call(server, {:request, decoded, session_id}) do
      {:ok, response} when has_sse_handler ->
        {:reply, {:sse, response}, state}

      {:ok, response} ->
        {:reply, {:ok, response}, state}

      {:error, reason} ->
        Logging.transport_event("server_error", %{reason: reason, session_id: session_id}, level: :error)
        {:reply, {:error, reason}, state}
    end
  catch
    :exit, reason ->
      Logging.transport_event("server_call_failed", %{reason: reason}, level: :error)
      {:reply, {:error, :server_unavailable}, state}
  end

  @impl GenServer
  def handle_cast({:unregister_sse_handler, session_id}, state) do
    sse_handlers =
      case Map.get(state.sse_handlers, session_id) do
        {_pid, ref} ->
          Process.demonitor(ref, [:flush])
          Map.delete(state.sse_handlers, session_id)

        nil ->
          state.sse_handlers
      end

    {:noreply, %{state | sse_handlers: sse_handlers}}
  end

  @impl GenServer
  def handle_cast(:shutdown, state) do
    Logging.transport_event("shutdown", %{transport: :streamable_http}, level: :info)

    for {_session_id, {pid, _ref}} <- state.sse_handlers do
      send(pid, :close_sse)
    end

    Telemetry.execute(
      Telemetry.event_transport_disconnect(),
      %{system_time: System.system_time()},
      %{transport: :streamable_http, reason: :shutdown}
    )

    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    sse_handlers =
      state.sse_handlers
      |> Enum.reject(fn {_session_id, {handler_pid, monitor_ref}} ->
        handler_pid == pid and monitor_ref == ref
      end)
      |> Map.new()

    Logging.transport_event("sse_handler_down", %{handler_pid: inspect(pid)})

    {:noreply, %{state | sse_handlers: sse_handlers}}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, _state) do
    Telemetry.execute(
      Telemetry.event_transport_terminate(),
      %{system_time: System.system_time()},
      %{transport: :streamable_http, reason: reason}
    )

    :ok
  end
end
