defmodule Hermes.Server do
  @moduledoc "high level mcp server implementation"

  alias Hermes.Server.ConfigurationError

  @server_capabilities ~w(prompts tools resources logging)a
  @protocol_versions ~w(2025-03-26 2024-05-11 2024-10-07)

  defguard is_server_capability(capability) when capability in @server_capabilities

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

  defguard is_supported_capability(capabilities, capability) when is_map_key(capabilities, capability)
end
