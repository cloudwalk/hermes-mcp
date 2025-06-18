defmodule Hermes.Server.Session do
  @moduledoc """
  Manages state for the Hermes MCP server base implementation.

  This module provides a structured representation of server state during the MCP lifecycle,
  including initialization status, protocol negotiation, and server capabilities.

  ## State Structure

  Each server state includes:
  - `protocol_version`: Negotiated MCP protocol version
  - `frame`: Server frame (similar to LiveView socket)
  - `initialized`: Whether the server has completed initialization
  - `client_info`: Client information received during initialization
  - `client_capabilities`: Client capabilities received during initialization
  """

  use Agent, restart: :transient

  @type t :: %__MODULE__{
          protocol_version: String.t() | nil,
          initialized: boolean(),
          name: GenServer.name() | nil,
          client_info: map() | nil,
          client_capabilities: map() | nil,
          log_level: String.t(),
          id: String.t() | nil,
          pending_requests: %{String.t() => %{started_at: integer(), method: String.t()}}
        }

  defstruct [
    :id,
    :protocol_version,
    :log_level,
    :name,
    initialized: false,
    client_info: nil,
    client_capabilities: nil,
    pending_requests: %{}
  ]

  @doc """
  Starts a new session agent with initial state.
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    session_id = Keyword.fetch!(opts, :session_id)
    name = Keyword.fetch!(opts, :name)

    Agent.start_link(fn -> new(id: session_id, name: name) end, name: name)
  end

  @doc """
  Creates a new server state with the given options.

  ## Parameters

    * `opts` - Map containing the initialization options
  """
  @spec new(Enumerable.t()) :: t()
  def new(opts), do: struct(__MODULE__, opts)

  @doc """
  Guard to check if a session has been initialized.

  ## Examples

      iex> session = %Session{initialized: true}
      iex> is_initialized(session)
      true
  """
  defguard is_initialized(session) when session.initialized

  @doc """
  Retrieves the current state of a session.

  ## Parameters

    * `session` - The session agent name or PID

  ## Returns

  The current session state as a `%Session{}` struct.

  ## Examples

      iex> session_state = Session.get(session_name)
      %Session{initialized: true, protocol_version: "2025-03-26"}
  """
  @spec get(GenServer.name()) :: t
  def get(session) do
    Agent.get(session, & &1)
  end

  @doc """
  Updates state after successful initialization handshake.

  This function:
  1. Sets the negotiated protocol version
  2. Stores client information and capabilities
  3. Marks the server as initialized

  ## Parameters

    * `state` - The current server state
    * `protocol_version` - The negotiated protocol version
    * `client_info` - Client information from the initialize request
    * `client_capabilities` - Client capabilities from the initialize request

  ## Examples

      iex> client_info = %{"name" => "hello", "version" => "1.0.0"}
      iex> capabilities = %{"sampling" => %{}}
      iex> Hermes.Server.Session.update_from_initialization(session, "2025-03-26", client_info, capabilities)
      :ok
  """
  @spec update_from_initialization(GenServer.name(), String.t(), map, map) :: :ok
  def update_from_initialization(session, negotiated_version, client_info, capabilities) do
    Agent.update(session, fn state ->
      %{state | protocol_version: negotiated_version, client_info: client_info, client_capabilities: capabilities}
    end)
  end

  @doc """
  Marks the session as initialized.
  """
  @spec mark_initialized(GenServer.name()) :: :ok
  def mark_initialized(session) do
    Agent.update(session, fn state -> %{state | initialized: true} end)
  end

  @doc """
  Updates the log level.
  """
  @spec set_log_level(GenServer.name(), String.t()) :: :ok
  def set_log_level(session, level) do
    Agent.update(session, fn state -> %{state | log_level: level} end)
  end

  @doc """
  Tracks a new pending request in the session.

  ## Parameters

    * `session` - The session agent name or PID
    * `request_id` - The unique request ID
    * `method` - The MCP method being called

  ## Examples

      iex> Session.track_request(session, "req_123", "tools/call")
      :ok
  """
  @spec track_request(GenServer.name(), String.t(), String.t()) :: :ok
  def track_request(session, request_id, method) do
    Agent.update(session, fn state ->
      request_info = %{
        started_at: System.system_time(:millisecond),
        method: method
      }

      %{state | pending_requests: Map.put(state.pending_requests, request_id, request_info)}
    end)
  end

  @doc """
  Removes a completed request from tracking.

  ## Parameters

    * `session` - The session agent name or PID
    * `request_id` - The request ID to remove

  ## Returns

  The request info if found, nil otherwise.

  ## Examples

      iex> Session.complete_request(session, "req_123")
      %{started_at: 1234567890, method: "tools/call"}
  """
  @spec complete_request(GenServer.name(), String.t()) :: map() | nil
  def complete_request(session, request_id) do
    Agent.get_and_update(session, fn state ->
      {request_info, pending_requests} = Map.pop(state.pending_requests, request_id)
      {request_info, %{state | pending_requests: pending_requests}}
    end)
  end

  @doc """
  Checks if a request is currently pending.

  ## Parameters

    * `session` - The session agent name or PID
    * `request_id` - The request ID to check

  ## Examples

      iex> Session.has_pending_request?(session, "req_123")
      true
  """
  @spec has_pending_request?(GenServer.name(), String.t()) :: boolean()
  def has_pending_request?(session, request_id) do
    Agent.get(session, fn state ->
      Map.has_key?(state.pending_requests, request_id)
    end)
  end

  @doc """
  Gets all pending requests for a session.

  ## Parameters

    * `session` - The session agent name or PID

  ## Examples

      iex> Session.get_pending_requests(session)
      %{"req_123" => %{started_at: 1234567890, method: "tools/call"}}
  """
  @spec get_pending_requests(GenServer.name()) :: map()
  def get_pending_requests(session) do
    Agent.get(session, & &1.pending_requests)
  end
end
