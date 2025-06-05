defmodule Hermes.Server.Transport.StreamableHTTP do
  @moduledoc """
  Streamable HTTP transport implementation for MCP servers.

  This module implements the Streamable HTTP transport as specified in MCP 2025-03-26.
  It does NOT start its own HTTP server - instead, it provides a Plug that can be 
  integrated into Phoenix or other Plug-based applications.

  ## Features

  - Full MCP Streamable HTTP protocol support
  - Session management with ETS
  - Server-Sent Events (SSE) for streaming responses
  - Automatic session expiration and cleanup
  - Proper HTTP response handling

  ## Usage

  Add the transport to your MCP server configuration:

      server_opts = [
        module: YourServer,
        name: :your_server,
        transport: [layer: Hermes.Server.Transport.StreamableHTTP, name: :streamable_http_transport]
      ]

      {:ok, server} = Hermes.Server.Base.start_link(server_opts)

  Then in your Phoenix router or Plug application:

      forward "/mcp", to: Hermes.Server.Transport.StreamableHTTP.Plug,
        init_opts: [server: :your_server]

  ## Session Management

  Sessions are managed automatically through ETS tables. Each session tracks:
  - Server process reference
  - SSE connection (if active)
  - Last activity timestamp
  - MCP session ID (if provided by server)
  - Client information

  Sessions automatically expire after 5 minutes of inactivity.
  """

  @behaviour Hermes.Transport.Behaviour

  use GenServer

  import Peri

  alias Hermes.Logging
  alias Hermes.Telemetry
  alias Hermes.Transport.Behaviour, as: Transport

  @type t :: GenServer.server()

  @typedoc """
  StreamableHTTP transport options

  - `:server` - The server process (required)
  - `:name` - Name for registering the GenServer (required)
  - `:registry` - Registry process name (required)
  """
  @type option ::
          {:server, GenServer.server()}
          | {:name, GenServer.name()}
          | {:registry, GenServer.name()}
          | GenServer.option()

  defschema(:parse_options, [
    {:server, {:required, {:oneof, [{:custom, &Hermes.genserver_name/1}, :pid, {:tuple, [:atom, :any]}]}}},
    {:name, {:required, {:custom, &Hermes.genserver_name/1}}},
    {:registry, {{:custom, &Hermes.genserver_name/1}, {:default, :hello}}}
  ])

  @doc """
  Starts a new StreamableHTTP transport process.

  ## Parameters
    * `opts` - Options
      * `:server` - (required) The server to forward messages to
      * `:name` - (required) Name for the GenServer process
      * `:registry` - (required) Registry process name

  ## Examples

      iex> Hermes.Server.Transport.StreamableHTTP.start_link(
      ...>   server: my_server,
      ...>   name: :my_transport,
      ...>   registry: :my_registry
      ...> )
      {:ok, pid}
  """
  @impl Transport
  @spec start_link(Enumerable.t(option())) :: GenServer.on_start()
  def start_link(opts) do
    opts = parse_options!(opts)
    name = Keyword.fetch!(opts, :name)

    GenServer.start_link(__MODULE__, Map.new(opts), name: name)
  end

  @doc """
  Sends a message to the client via the active SSE connection.

  This function locates the appropriate session and sends the message
  through the SSE stream.

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
  Creates a new session for a client connection.

  Called by the Plug when a new client connects.
  """
  @spec create_session(GenServer.server()) :: {:ok, String.t()} | {:error, term()}
  def create_session(transport) do
    GenServer.call(transport, :create_session)
  end

  @doc """
  Handles an incoming message from a client.

  Called by the Plug when a message is received via HTTP POST.
  """
  @spec handle_message(GenServer.server(), String.t(), binary()) ::
          {:ok, binary() | nil} | {:error, term()}
  def handle_message(transport, session_id, message) do
    GenServer.call(transport, {:handle_message, session_id, message})
  end

  @doc """
  Sets the SSE connection for a session.

  Called by the Plug when an SSE connection is established.
  """
  @spec set_sse_connection(GenServer.server(), String.t(), pid()) :: :ok | {:error, term()}
  def set_sse_connection(transport, session_id, sse_pid) do
    GenServer.call(transport, {:set_sse_connection, session_id, sse_pid})
  end

  @doc """
  Records activity for a session.

  Called by the Plug when a message is received.
  """
  @spec record_session_activity(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def record_session_activity(transport, session_id) do
    GenServer.call(transport, {:record_session_activity, session_id})
  end

  @doc """
  Looks up a session by ID.

  Called by the Plug to validate session existence.
  """
  @spec lookup_session(GenServer.server(), String.t()) :: {:ok, map()} | {:error, term()}
  def lookup_session(transport, session_id) do
    GenServer.call(transport, {:lookup_session, session_id})
  end

  @doc """
  Terminates a session.

  Called by the Plug when cleaning up sessions.
  """
  @spec terminate_session(GenServer.server(), String.t()) :: :ok
  def terminate_session(transport, session_id) do
    GenServer.call(transport, {:terminate_session, session_id})
  end

  # GenServer implementation

  @impl GenServer
  def init(%{server: server, registry: registry}) do
    Process.flag(:trap_exit, true)

    state = %{
      server: server,
      registry: registry,
      current_session: nil
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
  def handle_call(:create_session, _from, %{server: server, registry: registry} = state) do
    case GenServer.call(registry, {:create_session, server}) do
      {:ok, session_id} ->
        {:reply, {:ok, session_id}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:handle_message, session_id, message}, _from, %{registry: registry} = state) do
    case GenServer.call(registry, {:lookup_session, session_id}) do
      {:ok, session_info} ->
        GenServer.call(registry, {:record_activity, session_id})

        case GenServer.call(session_info.server, {:message, message}) do
          {:ok, nil} ->
            {:reply, {:ok, nil}, state}

          {:ok, response} ->
            {:reply, {:ok, response}, state}

          {:error, reason} ->
            Logging.transport_event("server_error", %{reason: reason}, level: :error)
            {:reply, {:error, reason}, state}
        end

      {:error, :not_found} ->
        {:reply, {:error, :session_not_found}, state}
    end
  catch
    :exit, reason ->
      Logging.transport_event("server_call_failed", %{reason: reason}, level: :error)
      {:reply, {:error, :server_unavailable}, state}
  end

  @impl GenServer
  def handle_call({:set_sse_connection, session_id, sse_pid}, _from, %{registry: registry} = state) do
    case GenServer.call(registry, {:set_sse_connection, session_id, sse_pid}) do
      :ok ->
        Process.monitor(sse_pid)
        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:record_session_activity, session_id}, _from, %{registry: registry} = state) do
    result = GenServer.call(registry, {:record_activity, session_id})
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:lookup_session, session_id}, _from, %{registry: registry} = state) do
    result = GenServer.call(registry, {:lookup_session, session_id})
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:terminate_session, session_id}, _from, %{registry: registry} = state) do
    result = GenServer.call(registry, {:terminate_session, session_id})
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:send_message, message}, _from, state) do
    Logging.transport_event(
      "send_message_fallback",
      %{
        message_size: byte_size(message)
      },
      level: :warning
    )

    {:reply, {:error, :no_active_session}, state}
  end

  @impl GenServer
  def handle_cast(:shutdown, %{registry: registry} = state) do
    Logging.transport_event("shutdown", "Transport shutting down", level: :info)

    registry
    |> GenServer.call(:list_sessions)
    |> Enum.each(&GenServer.call(registry, {:terminate_session, &1}))

    Telemetry.execute(
      Telemetry.event_transport_disconnect(),
      %{system_time: System.system_time()},
      %{transport: :streamable_http, reason: :shutdown}
    )

    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{registry: registry} = state) do
    Logging.transport_event("sse_process_down", %{pid: pid, reason: reason})

    registry
    |> GenServer.call(:list_sessions)
    |> Enum.each(fn session_id ->
      case GenServer.call(registry, {:lookup_session, session_id}) do
        {:ok, %{sse_pid: ^pid}} ->
          GenServer.call(registry, {:terminate_session, session_id})

        _ ->
          :ok
      end
    end)

    {:noreply, state}
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
