defmodule Hermes.Server do
  @moduledoc """
  MCP server implementation.

  This module provides the main API for implementing MCP (Model Context Protocol) servers.
  It includes macros and functions to simplify server creation with standardized capabilities,
  protocol version support, and supervision tree setup.

  ## Usage

      defmodule MyServer do
        use Hermes.Server,
          name: "My MCP Server",
          version: "1.0.0",
          capabilities: [:tools, :resources, :logging]

        @impl Hermes.Server
        def init(_arg, frame) do
          {:ok, frame}
        end

        @impl Hermes.Server
        def handle_request(%{"method" => "tools/list"}, frame) do
          {:reply, %{"tools" => []}, frame}
        end

        @impl Hermes.Server
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
  alias Hermes.Server.Frame
  alias Hermes.Server.Handlers

  @server_capabilities ~w(prompts tools resources logging)a
  @protocol_versions ~w(2025-03-26 2024-05-11 2024-10-07)

  @type request :: map()
  @type response :: map()
  @type notification :: map()
  @type mcp_error :: Hermes.MCP.Error.t()
  @type server_info :: map()
  @type server_capabilities :: map()

  @doc """
  Initializes the server when it starts up.

  This callback sets the stage for your MCP server. It's called once when the server
  process starts and gives you the opportunity to set up initial state, load configuration,
  establish connections to external services, or perform any other setup tasks your
  server needs before it can start handling MCP protocol messages.

  The frame parameter provides a structured way to manage your server's state throughout
  its lifecycle. You can store configuration, track active subscriptions, cache resources,
  or maintain any other stateful data your server needs to operate effectively.

  This follows the standard GenServer initialization pattern, so you can return various
  tuples to control the server's startup behavior - from simple success to requesting
  hibernation for memory optimization or scheduling immediate work with :continue.
  """
  @callback init(init_arg :: term(), Frame.t()) ::
              {:ok, Frame.t()}
              | {:ok, Frame.t(), timeout | :hibernate | {:continue, arg :: term}}
              | {:stop, reason :: term()}
              | :ignore

  @doc """
  Handles incoming MCP requests from clients.

  This callback is the heart of your MCP server's request handling. When a client sends a request,
  this function determines how to process it and what response to send back. The MCP protocol
  defines a standard set of request methods that clients can invoke:

  **Core Protocol Requests:**
  - `initialize` - Establishes the connection, exchanges capabilities between client and server
  - `ping` - Health check to verify the server is responsive

  **Resource Management:**
  - `resources/list` - Returns available resources the server can provide
  - `resources/templates/list` - Returns URI templates for dynamic resources
  - `resources/read` - Retrieves content of a specific resource
  - `resources/subscribe` - Subscribes to updates for a resource
  - `resources/unsubscribe` - Cancels a resource subscription

  **Tool Execution:**
  - `tools/list` - Returns available tools the server can execute
  - `tools/call` - Executes a specific tool with provided arguments

  **Prompt Templates:**
  - `prompts/list` - Returns available prompt templates
  - `prompts/get` - Retrieves a specific prompt with filled arguments

  **Other Capabilities:**
  - `logging/setLevel` - Adjusts the server's logging verbosity
  - `completion/complete` - Provides autocompletion suggestions

  The server should respond to supported methods and return appropriate errors for
  unsupported ones. When using `use Hermes.Server`, most of these handlers are
  automatically implemented based on your configured capabilities and registered
  components.
  """
  @callback handle_request(request :: request(), state :: Frame.t()) ::
              {:reply, response :: response(), new_state :: Frame.t()}
              | {:noreply, new_state :: Frame.t()}
              | {:error, error :: mcp_error(), new_state :: Frame.t()}

  @doc """
  Handles incoming MCP notifications from clients.

  Notifications are one-way messages in the MCP protocol - the client informs the server
  about events or state changes without expecting a response. This fire-and-forget pattern
  is perfect for status updates, progress tracking, and lifecycle events.

  **Standard MCP Notifications from Clients:**
  - `notifications/initialized` - Client signals it's ready after successful initialization
  - `notifications/cancelled` - Client requests cancellation of an in-progress operation
  - `notifications/progress` - Client reports progress on a long-running operation
  - `notifications/roots/list_changed` - Client's available filesystem roots have changed

  Unlike requests, notifications never receive responses. Any errors during processing
  are typically logged but not communicated back to the client. This makes notifications
  ideal for optional features like progress tracking where delivery isn't guaranteed.

  The server processes these notifications to update its internal state, trigger side effects,
  or coordinate with other parts of the system. When using `use Hermes.Server`, basic
  notification handling is provided, but you'll often want to override this callback
  to handle progress updates or cancellations specific to your server's operations.
  """
  @callback handle_notification(notification :: notification(), state :: Frame.t()) ::
              {:noreply, new_state :: Frame.t()}
              | {:error, error :: mcp_error(), new_state :: Frame.t()}

  @doc """
  Provides the server's identity information during initialization.

  This callback is called during the MCP handshake to identify your server to connecting clients.
  The information returned here helps clients understand which server they're talking to and
  ensures version compatibility.

  When using `use Hermes.Server`, this callback is automatically implemented using the
  `name` and `version` options you provide. You only need to implement this manually if
  you require dynamic server information based on runtime conditions.
  """
  @callback server_info :: server_info()

  @doc """
  Declares the server's capabilities during initialization.

  This callback tells clients what features your server supports - which types of resources
  it can provide, what tools it can execute, whether it supports logging configuration, etc.
  The capabilities you declare here directly impact which requests the client will send.

  When using `use Hermes.Server` with the `capabilities` option, this callback is automatically
  implemented based on your configuration. The macro analyzes your registered components and
  builds the appropriate capability map, so you rarely need to implement this manually.
  """
  @callback server_capabilities :: server_capabilities()

  @doc """
  Specifies which MCP protocol versions this server can speak.

  Protocol version negotiation ensures client and server can communicate effectively.
  During initialization, the client and server agree on a mutually supported version.
  This callback returns the list of versions your server understands, typically in
  order of preference from newest to oldest.

  When using `use Hermes.Server`, this is automatically implemented with sensible defaults
  covering current and recent protocol versions. Override only if you need to restrict
  or extend version support for specific compatibility requirements.
  """
  @callback supported_protocol_versions() :: [String.t()]

  @doc """
  Handles non-MCP messages sent to the server process.

  While `handle_request` and `handle_notification` deal with MCP protocol messages,
  this callback handles everything else - timer events, messages from other processes,
  system signals, and any custom inter-process communication your server needs.

  This is particularly useful for servers that need to react to external events
  (like file system changes or database updates) and notify connected clients through
  MCP notifications. Think of it as the bridge between your Elixir application's
  internal events and the MCP protocol's notification system.
  """
  @callback handle_info(event :: term, Frame.t()) ::
              {:noreply, Frame.t()}
              | {:noreply, Frame.t(), timeout() | :hibernate | {:continue, arg :: term}}
              | {:stop, reason :: term, Frame.t()}

  @optional_callbacks handle_notification: 2, handle_info: 2

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

  @doc false
  defguard is_server_capability(capability) when capability in @server_capabilities

  @doc false
  defguard is_supported_capability(capabilities, capability) when is_map_key(capabilities, capability)

  @doc false
  defmacro __using__(opts) do
    quote do
      @behaviour Hermes.Server

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

      @impl Hermes.Server
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
        @impl Hermes.Server
        def server_info, do: %{"name" => unquote(name), "version" => unquote(version)}
      end
    end
  end

  defp maybe_define_server_capabilities(module, capabilities_config) do
    if not Module.defines?(module, {:server_capabilities, 0}) do
      capabilities = Enum.reduce(capabilities_config || [], %{}, &parse_capability/2)

      quote do
        @impl Hermes.Server
        def server_capabilities, do: unquote(Macro.escape(capabilities))
      end
    end
  end

  defp maybe_define_protocol_versions(module, protocol_versions) do
    if not Module.defines?(module, {:supported_protocol_versions, 0}) do
      versions = protocol_versions || @protocol_versions

      quote do
        @impl Hermes.Server
        def supported_protocol_versions, do: unquote(versions)
      end
    end
  end

  @doc false
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

  @doc false
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
