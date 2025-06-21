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

  alias Hermes.Server.Component
  alias Hermes.Server.ConfigurationError
  alias Hermes.Server.Handlers

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
    quote do
      @behaviour Hermes.Server.Behaviour

      import Hermes.Server, only: [component: 1, component: 2]

      import Hermes.Server.Base,
        only: [
          send_resources_list_changed: 1,
          send_resource_updated: 2,
          send_resource_updated: 3,
          send_prompts_list_changed: 1,
          send_tools_list_changed: 1,
          send_log_message: 3,
          send_log_message: 4,
          send_progress: 4,
          send_progress: 5
        ]

      import Hermes.Server.Frame

      require Hermes.MCP.Message

      Module.register_attribute(__MODULE__, :components, accumulate: true)
      Module.register_attribute(__MODULE__, :hermes_server_opts, persist: true)
      Module.put_attribute(__MODULE__, :hermes_server_opts, unquote(opts))

      @before_compile Hermes.Server
      @after_compile Hermes.Server

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor,
          restart: :permanent
        }
      end

      defoverridable child_spec: 1
    end
  end

  @doc """
  Registers a component (tool, prompt, or resource) with the server.

  ## Examples

      # Register with auto-derived name
      component MyServer.Tools.Calculator
      
      # Register with custom name
      component MyServer.Tools.FileManager, name: "files"
  """
  defmacro component(module, opts \\ []) do
    quote bind_quoted: [module: module, opts: opts] do
      if not Component.component?(module) do
        raise CompileError,
          description:
            "Module #{to_string(module)} is not a valid component. " <>
              "Use `use Hermes.Server.Component, type: :tool/:prompt/:resource`"
      end

      @components {Component.get_type(module), opts[:name] || Hermes.Server.__derive_component_name__(module), module}
    end
  end

  @doc false
  def __derive_component_name__(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  @doc false
  defmacro __before_compile__(env) do
    components = Module.get_attribute(env.module, :components, [])
    opts = get_server_opts(env.module)

    tools = for {:tool, name, mod} <- components, do: {name, mod}
    prompts = for {:prompt, name, mod} <- components, do: {name, mod}
    resources = for {:resource, name, mod} <- components, do: {name, mod}

    quote do
      def __components__(:tool), do: unquote(Macro.escape(tools))
      def __components__(:prompt), do: unquote(Macro.escape(prompts))
      def __components__(:resource), do: unquote(Macro.escape(resources))
      def __components__(_), do: []

      @impl Hermes.Server.Behaviour
      def handle_request(%{} = request, frame) do
        Handlers.handle(request, __MODULE__, frame)
      end

      unquote(maybe_define_server_info(env.module, opts[:name], opts[:version]))
      unquote(maybe_define_server_capabilities(env.module, opts[:capabilities]))
      unquote(maybe_define_protocol_versions(env.module, opts[:protocol_versions]))

      defoverridable handle_request: 2
    end
  end

  defp get_server_opts(module) do
    case Module.get_attribute(module, :hermes_server_opts, []) do
      [opts] when is_list(opts) -> opts
      opts when is_list(opts) -> opts
      _ -> []
    end
  end

  defp maybe_define_server_info(module, name, version) do
    if not Module.defines?(module, {:server_info, 0}) or is_nil(name) or is_nil(version) do
      quote do
        @impl Hermes.Server.Behaviour
        def server_info, do: %{"name" => unquote(name), "version" => unquote(version)}
      end
    end
  end

  defp maybe_define_server_capabilities(module, capabilities_config) do
    if not Module.defines?(module, {:server_capabilities, 0}) do
      capabilities = Enum.reduce(capabilities_config || [], %{}, &parse_capability/2)

      quote do
        @impl Hermes.Server.Behaviour
        def server_capabilities, do: unquote(Macro.escape(capabilities))
      end
    end
  end

  defp maybe_define_protocol_versions(module, protocol_versions) do
    if not Module.defines?(module, {:supported_protocol_versions, 0}) do
      versions = protocol_versions || @protocol_versions

      quote do
        @impl Hermes.Server.Behaviour
        def supported_protocol_versions, do: unquote(versions)
      end
    end
  end

  def parse_capability(capability, %{} = capabilities) when is_server_capability(capability) do
    Map.put(capabilities, to_string(capability), %{})
  end

  def parse_capability({:resources, opts}, %{} = capabilities) do
    subscribe? = opts[:subscribe?]
    list_changed? = opts[:list_changed?]

    capabilities
    |> Map.put("resources", %{})
    |> then(&if(is_nil(subscribe?), do: &1, else: Map.put(&1, :subscribe, subscribe?)))
    |> then(&if(is_nil(list_changed?), do: &1, else: Map.put(&1, :listChanged, list_changed?)))
  end

  def parse_capability({capability, opts}, %{} = capabilities) when is_server_capability(capability) do
    list_changed? = opts[:list_changed?]

    capabilities
    |> Map.put(to_string(capability), %{})
    |> then(&if(is_nil(list_changed?), do: &1, else: Map.put(&1, :listChanged, list_changed?)))
  end

  @doc false
  def __after_compile__(env, _bytecode) do
    module = env.module

    opts =
      case Module.get_attribute(module, :hermes_server_opts, []) do
        [opts] when is_list(opts) -> opts
        opts when is_list(opts) -> opts
        _ -> []
      end

    name = opts[:name]
    version = opts[:version]

    if not Module.defines?(env.module, {:server_info, 0}) do
      validate_server_info!(module, name, version)
    end
  end

  def validate_server_info!(module, nil, nil) do
    raise ConfigurationError, module: module, missing_key: :both
  end

  def validate_server_info!(module, nil, _) do
    raise ConfigurationError, module: module, missing_key: :name
  end

  def validate_server_info!(module, _, nil) do
    raise ConfigurationError, module: module, missing_key: :version
  end

  def validate_server_info!(_, name, version) when is_binary(name) and is_binary(version), do: :ok
end
