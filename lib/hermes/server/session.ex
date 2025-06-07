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

  alias Hermes.Server.Registry

  @type t :: %__MODULE__{
          protocol_version: String.t() | nil,
          initialized: boolean(),
          name: GenServer.name() | nil,
          client_info: map() | nil,
          client_capabilities: map() | nil,
          log_level: String.t(),
          id: String.t() | nil
        }

  defstruct [
    :id,
    :protocol_version,
    :log_level,
    :name,
    initialized: false,
    client_info: nil,
    client_capabilities: nil
  ]

  @doc """
  Starts a new session agent with initial state.
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    server = Keyword.fetch!(opts, :server)
    session_id = Keyword.fetch!(opts, :session_id)
    name = Registry.server_session(server, session_id)

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
  Checks if a session exists.
  """
  @spec exists?(module(), String.t()) :: boolean()
  def exists?(server, session_id) do
    not is_nil(Registry.whereis_server_session(server, session_id))
  end
end
