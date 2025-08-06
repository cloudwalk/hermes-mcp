defmodule Hermes.Server.Transport.StreamableHTTP do
  @moduledoc """
  StreamableHTTP transport implementation for MCP servers.

  This module provides an HTTP-based transport layer that supports multiple
  concurrent client sessions through Server-Sent Events (SSE). It enables
  web-based MCP clients to communicate with the server using standard HTTP
  protocols.

  ## Features

  - Multiple concurrent client sessions
  - Server-Sent Events for real-time server-to-client communication
  - HTTP POST endpoint for client-to-server messages
  - Automatic session cleanup on disconnect
  - Integration with Phoenix/Plug applications

  ## Usage

  StreamableHTTP is typically started through the server supervisor:

      Hermes.Server.start_link(MyServer, [],
        transport: :streamable_http,
        streamable_http: [port: 4000]
      )

  For integration with existing Phoenix/Plug applications:

      # In your router
      forward "/mcp", Hermes.Server.Transport.StreamableHTTP.Plug,
        server: MyApp.MCPServer

  ## Message Flow

  1. Client connects to `/sse` endpoint, receives a session ID
  2. Client sends messages via POST to `/messages` with session ID header
  3. Server responses are pushed through the SSE connection
  4. Connection closes on client disconnect or server shutdown

  ## Configuration

  - `:port` - HTTP server port (default: 4000)
  - `:server` - The MCP server process to connect to
  - `:name` - Process registration name
  """

  @behaviour Hermes.Transport.Behaviour

  use GenServer
  use Hermes.Logging

  import Peri

  alias Hermes.MCP.Message
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

  defschema(:parse_options, [
    {:server, {:required, Hermes.get_schema(:process_name)}},
    {:name, {:required, {:custom, &Hermes.genserver_name/1}}},
    {:registry, {:atom, {:default, Hermes.Server.Registry}}},
    {:request_timeout, {:integer, {:default, to_timeout(second: 30)}}},
    {:task_supervisor, {:required, {:custom, &Hermes.genserver_name/1}}}
  ])

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
  @spec send_message(GenServer.server(), binary(), keyword()) :: :ok | {:error, term()}
  def send_message(transport, message, _opts \\ []) when is_binary(message) do
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
  def supported_protocol_versions, do: ["2025-03-26", "2025-06-18"]

  @doc """
  Registers an SSE handler process for a session.

  Called by the Plug when establishing an SSE connection.
  The calling process becomes the SSE handler for the session.
  """
  @spec register_sse_handler(GenServer.server(), String.t()) ::
          :ok | {:error, term()}
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
  Handles an incoming message from a client with request context.

  Called by the Plug when a message is received via HTTP POST.
  """
  @spec handle_message(GenServer.server(), String.t(), map() | list(map), map()) ::
          {:ok, binary() | nil} | {:error, term()}
  def handle_message(transport, session_id, message, context) do
    GenServer.call(transport, {:handle_message, session_id, message, context})
  end

  @doc """
  Handles an incoming message with context and returns {:sse, response} if SSE handler exists.

  This allows the Plug to know whether to stream the response via SSE
  or return it as a regular HTTP response.
  """
  @spec handle_message_for_sse(GenServer.server(), String.t(), map(), map()) ::
          {:ok, binary()} | {:sse, binary()} | {:error, term()}
  def handle_message_for_sse(transport, session_id, message, context) do
    GenServer.call(
      transport,
      {:handle_message_for_sse, session_id, message, context}
    )
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
  @spec route_to_session(GenServer.server(), String.t(), binary()) ::
          :ok | {:error, term()}
  def route_to_session(transport, session_id, message) do
    GenServer.call(transport, {:route_to_session, session_id, message})
  end

  # GenServer implementation

  @impl GenServer
  def init(%{server: server} = opts) do
    Process.flag(:trap_exit, true)

    state = %{
      server: server,
      registry: opts.registry,
      request_timeout: opts.request_timeout,
      task_supervisor: opts.task_supervisor,
      # Map of session_id => {pid, monitor_ref}
      sse_handlers: %{},
      active_tasks: %{}
    }

    Logger.metadata(mcp_transport: :streamable_http, mcp_server: server)

    Logging.transport_event("starting", %{
      transport: :streamable_http,
      server: server
    })

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
  def handle_call({:handle_message, session_id, message, context}, from, state) when is_map(message) do
    server = state.registry.whereis_server(state.server)
    timeout = state.request_timeout

    cond do
      Message.is_notification(message) ->
        GenServer.cast(server, {:notification, message, session_id, context})
        {:reply, {:ok, nil}, state}

      Message.is_response(message) or Message.is_error(message) ->
        GenServer.cast(server, {:response, message, session_id, context})
        {:reply, {:ok, nil}, state}

      true ->
        task =
          Task.Supervisor.async(state.task_supervisor, fn ->
            forward_request_to_server(server, message, session_id, context, timeout)
          end)

        task_info = %{
          type: :handle_message,
          session_id: session_id,
          from: from
        }

        {:noreply, put_in(state.active_tasks[task.ref], task_info)}
    end
  end

  @impl GenServer
  def handle_call({:handle_message_for_sse, session_id, message, context}, from, state) when is_map(message) do
    server = state.registry.whereis_server(state.server)
    timeout = state.request_timeout

    if Message.is_notification(message) do
      GenServer.cast(server, {:notification, message, session_id, context})
      {:reply, {:ok, nil}, state}
    else
      sse_handler? = Map.has_key?(state.sse_handlers, session_id)

      task =
        Task.Supervisor.async(state.task_supervisor, fn ->
          forward_request_to_server(
            server,
            message,
            session_id,
            context,
            timeout,
            sse_handler?
          )
        end)

      task_info = %{
        type: :handle_message_for_sse,
        session_id: session_id,
        from: from,
        has_sse_handler: sse_handler?
      }

      {:noreply, put_in(state.active_tasks[task.ref], task_info)}
    end
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

  defp forward_request_to_server(server, message, session_id, context, timeout, has_sse_handler \\ false) do
    msg = {:request, message, session_id, context}

    case GenServer.call(server, msg, timeout) do
      {:ok, response} when has_sse_handler ->
        {:sse, response}

      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        Logging.transport_event(
          "server_error",
          %{reason: reason, session_id: session_id},
          level: :error
        )

        {:error, reason}
    end
  catch
    :exit, reason ->
      Logging.transport_event("server_call_failed", %{reason: reason}, level: :error)
      {:error, :server_unavailable}
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

  # Handle successful task completion
  @impl GenServer
  def handle_info({ref, result}, %{active_tasks: active_tasks} = state)
      when is_reference(ref) and is_map_key(active_tasks, ref) do
    {task_info, active_tasks} = Map.pop(active_tasks, ref)
    GenServer.reply(task_info.from, result)
    Process.demonitor(ref, [:flush])

    {:noreply, %{state | active_tasks: active_tasks}}
  end

  def handle_info({_ref, _}, state), do: {:noreply, state}

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{active_tasks: active_tasks} = state)
      when is_map_key(active_tasks, ref) do
    {task_info, active_tasks} = Map.pop(active_tasks, ref)
    error = {:error, {:task_crashed, reason}}
    GenServer.reply(task_info.from, error)

    Logging.transport_event(
      "task_crashed",
      %{
        reason: inspect(reason, pretty: true),
        session_id: task_info.session_id
      },
      level: :error
    )

    {:noreply, %{state | active_tasks: active_tasks}}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    sse_handlers =
      state.sse_handlers
      |> Enum.reject(fn {_session_id, {handler_pid, monitor_ref}} ->
        handler_pid == pid and monitor_ref == ref
      end)
      |> Map.new()

    if map_size(sse_handlers) < map_size(state.sse_handlers) do
      Logging.transport_event("sse_handler_down", %{reason: inspect(reason)})
    end

    {:noreply, %{state | sse_handlers: sse_handlers}}
  end

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
