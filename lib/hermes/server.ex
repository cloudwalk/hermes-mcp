defmodule Hermes.Server do
  @moduledoc """
  High-level MCP server implementation.

  This module provides the main API for implementing MCP (Model Context Protocol) servers.
  It includes macros and functions to simplify server creation with standardized capabilities,
  protocol version support, and supervision tree setup.

  ## Usage

      defmodule MyServer do
        use Hermes.Server,
          name: "My MCP Server",
          version: "1.0.0",
          capabilities: [:tools, :resources, :logging]

        @impl Hermes.Server.Behaviour
        def init(_arg, frame) do
          {:ok, frame}
        end

        @impl Hermes.Server.Behaviour
        def handle_request(%{"method" => "tools/list"}, frame) do
          {:reply, %{"tools" => []}, frame}
        end

        @impl Hermes.Server.Behaviour
        def handle_notification(_notification, frame) do
          {:noreply, frame}
        end
      end

  ## Server Capabilities

  The following capabilities are supported:
  - `:prompts` - Server can provide prompt templates
  - `:tools` - Server can execute tools/functions
  - `:resources` - Server can provide resources (files, data, etc.)
  - `:logging` - Server supports log level configuration

  Capabilities can be configured with options:
  - `subscribe?: boolean` - Whether the capability supports subscriptions (resources only)
  - `list_changed?: boolean` - Whether the capability emits list change notifications

  ## Protocol Versions

  By default, servers support the following protocol versions:
  - "2025-03-26" - Latest protocol version
  - "2024-10-07" - Previous stable version
  - "2024-05-11" - Legacy version for backward compatibility
  """

  alias Hermes.Server.ConfigurationError

  @server_capabilities ~w(prompts tools resources logging)a
  @protocol_versions ~w(2025-03-26 2024-05-11 2024-10-07)

  @doc """
  Starts a server with its supervision tree.

  ## Examples

      # Start with default options
      Hermes.Server.start_link(MyServer, :ok, transport: :stdio)
      
      # Start with custom name
      Hermes.Server.start_link(MyServer, %{}, 
        transport: :stdio,
        name: {:local, :my_server}
      )
  """
  defdelegate start_link(mod, init_arg, opts), to: Hermes.Server.Supervisor

  @doc """
  Guard to check if a capability is valid.

  ## Examples

      iex> is_server_capability(:tools)
      true

      iex> is_server_capability(:invalid)
      false
  """
  defguard is_server_capability(capability) when capability in @server_capabilities

  @doc """
  Guard to check if a capability is supported by the server.

  ## Examples

      iex> capabilities = %{"tools" => %{}}
      iex> is_supported_capability(capabilities, "tools")
      true
  """
  defguard is_supported_capability(capabilities, capability) when is_map_key(capabilities, capability)

  @doc false
  defmacro __using__(opts) do
    module = __CALLER__.module

    capabilities = Enum.reduce(opts[:capabilities] || [], %{}, &parse_capability/2)
    protocol_versions = opts[:protocol_versions] || @protocol_versions
    name = opts[:name]
    version = opts[:version]

    if is_nil(name) and is_nil(version) do
      raise ConfigurationError, module: module, missing_key: :both
    end

    if is_nil(name), do: raise(ConfigurationError, module: module, missing_key: :name)
    if is_nil(version), do: raise(ConfigurationError, module: module, missing_key: :version)

    quote do
      @behaviour Hermes.Server.Behaviour

      import Hermes.Server.Frame

      alias Hermes.MCP.Message

      require Message

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor,
          restart: :permanent
        }
      end

      @impl Hermes.Server.Behaviour
      def server_info do
        %{"name" => unquote(name), "version" => unquote(version)}
      end

      @impl Hermes.Server.Behaviour
      def server_capabilities, do: unquote(Macro.escape(capabilities))

      @impl Hermes.Server.Behaviour
      def supported_protocol_versions, do: unquote(protocol_versions)

      defoverridable server_info: 0, server_capabilities: 0, supported_protocol_versions: 0, child_spec: 1
    end
  end

  defp parse_capability(capability, %{} = capabilities) when is_server_capability(capability) do
    Map.put(capabilities, to_string(capability), %{})
  end

  defp parse_capability({:resources, opts}, %{} = capabilities) do
    subscribe? = opts[:subscribe?]
    list_changed? = opts[:list_changed?]

    capabilities
    |> Map.put("resources", %{})
    |> then(&if(is_nil(subscribe?), do: &1, else: Map.put(&1, :subscribe, subscribe?)))
    |> then(&if(is_nil(list_changed?), do: &1, else: Map.put(&1, :subscribe, list_changed?)))
  end

  defp parse_capability({capability, opts}, %{} = capabilities) when is_server_capability(capability) do
    list_changed? = opts[:list_changed?]

    capabilities
    |> Map.put(to_string(capability), %{})
    |> then(&if(is_nil(list_changed?), do: &1, else: Map.put(&1, :subscribe, list_changed?)))
  end
end
