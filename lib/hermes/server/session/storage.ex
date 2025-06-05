defmodule Hermes.Server.Session.Storage do
  @moduledoc """
  Behaviour for session storage backends in MCP servers.

  This module defines the interface that all session storage implementations must follow.
  It supports different storage backends (ETS, Registry, distributed stores) while providing
  a consistent API for session management.

  ## Design Principles

  - **Flexibility**: Support different storage backends through a behaviour
  - **Scalability**: Enable cluster-wide session management
  - **Ephemeral**: Sessions are not persisted to disk (by default)
  - **OTP Compliance**: Integrate well with Elixir/OTP patterns

  ## Session Structure

  Each session contains:
  - `id` - Unique session identifier
  - `server` - Server module name (for Registry lookup)
  - `transport` - Transport type and reference tuple
  - `metadata` - Additional session-specific data
  - `created_at` - Session creation timestamp
  - `last_activity` - Last activity timestamp

  ## Implementation Example

      defmodule MyApp.SessionStorage do
        @behaviour Hermes.Server.Session.Storage

        def init(opts) do
          # Initialize storage backend
          {:ok, state}
        end

        def register(state, session_id, session_data) do
          # Store session
          {:ok, state}
        end

        # ... implement other callbacks
      end
  """

  @type session_id :: String.t()
  @type session_data :: %{
          id: session_id(),
          server: module() | GenServer.name(),
          transport: {atom(), term()},
          metadata: map(),
          created_at: DateTime.t(),
          last_activity: DateTime.t()
        }
  @type state :: term()
  @type error :: {:error, :session_exists | :session_not_found | term()}

  @doc """
  Initializes the storage backend.

  Called when the storage process starts. Should set up any necessary
  resources (tables, connections, etc).

  ## Parameters
    - `opts` - Initialization options specific to the storage implementation

  ## Returns
    - `{:ok, state}` - Initial state for the storage backend
    - `{:error, reason}` - If initialization fails
  """
  @callback init(opts :: keyword()) :: {:ok, state()} | {:error, reason :: term()}

  @doc """
  Registers a new session in the storage.

  ## Parameters
    - `state` - Current storage state
    - `session_id` - Unique identifier for the session
    - `session_data` - Session information to store

  ## Returns
    - `{:ok, state}` - Updated state after successful registration
    - `{:error, :session_exists, state}` - If session ID already exists
    - `{:error, reason, state}` - For other errors
  """
  @callback register(state(), session_id(), session_data()) ::
              {:ok, state()} | {:error, :session_exists | term(), state()}

  @doc """
  Retrieves a session by ID.

  ## Parameters
    - `state` - Current storage state
    - `session_id` - Session ID to look up

  ## Returns
    - `{:ok, session_data, state}` - Session data if found
    - `{:error, :session_not_found, state}` - If session doesn't exist
  """
  @callback lookup(state(), session_id()) ::
              {:ok, session_data(), state()} | {:error, :session_not_found, state()}

  @doc """
  Lists all active sessions.

  ## Parameters
    - `state` - Current storage state
    - `opts` - Options for filtering/pagination
      - `:server` - Filter by server module
      - `:transport_type` - Filter by transport type
      - `:limit` - Maximum number of results
      - `:offset` - Pagination offset

  ## Returns
    - `{:ok, sessions, state}` - List of sessions matching criteria
  """
  @callback list(state(), opts :: keyword()) :: {:ok, [session_data()], state()}

  @doc """
  Updates an existing session.

  ## Parameters
    - `state` - Current storage state
    - `session_id` - Session ID to update
    - `updates` - Map of fields to update

  ## Returns
    - `{:ok, updated_session, state}` - Updated session data
    - `{:error, :session_not_found, state}` - If session doesn't exist
  """
  @callback update(state(), session_id(), updates :: map()) ::
              {:ok, session_data(), state()} | {:error, :session_not_found, state()}

  @doc """
  Removes a session from storage.

  ## Parameters
    - `state` - Current storage state
    - `session_id` - Session ID to remove

  ## Returns
    - `{:ok, state}` - Updated state after removal
    - `{:error, :session_not_found, state}` - If session doesn't exist
  """
  @callback unregister(state(), session_id()) ::
              {:ok, state()} | {:error, :session_not_found, state()}

  @doc """
  Removes all sessions from storage.

  ## Parameters
    - `state` - Current storage state

  ## Returns
    - `{:ok, count, state}` - Number of sessions cleared and updated state
  """
  @callback clear(state()) :: {:ok, count :: non_neg_integer(), state()}

  @doc """
  Updates the last activity timestamp for a session.

  ## Parameters
    - `state` - Current storage state
    - `session_id` - Session ID to update

  ## Returns
    - `{:ok, state}` - Updated state
    - `{:error, :session_not_found, state}` - If session doesn't exist
  """
  @callback touch(state(), session_id()) ::
              {:ok, state()} | {:error, :session_not_found, state()}

  @doc """
  Removes sessions that haven't been active within the timeout period.

  ## Parameters
    - `state` - Current storage state
    - `timeout_ms` - Timeout in milliseconds

  ## Returns
    - `{:ok, count, state}` - Number of expired sessions and updated state
  """
  @callback expire_inactive(state(), timeout_ms :: non_neg_integer()) ::
              {:ok, count :: non_neg_integer(), state()}
end
