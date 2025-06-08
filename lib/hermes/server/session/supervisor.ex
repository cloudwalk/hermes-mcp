defmodule Hermes.Server.Session.Supervisor do
  @moduledoc """
  Dynamic supervisor for managing per-session server processes.

  This module provides a clean API for starting and stopping session-specific
  server instances without creating atoms dynamically. It enables multi-session
  support for transports like StreamableHTTP that handle multiple concurrent
  client connections.

  ## Architecture

  The session supervisor is part of the server supervision tree:
  ```
  Server.Supervisor
  ├── Server.Base (message handler)
  ├── Server.Session.Supervisor (this module)
  │   ├── Session Agent 1
  │   ├── Session Agent 2
  │   └── Session Agent N
  └── Transport (STDIO, StreamableHTTP, etc.)
  ```

  ## Session Lifecycle

  1. **Creation**: When a new client connects, a session is created via `create_session/2`
  2. **State Management**: Each session maintains its own state (protocol version,
     client info, initialization status)
  3. **Isolation**: Sessions are isolated from each other, preventing cross-contamination
  4. **Cleanup**: Sessions are terminated when clients disconnect or on server shutdown

  ## Usage

  Sessions are typically managed automatically by the Base server:

      # Base server creates a session when needed
      {:ok, pid} = Session.Supervisor.create_session(MyServer, session_id)

      # Sessions can be explicitly closed
      :ok = Session.Supervisor.close_session(MyServer, session_id)

  ## Benefits

  - **Resource Management**: Automatic cleanup of disconnected sessions
  - **Fault Tolerance**: Session crashes don't affect other sessions
  - **Scalability**: Support for many concurrent clients
  - **State Isolation**: Each client has independent state
  """

  use DynamicSupervisor

  alias Hermes.Server.Session

  @kind :session_supervisor

  @doc """
  Starts the session supervisor.

  ## Parameters
    * `server` - The server module atom

  ## Returns
    * `{:ok, pid}` - Supervisor started successfully
    * `{:error, reason}` - Failed to start supervisor

  ## Examples

      {:ok, _pid} = Session.Supervisor.start_link(MyServer)
  """
  def start_link(opts \\ []) do
    server = Keyword.fetch!(opts, :server)
    registry = Keyword.get(opts, :registry, Hermes.Server.Registry)
    name = registry.supervisor(@kind, server)
    DynamicSupervisor.start_link(__MODULE__, server, name: name)
  end

  @doc """
  Creates a new session for a client connection.

  ## Parameters
    * `registry` - The registry module to use to retrieve processes names
    * `server` - The server module atom
    * `session_id` - Unique identifier for the session (typically from transport)

  ## Returns
    * `{:ok, pid}` - Session created successfully
    * `{:error, {:already_started, pid}}` - Session already exists
    * `{:error, reason}` - Failed to create session

  ## Examples

      # Create a new session for a client
      {:ok, session_pid} = Session.Supervisor.create_session(MyRegistry, MyServer, "session-123")

      # Attempting to create duplicate session
      {:error, {:already_started, ^session_pid}} = 
        Session.Supervisor.create_session(MyRegistry, MyServer, "session-123")
  """
  def create_session(registry \\ Hermes.Server.Registry, server, session_id) do
    name = registry.supervisor(@kind, server)
    session_name = registry.server_session(server, session_id)
    DynamicSupervisor.start_child(name, {Session, session_id: session_id, name: session_name})
  end

  @doc """
  Terminates a session and cleans up its resources.

  ## Parameters
    * `registry` - The registry module to use to retrieve processes names
    * `server` - The server module atom
    * `session_id` - The session identifier to terminate

  ## Returns
    * `:ok` - Session terminated successfully
    * `{:error, :not_found}` - Session does not exist

  ## Examples

      # Close an existing session
      :ok = Session.Supervisor.close_session(MyRegistry, MyServer, "session-123")

      # Attempting to close non-existent session
      {:error, :not_found} = Session.Supervisor.close_session(MyRegistry, MyServer, "unknown")
  """
  def close_session(registry \\ Hermes.Server.Registry, server, session_id) when is_binary(session_id) do
    name = registry.supervisor(@kind, server)

    if pid = registry.whereis_server_session(server, session_id) do
      DynamicSupervisor.terminate_child(name, pid)
    else
      {:error, :not_found}
    end
  end

  @impl DynamicSupervisor
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
