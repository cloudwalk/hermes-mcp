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

  alias Hermes.MCP.Error
  alias Hermes.Server.Component
  alias Hermes.Server.Component.Schema
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

      import Hermes.Server, only: [component: 1, component: 2]
      import Hermes.Server.Frame

      require Hermes.MCP.Message

      Module.register_attribute(__MODULE__, :components, accumulate: true)
      @before_compile Hermes.Server

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

      defoverridable server_info: 0,
                     server_capabilities: 0,
                     supported_protocol_versions: 0,
                     child_spec: 1
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

    tools = for {:tool, name, mod} <- components, do: {name, mod}
    prompts = for {:prompt, name, mod} <- components, do: {name, mod}
    resources = for {:resource, name, mod} <- components, do: {name, mod}

    quote do
      def __components__(:tool), do: unquote(Macro.escape(tools))
      def __components__(:prompt), do: unquote(Macro.escape(prompts))
      def __components__(:resource), do: unquote(Macro.escape(resources))
      def __components__(_), do: []

      @impl Hermes.Server.Behaviour
      def handle_request(request, frame) do
        Hermes.Server.__default_handle_request__(request, frame, __MODULE__)
      end

      defoverridable handle_request: 2
    end
  end

  @doc false
  def __default_handle_request__(%{"method" => "tools/list"}, frame, server_module) do
    {:reply,
     %{
       "tools" =>
         for {name, module} <- server_module.__components__(:tool) do
           %{
             "name" => name,
             "description" => Component.get_description(module),
             "inputSchema" => module.input_schema()
           }
         end
     }, frame}
  end

  def __default_handle_request__(%{"method" => "tools/call", "params" => params}, frame, server_module) do
    with %{"name" => tool_name, "arguments" => args} <- params,
         {_name, module} <- find_component(server_module.__components__(:tool), tool_name) do
      call_tool(module, args, frame)
    else
      nil ->
        {:error, Error.invalid_params(%{message: "Tool not found: #{params["name"]}"}), frame}

      {:error, reason} ->
        {:error, Error.invalid_params(reason), frame}

      {:error, reason, new_frame} ->
        {:error, Error.invalid_params(reason), new_frame}
    end
  end

  def __default_handle_request__(%{"method" => "prompts/list"}, frame, server_module) do
    {:reply,
     %{
       "prompts" =>
         for {name, module} <- server_module.__components__(:prompt) do
           %{
             "name" => name,
             "description" => Component.get_description(module),
             "arguments" => module.arguments()
           }
         end
     }, frame}
  end

  def __default_handle_request__(%{"method" => "prompts/get", "params" => params}, frame, server_module) do
    with %{"name" => prompt_name, "arguments" => args} <- params,
         {_name, module} <- find_component(server_module.__components__(:prompt), prompt_name) do
      get_prompt_messages(module, args, frame)
    else
      nil ->
        {:error, Error.invalid_params(%{message: "Prompt not found: #{params["name"]}"}), frame}

      {:error, reason} ->
        {:error, Error.invalid_params(reason), frame}

      {:error, reason, new_frame} ->
        {:error, Error.invalid_params(reason), new_frame}
    end
  end

  def __default_handle_request__(%{"method" => "resources/list"}, frame, server_module) do
    {:reply,
     %{
       "resources" =>
         for {_name, module} <- server_module.__components__(:resource) do
           %{
             "uri" => module.uri(),
             "name" => Component.get_description(module),
             "mimeType" => module.mime_type()
           }
         end
     }, frame}
  end

  def __default_handle_request__(%{"method" => "resources/read", "params" => params}, frame, server_module) do
    with %{"uri" => uri} <- params,
         module when not is_nil(module) <- find_resource_by_uri(server_module.__components__(:resource), uri) do
      read_resource(module, params, frame)
    else
      nil ->
        {:error, Error.invalid_params(%{message: "Resource not found: #{params["uri"]}"}), frame}

      {:error, reason} ->
        {:error, Error.invalid_params(reason), frame}

      {:error, reason, new_frame} ->
        {:error, Error.invalid_params(reason), new_frame}
    end
  end

  def __default_handle_request__(_request, frame, _server_module) do
    {:error, Error.method_not_found(), frame}
  end

  defp find_component(components, name) do
    Enum.find(components, fn {n, _} -> n == name end)
  end

  defp find_resource_by_uri(components, uri) do
    case Enum.find(components, fn {_name, module} -> module.uri() == uri end) do
      {_name, module} -> module
      nil -> nil
    end
  end

  defp call_tool(module, args, frame) do
    case module.mcp_schema(args) do
      {:ok, args} -> module.execute(args, frame)
      {:error, errors} -> {:error, Error.invalid_request(%{message: Schema.format_errors(errors)}), frame}
    end
  end

  defp get_prompt_messages(module, args, frame) do
    case module.mcp_schema(args) do
      {:ok, args} -> module.get_messages(args, frame)
      {:error, errors} -> {:error, Error.invalid_request(%{message: Schema.format_errors(errors)}), frame}
    end
  end

  defp read_resource(module, params, frame) do
    case module.read(params, frame) do
      {:reply, %{"text" => _} = content, new_frame} ->
        response =
          content
          |> Map.put("uri", module.uri())
          |> Map.put("mimeType", module.mime_type())

        {:reply, response, new_frame}

      {:reply, %{"blob" => _} = content, new_frame} ->
        response =
          content
          |> Map.put("uri", module.uri())
          |> Map.put("mimeType", module.mime_type())

        {:reply, response, new_frame}

      other ->
        other
    end
  end
end
