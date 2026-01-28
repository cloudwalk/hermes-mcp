defmodule Hermes.Server.Transport.SSE do
  @moduledoc """
  SSE (Server-Sent Events) transport implementation for MCP servers.

  > #### Deprecated {: .warning}
  >
  > This transport has been deprecated as of MCP specification 2025-03-26 in favor
  > of the Streamable HTTP transport (`Hermes.Server.Transport.StreamableHTTP`).
  >
  > The HTTP+SSE transport from protocol version 2024-11-05 has been replaced by
  > the more flexible Streamable HTTP transport which supports optional SSE streaming
  > on a single endpoint.
  >
  > For new implementations, please use `Hermes.Server.Transport.StreamableHTTP` instead.
  > This module is maintained for backward compatibility with clients using the
  > 2024-11-05 protocol version.

  This module provides backward compatibility with the HTTP+SSE transport
  from MCP protocol version 2024-11-05. It supports multiple concurrent
  client sessions through Server-Sent Events for server-to-client communication
  and HTTP POST for client-to-server messages.

  ## Features

  - Multiple concurrent client sessions
  - Server-Sent Events for real-time server-to-client communication
  - Separate SSE and POST endpoints (as per 2024-11-05 spec)
  - Automatic session cleanup on disconnect
  - Integration with existing Phoenix/Plug applications

  ## Usage

  SSE transport is typically started through the server supervisor:

      Hermes.Server.start_link(MyServer, [],
        transport: :sse,
        sse: [port: 8080, sse_path: "/sse", post_path: "/messages"]
      )

  For integration with existing Phoenix/Plug applications:

      # In your router
      forward "/sse", Hermes.Server.Transport.SSE.Plug,
        server: MyApp.MCPServer,
        mode: :sse

      forward "/messages", Hermes.Server.Transport.SSE.Plug,
        server: MyApp.MCPServer,
        mode: :post

  ## Message Flow

  1. Client connects to SSE endpoint, receives "endpoint" event with POST URL
  2. Client sends messages via POST to the endpoint URL
  3. Server responses are pushed through the SSE connection
  4. Connection closes on client disconnect or server shutdown

  ## Configuration

  - `:port` - HTTP server port (default: 8080)
  - `:sse_path` - Path for SSE connections (default: "/sse")
  - `:post_path` - Path for POST messages (default: "/messages")
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

  @deprecated "Use Hermes.Server.Transport.StreamableHTTP instead"

  @type t :: GenServer.server()

  @typedoc """
  SSE transport options

  - `:server` - The server process (required)
  - `:name` - Name for registering the GenServer (required)
  - `:base_url` - Base URL for constructing endpoint URLs
  - `:post_path` - Path for POST endpoint (default: "/messages")
  """
  @type option ::
          {:server, GenServer.server()}
          | {:name, GenServer.name()}
          | {:base_url, String.t()}
          | {:post_path, String.t()}
          | GenServer.option()

  defschema(:parse_options, [
    {:server, {:required, Hermes.get_schema(:process_name)}},
    {:name, {:required, {:custom, &Hermes.genserver_name/1}}},
    {:base_url, {:string, {:default, ""}}},
    {:post_path, {:string, {:default, "/messages"}}},
    {:registry, {:atom, {:default, Hermes.Server.Registry}}},
    {:request_timeout, {:integer, {:default, to_timeout(second: 30)}}}
  ])

  @doc """
  Starts the SSE transport.
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

  This broadcasts to all active SSE connections for the session.

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
  def supported_protocol_versions do
    ["2024-11-05"]
  end

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
  @spec handle_message(GenServer.server(), String.t(), map(), map()) ::
          {:ok, binary() | nil} | {:error, term()}
  def handle_message(transport, session_id, message, context) do
    GenServer.call(transport, {:handle_message, session_id, message, context})
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

  @doc """
  Gets the endpoint URL that should be sent to clients.

  This constructs the URL that clients should use for POST requests.
  """
  @spec get_endpoint_url(GenServer.server()) :: String.t()
  def get_endpoint_url(transport) do
    GenServer.call(transport, :get_endpoint_url)
  end

  # GenServer implementation

  @impl GenServer
  def init(%{server: server} = opts) do
    Process.flag(:trap_exit, true)

    state = %{
      server: server,
      base_url: Map.get(opts, :base_url, ""),
      post_path: Map.get(opts, :post_path, "/messages"),
      registry: opts.registry,
      request_timeout: opts.request_timeout,
      # Map of session_id => {pid, monitor_ref}
      sse_handlers: %{}
    }

    Logger.metadata(mcp_transport: :sse, mcp_server: server)
    Logging.transport_event("starting", %{transport: :sse, server: server})

    Telemetry.execute(
      Telemetry.event_transport_init(),
      %{system_time: System.system_time()},
      %{transport: :sse, server: server}
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
  def handle_call({:handle_message, session_id, message, context}, _from, state) when is_map(message) do
    server = state.registry.whereis_server(state.server)
    timeout = state.request_timeout

    if Message.is_notification(message) do
      GenServer.cast(server, {:notification, message, session_id, context})
      {:reply, {:ok, nil}, state}
    else
      case forward_request_to_server(server, message, session_id, context, timeout) do
        {:ok, response} ->
          maybe_send_through_sse(response, session_id, state)

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
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
    Logging.transport_event("broadcast_message", %{
      message_size: byte_size(message),
      active_handlers: map_size(state.sse_handlers)
    })

    for {_session_id, {pid, _ref}} <- state.sse_handlers do
      send(pid, {:sse_message, message})
    end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:get_endpoint_url, _from, state) do
    endpoint_url =
      if state.base_url == "" do
        state.post_path
      else
        Path.join([state.base_url, state.post_path])
      end

    {:reply, endpoint_url, state}
  end

  defp maybe_send_through_sse(response, session_id, state) do
    case Map.get(state.sse_handlers, session_id) do
      {pid, _ref} ->
        send(pid, {:sse_message, response})
        {:reply, {:ok, nil}, state}

      nil ->
        {:reply, {:error, :no_sse_handler}, state}
    end
  end

  defp forward_request_to_server(server, message, session_id, context, timeout) do
    msg = {:request, message, session_id, context}

    case GenServer.call(server, msg, timeout) do
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
    Logging.transport_event("shutdown", %{transport: :sse}, level: :info)

    for {_session_id, {pid, _ref}} <- state.sse_handlers do
      send(pid, :close_sse)
    end

    Telemetry.execute(
      Telemetry.event_transport_disconnect(),
      %{system_time: System.system_time()},
      %{transport: :sse, reason: :shutdown}
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
      %{transport: :sse, reason: reason}
    )

    :ok
  end
end
