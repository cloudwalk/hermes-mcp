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

  alias Hermes.Server.Registry

  @type t :: %__MODULE__{
          protocol_version: String.t() | nil,
          initialized: boolean(),
          client_info: map() | nil,
          client_capabilities: map() | nil,
          log_level: String.t(),
          id: String.t() | nil
        }

  defstruct [
    :id,
    :protocol_version,
    :log_level,
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

    Agent.start_link(fn -> new(id: session_id) end, name: name)
  end

  @doc """
  Creates a new server state with the given options.

  ## Parameters

    * `opts` - Map containing the initialization options
  """
  @spec new(Enumerable.t()) :: t()
  def new(opts), do: struct(__MODULE__, opts)

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
      iex> params = %{"protocolVersion" => "2025-03-26", "capabilities" => capabilities, "clientInfo" => client_info}
      iex> updated_state = Hermes.Server.Base.State.update_from_initialization(state, params)
      iex> updated_state.initialized
      true
      iex> updated_state.protocol_version
      "2025-03-26"
  """
  @spec update_from_initialization(GenServer.name(), String.t(), map, map) :: :ok
  def update_from_initialization(session, negotiated_version, client_info, capabilities) do
    Agent.update(session, fn state ->
      %{state | protocol_version: negotiated_version, client_info: client_info, client_capabilities: capabilities}
    end)
  end

  @doc """
  Checks if the server is initialized.

  ## Parameters

    * `state` - The current server state

  ## Examples

      iex> Hermes.Server.Base.State.initialized?(uninitialized_state)
      false
      
      iex> Hermes.Server.Base.State.initialized?(initialized_state)
      true
  """
  @spec initialized?(GenServer.name()) :: boolean()
  def initialized?(session) do
    Agent.get(session, & &1.initialized)
  end

  @doc """
  Marks the session as initialized.
  """
  @spec mark_initialized(GenServer.name()) :: :ok
  def mark_initialized(session) do
    Agent.update(session, fn state -> %{state | initialized: true} end)
  end

  @doc """
  Gets the negotiated protocol version.

  ## Parameters

    * `state` - The current server state

  ## Examples

      iex> Hermes.Server.Base.State.get_protocol_version(initialized_state)
      "2025-03-26"
  """
  @spec get_protocol_version(GenServer.name()) :: String.t() | nil
  def get_protocol_version(session) do
    Agent.get(session, & &1.protocol_version)
  end

  @doc """
  Gets the client information.

  ## Parameters

    * `state` - The current server state

  ## Examples

      iex> Hermes.Server.Base.State.get_client_info(initialized_state)
      %{"name" => "ClientApp", "version" => "2.0.0"}
  """
  @spec get_client_info(GenServer.name()) :: map() | nil
  def get_client_info(session) do
    Agent.get(session, & &1.client_info)
  end

  @doc """
  Gets the client capabilities.

  ## Parameters

    * `state` - The current server state

  ## Examples

      iex> Hermes.Server.Base.State.get_client_capabilities(initialized_state)
      %{"roots" => %{"listChanged" => true}}
  """
  @spec get_client_capabilities(GenServer.name()) :: map() | nil
  def get_client_capabilities(session) do
    Agent.get(session, & &1.client_capabilities)
  end

  @doc """
  Updates the log level.
  """
  @spec set_log_level(GenServer.name(), String.t()) :: :ok
  def set_log_level(session, level) do
    Agent.update(session, fn state -> %{state | log_level: level} end)
  end

  @doc """
  Gets the entire session state.
  For debugging and testing purposes.
  """
  @spec get(GenServer.name()) :: t()
  def get(session) do
    Agent.get(session, & &1)
  end

  @doc """
  Checks if a session exists.
  """
  @spec exists?(module(), String.t()) :: boolean()
  def exists?(server, session_id) do
    not is_nil(Registry.whereis_server_session(server, session_id))
  end
end
