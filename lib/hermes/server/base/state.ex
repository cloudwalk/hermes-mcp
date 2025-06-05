defmodule Hermes.Server.Base.State do
  @moduledoc """
  Manages state for the Hermes MCP server base implementation.

  This module provides a structured representation of server state during the MCP lifecycle,
  including initialization status, protocol negotiation, and server capabilities.

  ## State Structure

  Each server state includes:
  - `module`: The module implementing the server behavior
  - `server_info`: Server information (name, version)
  - `capabilities`: Server capabilities to advertise
  - `protocol_version`: Negotiated MCP protocol version
  - `supported_versions`: List of protocol versions the server supports
  - `transport`: Transport configuration
  - `frame`: Server frame (similar to LiveView socket)
  - `initialized`: Whether the server has completed initialization
  - `client_info`: Client information received during initialization
  - `client_capabilities`: Client capabilities received during initialization

  ## Examples

  ```elixir
  # Create a new server state
  state = Hermes.Server.Base.State.new(%{
    module: MyServer,
    server_info: %{"name" => "MyServer", "version" => "1.0.0"},
    capabilities: %{"tools" => %{}, "resources" => %{}},
    supported_versions: ["2025-03-26", "2024-11-05"],
    transport: %{layer: Hermes.Server.Transport.STDIO, name: MyTransport}
  })

  # Update state after initialization
  updated_state = Hermes.Server.Base.State.update_from_init(
    state,
    "2025-03-26",
    %{"name" => "Client", "version" => "1.0.0"},
    %{"roots" => %{}}
  )
  ```
  """

  alias Hermes.Server.Frame

  @type t :: %__MODULE__{
          module: module(),
          server_info: map(),
          capabilities: map(),
          protocol_version: String.t() | nil,
          supported_versions: [String.t()],
          transport: map(),
          frame: Frame.t() | nil,
          initialized: boolean(),
          client_info: map() | nil,
          client_capabilities: map() | nil,
          log_level: String.t()
        }

  defstruct [
    :module,
    :server_info,
    :capabilities,
    :protocol_version,
    :supported_versions,
    :transport,
    :frame,
    :log_level,
    initialized: false,
    client_info: nil,
    client_capabilities: nil
  ]

  @doc """
  Creates a new server state with the given options.

  ## Parameters

    * `opts` - Map containing the initialization options

  ## Options

    * `:module` - The module implementing the server behavior (required)
    * `:server_info` - Server information map (required)
    * `:capabilities` - Server capabilities to advertise (required)
    * `:supported_versions` - List of supported protocol versions (required)
    * `:transport` - Transport configuration (required)

  ## Examples

      iex> Hermes.Server.Base.State.new(%{
      ...>   module: MyServer,
      ...>   server_info: %{"name" => "MyServer", "version" => "1.0.0"},
      ...>   capabilities: %{"tools" => %{}},
      ...>   supported_versions: ["2025-03-26"],
      ...>   transport: %{layer: Hermes.Server.Transport.STDIO, name: MyTransport}
      ...> })
      %Hermes.Server.Base.State{
        module: MyServer,
        server_info: %{"name" => "MyServer", "version" => "1.0.0"},
        capabilities: %{"tools" => %{}},
        supported_versions: ["2025-03-26"],
        transport: %{layer: Hermes.Server.Transport.STDIO, name: MyTransport}
      }
  """
  @spec new(map()) :: t()
  def new(opts) do
    %__MODULE__{
      module: opts.module,
      server_info: opts.server_info,
      capabilities: opts.capabilities,
      supported_versions: opts.supported_versions,
      transport: opts.transport
    }
  end

  @doc """
  Updates the state with a frame from the module's init callback.

  ## Parameters

    * `state` - The current server state
    * `frame` - The frame returned from the module's init callback

  ## Examples

      iex> frame = Frame.new(%{custom: "data"})
      iex> updated_state = Hermes.Server.Base.State.put_frame(state, frame)
      iex> updated_state.frame
      %Frame{assigns: %{custom: "data"}}
  """
  @spec put_frame(t(), Frame.t()) :: t()
  def put_frame(state, %Frame{} = frame) do
    %{state | frame: frame}
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
      iex> params = %{"protocolVersion" => "2025-03-26", "capabilities" => capabilities, "clientInfo" => client_info}
      iex> updated_state = Hermes.Server.Base.State.update_from_initialization(state, params)
      iex> updated_state.initialized
      true
      iex> updated_state.protocol_version
      "2025-03-26"
  """
  @spec update_from_initialization(t(), map) :: t()
  def update_from_initialization(state, initialize_params) do
    %{
      state
      | protocol_version: initialize_params["protocolVersion"],
        client_info: initialize_params["clientInfo"],
        client_capabilities: initialize_params["capabilities"]
    }
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
  @spec initialized?(t()) :: boolean()
  def initialized?(state) do
    state.initialized
  end

  @doc """
  Gets the negotiated protocol version.

  ## Parameters

    * `state` - The current server state

  ## Examples

      iex> Hermes.Server.Base.State.get_protocol_version(initialized_state)
      "2025-03-26"
  """
  @spec get_protocol_version(t()) :: String.t() | nil
  def get_protocol_version(state) do
    state.protocol_version
  end

  @doc """
  Gets the client information.

  ## Parameters

    * `state` - The current server state

  ## Examples

      iex> Hermes.Server.Base.State.get_client_info(initialized_state)
      %{"name" => "ClientApp", "version" => "2.0.0"}
  """
  @spec get_client_info(t()) :: map() | nil
  def get_client_info(state) do
    state.client_info
  end

  @doc """
  Gets the client capabilities.

  ## Parameters

    * `state` - The current server state

  ## Examples

      iex> Hermes.Server.Base.State.get_client_capabilities(initialized_state)
      %{"roots" => %{"listChanged" => true}}
  """
  @spec get_client_capabilities(t()) :: map() | nil
  def get_client_capabilities(state) do
    state.client_capabilities
  end

  @doc """
  Assigns a value to the server frame.

  Similar to `Hermes.Server.Frame.assign/3`, but operates on the state's frame.

  ## Parameters

    * `state` - The current server state
    * `key` - The key to assign
    * `value` - The value to assign

  ## Examples

      iex> updated_state = Hermes.Server.Base.State.assign(state, :user_id, 123)
      iex> updated_state.frame.assigns.user_id
      123
  """
  @spec assign(t(), atom(), any()) :: t()
  def assign(%{frame: nil} = state, key, value) when is_atom(key) do
    frame = Frame.new(%{key => value})
    %{state | frame: frame}
  end

  def assign(%{frame: frame} = state, key, value) when is_atom(key) do
    updated_frame = Frame.assign(frame, key, value)
    %{state | frame: updated_frame}
  end

  @doc """
  Assigns multiple values to the server frame.

  ## Parameters

    * `state` - The current server state
    * `assigns` - Map or keyword list of assigns

  ## Examples

      iex> updated_state = Hermes.Server.Base.State.assign(state, %{user_id: 123, name: "John"})
      iex> updated_state.frame.assigns.user_id
      123
  """
  @spec assign(t(), Enumerable.t()) :: t()
  def assign(%{frame: nil} = state, assigns) when is_map(assigns) or is_list(assigns) do
    frame = Frame.new(assigns)
    %{state | frame: frame}
  end

  def assign(%{frame: frame} = state, assigns) when is_map(assigns) or is_list(assigns) do
    updated_frame = Frame.assign(frame, assigns)
    %{state | frame: updated_frame}
  end

  @doc """
  Negotiates the protocol version based on client request and server support.

  Returns the negotiated version according to MCP spec:
  - If server supports the requested version, returns that version
  - Otherwise, returns the latest version the server supports

  ## Parameters

    * `state` - The current server state
    * `requested_version` - The version requested by the client

  ## Examples

      iex> state = %State{supported_versions: ["2025-03-26", "2024-11-05"]}
      iex> Hermes.Server.Base.State.negotiate_protocol_version(state, "2025-03-26")
      "2025-03-26"
      
      iex> Hermes.Server.Base.State.negotiate_protocol_version(state, "2023-01-01")
      "2025-03-26"
  """
  @spec negotiate_protocol_version(t(), String.t()) :: String.t()
  def negotiate_protocol_version(state, requested_version) do
    if requested_version in state.supported_versions do
      requested_version
    else
      hd(state.supported_versions)
    end
  end

  defguard is_supported_capability(state, capability) when is_map_key(state.capabilites, capability)
end
