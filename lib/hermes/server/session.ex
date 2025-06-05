defmodule Hermes.Server.Session do
  @moduledoc """
  Session management for MCP servers.

  This module provides session management capabilities for MCP servers, allowing
  multiple concurrent client connections to be tracked and managed. It follows
  the Elixir/OTP pattern where each session corresponds to a server process.

  ## Architecture

  Sessions are lightweight records that map session IDs to server and transport
  processes. The actual client state (client_info, capabilities, etc.) remains
  in the `Hermes.Server.Base.State` of each server process.

  ## Session Structure

  ```elixir
  %{
    id: "session-123",
    server: MyApp.Calculator,           # Server module name
    transport: {:streamable_http, ref}, # Transport type and reference
    created_at: DateTime.t(),
    last_activity: DateTime.t(),
    metadata: %{}                       # Optional session metadata
  }
  ```

  ## Usage

  ```elixir
  # Register a new session
  {:ok, session_id} = Hermes.Server.Session.register(
    server: MyApp.Calculator,
    transport: {:streamable_http, "transport-ref"}
  )

  # Look up a session
  {:ok, session} = Hermes.Server.Session.get(session_id)

  # Send notification to a specific session
  Hermes.Server.Session.send_notification(session_id, "ping", %{})

  # List all sessions
  sessions = Hermes.Server.Session.list()
  ```
  """

  use GenServer

  import Peri

  alias Hermes.MCP.ID
  alias Hermes.Server.Registry, as: ServerRegistry

  @type session_id :: String.t()
  @type server_name :: module() | GenServer.name()
  @type transport_type :: :stdio | :streamable_http | :sse | atom()
  @type transport_ref :: String.t() | atom() | pid()

  @type session :: %{
          id: session_id(),
          server: server_name(),
          transport: {transport_type(), transport_ref()},
          created_at: DateTime.t(),
          last_activity: DateTime.t(),
          metadata: map()
        }

  @type storage_backend :: module()

  @session_expiry_ms to_timeout(minute: 5)
  @cleanup_interval_ms to_timeout(minute: 1)

  defschema(:parse_options, [
    {:storage, {:required, :atom}},
    {:storage_opts, :keyword},
    {:expiry_ms, {:oneof, [:pos_integer, nil]}},
    {:cleanup_interval_ms, :pos_integer}
  ])

  # Client API

  @doc """
  Starts the session manager.

  ## Options

    * `:storage` - Storage backend module (defaults to `Hermes.Server.Session.Storage.ETS`)
    * `:storage_opts` - Options passed to storage backend
    * `:expiry_ms` - Session expiry in milliseconds (defaults to 5 minutes)
    * `:cleanup_interval_ms` - Cleanup interval in milliseconds (defaults to 1 minute)
  """
  def start_link(opts \\ []) do
    opts = Keyword.put_new(opts, :storage, Hermes.Server.Session.Storage.ETS)
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a new session.

  ## Options

    * `:server` - Server module or name (required)
    * `:transport` - Transport tuple `{type, ref}` (required)
    * `:metadata` - Optional metadata map

  ## Examples

      iex> Hermes.Server.Session.register(
      ...>   server: MyApp.Calculator,
      ...>   transport: {:streamable_http, "transport-123"}
      ...> )
      {:ok, "session-abc123"}
  """
  @spec register(keyword()) :: {:ok, session_id()} | {:error, term()}
  def register(opts) do
    GenServer.call(__MODULE__, {:register, opts})
  end

  @doc """
  Looks up a session by ID.

  ## Examples

      iex> Hermes.Server.Session.get("session-abc123")
      {:ok, %{id: "session-abc123", server: MyApp.Calculator, ...}}

      iex> Hermes.Server.Session.get("unknown")
      {:error, :not_found}
  """
  @spec get(session_id()) :: {:ok, session()} | {:error, :not_found}
  def get(session_id) do
    GenServer.call(__MODULE__, {:get, session_id})
  end

  @doc """
  Lists all active sessions.

  ## Options

    * `:server` - Filter by server module
    * `:transport_type` - Filter by transport type
    * `:limit` - Maximum number of results
    * `:offset` - Pagination offset

  ## Examples

      iex> Hermes.Server.Session.list()
      [%{id: "session-1", ...}, %{id: "session-2", ...}]

      iex> Hermes.Server.Session.list(server: MyApp.Calculator)
      [%{id: "session-1", server: MyApp.Calculator, ...}]
  """
  @spec list(keyword()) :: [session()]
  def list(opts \\ []) do
    GenServer.call(__MODULE__, {:list, opts})
  end

  @doc """
  Updates session metadata.

  ## Examples

      iex> Hermes.Server.Session.update("session-123", %{user_id: 42})
      {:ok, %{id: "session-123", metadata: %{user_id: 42}, ...}}
  """
  @spec update(session_id(), map()) :: {:ok, session()} | {:error, :not_found}
  def update(session_id, updates) do
    GenServer.call(__MODULE__, {:update, session_id, updates})
  end

  @doc """
  Unregisters a session.

  ## Examples

      iex> Hermes.Server.Session.unregister("session-123")
      :ok
  """
  @spec unregister(session_id()) :: :ok | {:error, :not_found}
  def unregister(session_id) do
    GenServer.call(__MODULE__, {:unregister, session_id})
  end

  @doc """
  Sends a notification to a specific session.

  This is a convenience function that looks up the session's server
  and sends the notification through it.

  ## Examples

      iex> Hermes.Server.Session.send_notification("session-123", "ping", %{})
      :ok
  """
  @spec send_notification(session_id(), String.t(), map()) :: :ok | {:error, term()}
  def send_notification(session_id, method, params \\ %{}) do
    with {:ok, session} <- get(session_id) do
      server_name = get_server_name(session.server)
      Hermes.Server.Base.send_notification(server_name, method, params)
    end
  end

  @doc """
  Finds sessions by server.

  ## Examples

      iex> Hermes.Server.Session.find_by_server(MyApp.Calculator)
      [%{id: "session-1", server: MyApp.Calculator, ...}]
  """
  @spec find_by_server(server_name()) :: [session()]
  def find_by_server(server) do
    list(server: server)
  end

  @doc """
  Finds sessions by transport type.

  ## Examples

      iex> Hermes.Server.Session.find_by_transport(:streamable_http)
      [%{id: "session-1", transport: {:streamable_http, _}, ...}]
  """
  @spec find_by_transport(transport_type()) :: [session()]
  def find_by_transport(transport_type) do
    list(transport_type: transport_type)
  end

  @doc """
  Updates the last activity timestamp for a session.

  ## Examples

      iex> Hermes.Server.Session.touch("session-123")
      :ok
  """
  @spec touch(session_id()) :: :ok | {:error, :not_found}
  def touch(session_id) do
    GenServer.call(__MODULE__, {:touch, session_id})
  end

  # Server callbacks

  @impl GenServer
  def init(opts) do
    opts = parse_options!(opts)

    storage_module = opts[:storage]
    storage_opts = opts[:storage_opts] || []
    expiry_ms = opts[:expiry_ms] || @session_expiry_ms
    cleanup_interval_ms = opts[:cleanup_interval_ms] || @cleanup_interval_ms

    case storage_module.init(storage_opts) do
      {:ok, storage_state} ->
        state = %{
          storage: storage_module,
          storage_state: storage_state,
          expiry_ms: expiry_ms
        }

        # Schedule periodic cleanup
        if expiry_ms do
          Process.send_after(self(), :cleanup, cleanup_interval_ms)
        end

        {:ok, state}

      {:error, reason} ->
        {:stop, {:storage_init_failed, reason}}
    end
  end

  @impl GenServer
  def handle_call({:register, opts}, _from, state) do
    session_id = ID.generate_session_id()

    session_data = %{
      id: session_id,
      server: Keyword.fetch!(opts, :server),
      transport: Keyword.fetch!(opts, :transport),
      created_at: DateTime.utc_now(),
      last_activity: DateTime.utc_now(),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    case state.storage.register(state.storage_state, session_id, session_data) do
      {:ok, new_storage_state} ->
        {:reply, {:ok, session_id}, %{state | storage_state: new_storage_state}}

      {:error, reason, new_storage_state} ->
        {:reply, {:error, reason}, %{state | storage_state: new_storage_state}}
    end
  end

  @impl GenServer
  def handle_call({:get, session_id}, _from, state) do
    case state.storage.lookup(state.storage_state, session_id) do
      {:ok, session, new_storage_state} ->
        {:reply, {:ok, session}, %{state | storage_state: new_storage_state}}

      {:error, :session_not_found, new_storage_state} ->
        {:reply, {:error, :not_found}, %{state | storage_state: new_storage_state}}
    end
  end

  @impl GenServer
  def handle_call({:list, opts}, _from, state) do
    case state.storage.list(state.storage_state, opts) do
      {:ok, sessions, new_storage_state} ->
        {:reply, sessions, %{state | storage_state: new_storage_state}}
    end
  end

  @impl GenServer
  def handle_call({:update, session_id, updates}, _from, state) do
    updates = Map.put(updates, :last_activity, DateTime.utc_now())

    case state.storage.update(state.storage_state, session_id, updates) do
      {:ok, session, new_storage_state} ->
        {:reply, {:ok, session}, %{state | storage_state: new_storage_state}}

      {:error, :session_not_found, new_storage_state} ->
        {:reply, {:error, :not_found}, %{state | storage_state: new_storage_state}}
    end
  end

  @impl GenServer
  def handle_call({:unregister, session_id}, _from, state) do
    case state.storage.unregister(state.storage_state, session_id) do
      {:ok, new_storage_state} ->
        {:reply, :ok, %{state | storage_state: new_storage_state}}

      {:error, :session_not_found, new_storage_state} ->
        {:reply, {:error, :not_found}, %{state | storage_state: new_storage_state}}
    end
  end

  @impl GenServer
  def handle_call({:touch, session_id}, _from, state) do
    case state.storage.touch(state.storage_state, session_id) do
      {:ok, new_storage_state} ->
        {:reply, :ok, %{state | storage_state: new_storage_state}}

      {:error, :session_not_found, new_storage_state} ->
        {:reply, {:error, :not_found}, %{state | storage_state: new_storage_state}}
    end
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    if state.expiry_ms do
      case state.storage.expire_inactive(state.storage_state, state.expiry_ms) do
        {:ok, _count, new_storage_state} ->
          Process.send_after(self(), :cleanup, @cleanup_interval_ms)
          {:noreply, %{state | storage_state: new_storage_state}}
      end
    else
      {:noreply, state}
    end
  end

  # Private functions

  defp get_server_name(module) when is_atom(module) do
    ServerRegistry.server(module)
  end

  defp get_server_name(name), do: name
end
