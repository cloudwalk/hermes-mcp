defmodule Hermes.Server do
  @moduledoc """
  Build MCP servers that extend language model capabilities.

  MCP servers are specialized processes that provide three core primitives to AI assistants:
  **Resources** (contextual data like files or schemas), **Tools** (actions the model can invoke),
  and **Prompts** (user-selectable templates). They operate in a secure, isolated architecture
  where clients maintain 1:1 connections with servers, enabling composable functionality while
  maintaining strict security boundaries.

  ## Quick Start

  Create a server in three steps:

      defmodule MyServer do
        use Hermes.Server,
          name: "my-server",
          version: "1.0.0",
          capabilities: [:tools]

        component MyServer.Calculator
      end

      defmodule MyServer.Calculator do
        use Hermes.Server.Component, type: :tool

        def definition do
          %{
            name: "add",
            description: "Add two numbers",
            input_schema: %{
              type: "object",
              properties: %{
                a: %{type: "number"},
                b: %{type: "number"}
              }
            }
          }
        end

        def call(%{"a" => a, "b" => b}), do: {:ok, a + b}
      end

      # Start your server
      {:ok, _pid} = Hermes.Server.start_link(MyServer, [], transport: :stdio)

  Your server is now a living process that AI assistants can connect to, discover available
  tools, and execute calculations through a secure protocol boundary.

  ## Capabilities

  Declare what your server can do:

  - **`:tools`** - Execute functions with structured inputs and outputs
  - **`:resources`** - Provide data that models can read (files, APIs, databases)
  - **`:prompts`** - Offer reusable templates for common interactions
  - **`:logging`** - Allow clients to configure verbosity levels

  Configure capabilities with options:

      use Hermes.Server,
        capabilities: [
          :tools,
          {:resources, subscribe?: true},      # Enable resource update subscriptions
          {:prompts, list_changed?: true}      # Notify when prompts change
        ]

  ## Components

  Register tools, resources, and prompts as components:

      component MyServer.FileReader           # Auto-named as "file_reader"
      component MyServer.ApiClient, name: "api"   # Custom name

  Components are modules that implement specific behaviors
  and are automatically discovered by clients through the protocol.

  ## Server Lifecycle

  Your server follows a predictable lifecycle with callbacks you can hook into:

  1. **`init/2`** - Set up initial state when the server starts
  2. **`handle_request/2`** - Process MCP protocol requests from clients
  3. **`handle_notification/2`** - React to one-way client messages
  4. **`handle_info/2`** - Bridge external events into MCP notifications

  Most protocol handling is automatic - you typically only implement `init/2` for setup
  and occasionally override other callbacks for custom behavior.
  """

  alias Hermes.Server.Component
  alias Hermes.Server.Component.Prompt
  alias Hermes.Server.Component.Resource
  alias Hermes.Server.Component.Tool
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
  Called after a client requests a `initialize` request.

  This callback is invoked while the MCP handshake starts and so the client may not sent
  the `notifications/initialized` message yet. For checking if the notification was already sent
  and the MCP handshare was successfully completed, you can call the `initialized?/1` function.

  It receives the client's information and
  the current frame, allowing you to perform client-specific setup, validate capabilities,
  or prepare resources based on the connected client.

  The client_info parameter contains details about the connected client including its
  name, version, and any additional metadata. Use this to tailor your server's behavior
  to specific client implementations or versions.
  """
  @callback init(client_info :: map(), Frame.t()) :: {:ok, Frame.t()}

  @doc """
  Handles a tool call request.

  This callback is invoked when a client calls a specific tool. It receives the tool name,
  the arguments provided by the client, and the current frame. Developers's implementation should
  execute the tool's logic and return the result.

  This callback handles both module-based components (registered with `component`) and
  runtime components (registered with `Frame.register_tool/3`). For module-based tools,
  the framework automatically generates pattern-matched clauses during compilation.
  """
  @callback handle_tool_call(name :: String.t(), arguments :: map(), Frame.t()) ::
              {:reply, result :: term(), Frame.t()}
              | {:error, mcp_error(), Frame.t()}

  @doc """
  Handles a resource read request.

  This callback is invoked when a client requests to read a specific resource. It receives
  the resource URI and the current frame. Developer's implementation should retrieve and return
  the resource content.

  This callback handles both module-based components (registered with `component`) and
  runtime components (registered with `Frame.register_resource/3`). For module-based resources,
  the framework automatically generates pattern-matched clauses during compilation.
  """
  @callback handle_resource_read(uri :: String.t(), Frame.t()) ::
              {:reply, content :: map(), Frame.t()}
              | {:error, mcp_error(), Frame.t()}

  @doc """
  Handles a prompt get request.

  This callback is invoked when a client requests a specific prompt template. It receives
  the prompt name, any arguments to fill into the template, and the current frame.

  This callback handles both module-based components (registered with `component`) and
  runtime components (registered with `Frame.register_prompt/3`). For module-based prompts,
  the framework automatically generates pattern-matched clauses during compilation.
  """
  @callback handle_prompt_get(name :: String.t(), arguments :: map(), Frame.t()) ::
              {:reply, messages :: list(), Frame.t()}
              | {:error, mcp_error(), Frame.t()}

  @doc """
  Low-level handler for any MCP request.

  This is an advanced callback that gives you complete control over request handling.
  When implemented, it bypasses the automatic routing to `handle_tool_call/3`,
  `handle_resource_read/2`, and `handle_prompt_get/3` and all other requests that are
  handled internally, like `tools/list` and `logging/setLevel`.

  Use this when you need to:
  - Implement custom request methods beyond the standard MCP protocol
  - Add middleware-like processing before requests reach specific handlers
  - Override the framework's default request routing behavior

  Note: If you implement this callback, you become responsible for handling ALL
  MCP requests, including standard protocol methods like `tools/list`, `resources/list`, etc.
  Consider using the specific callbacks instead unless you need this level of control.
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

  @doc """
  Handles synchronous calls to the server process.

  This optional callback allows you to handle custom synchronous calls made to your
  MCP server process using `GenServer.call/2`. This is useful for implementing
  administrative functions, status queries, or any synchronous operations that
  need to interact with the server's internal state.

  The callback follows standard GenServer semantics and should return appropriate
  reply tuples. If not implemented, the Base module provides a default implementation
  that handles standard MCP operations.
  """
  @callback handle_call(request :: term, from :: GenServer.from(), Frame.t()) ::
              {:reply, reply :: term, Frame.t()}
              | {:reply, reply :: term, Frame.t(),
                 timeout() | :hibernate | {:continue, arg :: term}}
              | {:noreply, Frame.t()}
              | {:noreply, Frame.t(), timeout() | :hibernate | {:continue, arg :: term}}
              | {:stop, reason :: term, reply :: term, Frame.t()}
              | {:stop, reason :: term, Frame.t()}

  @doc """
  Handles asynchronous casts to the server process.

  This optional callback allows you to handle custom asynchronous messages sent to your
  MCP server process using `GenServer.cast/2`. This is useful for fire-and-forget
  operations, background tasks, or any asynchronous operations that don't require
  an immediate response.

  The callback follows standard GenServer semantics. If not implemented, the Base
  module provides a default implementation that handles standard MCP operations.
  """
  @callback handle_cast(request :: term, Frame.t()) ::
              {:noreply, Frame.t()}
              | {:noreply, Frame.t(), timeout() | :hibernate | {:continue, arg :: term}}
              | {:stop, reason :: term, Frame.t()}

  @doc """
  Cleans up when the server process terminates.

  This optional callback is invoked when the server process is about to terminate.
  It allows you to perform cleanup operations, close connections, save state,
  or release resources before the process exits.

  The callback receives the termination reason and the current frame. Any return
  value is ignored. If not implemented, the Base module provides a default
  implementation that logs the termination event.
  """
  @callback terminate(reason :: term, Frame.t()) :: term

  @doc """
  Handles the response from a sampling/createMessage request sent to the client.

  This callback is invoked when the client responds to a sampling request initiated
  by the server. The response contains the generated message from the client's LLM.

  ## Parameters

    * `response` - The response from the client containing:
      * `"role"` - The role of the generated message (typically "assistant")
      * `"content"` - The content object with type and data
      * `"model"` - The model used for generation
      * `"stopReason"` - Why generation stopped (e.g., "endTurn")
    * `request_id` - The ID of the original request for correlation
    * `frame` - The current server frame

  ## Returns

    * `{:noreply, frame}` - Continue processing
    * `{:stop, reason, frame}` - Stop the server

  ## Examples

      def handle_sampling(response, request_id, frame) do
        %{"content" => %{"text" => text}} = response
        # Process the generated text...
        {:noreply, frame}
      end
  """
  @callback handle_sampling(
              response :: map(),
              request_id :: String.t(),
              Frame.t()
            ) ::
              {:noreply, Frame.t()}
              | {:stop, reason :: term(), Frame.t()}

  @optional_callbacks handle_notification: 2,
                      handle_info: 2,
                      handle_call: 3,
                      handle_cast: 2,
                      terminate: 2,
                      handle_tool_call: 3,
                      handle_resource_read: 2,
                      handle_prompt_get: 3,
                      handle_request: 2,
                      init: 2,
                      handle_sampling: 3

  @doc """
  Checks if the MCP session has been initialized.

  Returns true if the client has completed the initialization handshake and sent
  the `notifications/initialized` message. This is useful for guarding operations
  that require an active session.

  ## Examples

      def handle_info(:check_status, frame) do
        if Hermes.Server.initialized?(frame) do
          # Perform operations requiring initialized session
          {:noreply, frame}
        else
          # Wait for initialization
          {:noreply, frame}
        end
      end
  """
  @spec initialized?(Frame.t()) :: boolean()
  def initialized?(%Frame{initialized: initialized}), do: initialized

  @doc false
  defguard is_server_capability(capability) when capability in @server_capabilities

  @doc false
  defguard is_supported_capability(capabilities, capability)
           when is_map_key(capabilities, capability)

  @doc false
  defmacro __using__(opts) do
    quote do
      @behaviour Hermes.Server

      import Hermes.Server
      import Hermes.Server.Component, only: [field: 3]
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
          start: {Hermes.Server.Supervisor, :start_link, [__MODULE__, opts]},
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

      @components {Component.get_type(module),
                   opts[:name] || Hermes.Server.__derive_component_name__(module), module}
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

    quote do
      def __components__,
        do: Hermes.Server.parse_components(unquote(Macro.escape(components)))

      def __components__(:tool), do: Enum.filter(__components__(), &match?(%Tool{}, &1))

      def __components__(:prompt),
        do: Enum.filter(__components__(), &match?(%Prompt{}, &1))

      def __components__(:resource),
        do: Enum.filter(__components__(), &match?(%Resource{}, &1))

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

  @doc false
  def parse_components(components) when is_list(components) do
    components
    |> Enum.flat_map(&parse_components/1)
    |> Enum.sort_by(& &1.name)
  end

  def parse_components({:tool, name, mod}) do
    annotations = if Hermes.exported?(mod, :annotations, 0), do: mod.annotations()

    if Hermes.exported?(mod, :input_schema, 0) do
      validate_input = fn params ->
        mod.__mcp_raw_schema__()
        |> Component.__clean_schema_for_peri__()
        |> Peri.validate(params)
      end

      [
        %Tool{
          name: name,
          description: Component.get_description(mod),
          input_schema: mod.input_schema(),
          annotations: annotations,
          handler: mod,
          validate_input: validate_input
        }
      ]
    else
      []
    end
  end

  def parse_components({:prompt, name, mod}) do
    if Hermes.exported?(mod, :arguments, 0) do
      validate_input = fn params ->
        mod.__mcp_raw_schema__()
        |> Component.__clean_schema_for_peri__()
        |> Peri.validate(params)
      end

      [
        %Prompt{
          name: name,
          description: Component.get_description(mod),
          arguments: mod.arguments(),
          handler: mod,
          validate_input: validate_input
        }
      ]
    else
      []
    end
  end

  def parse_components({:resource, name, mod}) do
    if Hermes.exported?(mod, :uri, 0) do
      [
        %Resource{
          uri: mod.uri(),
          name: name,
          description: Component.get_description(mod),
          mime_type: mod.mime_type(),
          handler: mod
        }
      ]
    else
      []
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
    if not Module.defines?(module, {:server_info, 0}) or is_nil(name) or
         is_nil(version) do
      quote do
        @impl Hermes.Server
        def server_info,
          do: %{"name" => unquote(name), "version" => unquote(version)}
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
  def parse_capability(capability, %{} = capabilities)
      when is_server_capability(capability) do
    Map.put(capabilities, to_string(capability), %{})
  end

  def parse_capability({:resources, opts}, %{} = capabilities) do
    subscribe? = opts[:subscribe?]
    list_changed? = opts[:list_changed?]

    capabilities
    |> Map.put("resources", %{})
    |> then(&if(is_nil(subscribe?), do: &1, else: Map.put(&1, :subscribe, subscribe?)))
    |> then(
      &if(is_nil(list_changed?),
        do: &1,
        else: Map.put(&1, :listChanged, list_changed?)
      )
    )
  end

  def parse_capability({capability, opts}, %{} = capabilities)
      when is_server_capability(capability) do
    list_changed? = opts[:list_changed?]

    capabilities
    |> Map.put(to_string(capability), %{})
    |> then(
      &if(is_nil(list_changed?),
        do: &1,
        else: Map.put(&1, :listChanged, list_changed?)
      )
    )
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

  def validate_server_info!(_, name, version) when is_binary(name) and is_binary(version),
    do: :ok

  # Notification Functions

  @doc """
  Sends a resources list changed notification to connected clients.

  Use this when the available resources have changed (added, removed, or modified).
  The client will typically re-fetch the resource list in response.
  """
  @spec send_resources_list_changed(Frame.t()) :: :ok
  def send_resources_list_changed(%Frame{} = frame) do
    queue_notification(frame, "notifications/resources/list_changed", %{})
  end

  @doc """
  Sends a resource updated notification for a specific resource.

  Use this when the content of a specific resource has changed.
  Clients that have subscribed to this resource will be notified.
  """
  @spec send_resource_updated(
          Frame.t(),
          uri :: String.t(),
          timestamp :: DateTime.t() | nil
        ) ::
          :ok
  def send_resource_updated(%Frame{} = frame, uri, timestamp \\ nil) do
    params = %{"uri" => uri}
    params = if timestamp, do: Map.put(params, "timestamp", timestamp), else: params
    queue_notification(frame, "notifications/resources/updated", params)
  end

  @doc """
  Sends a prompts list changed notification to connected clients.

  Use this when the available prompts have changed (added, removed, or modified).
  The client will typically re-fetch the prompt list in response.
  """
  @spec send_prompts_list_changed(Frame.t()) :: :ok
  def send_prompts_list_changed(%Frame{} = frame) do
    queue_notification(frame, "notifications/prompts/list_changed", %{})
  end

  @doc """
  Sends a tools list changed notification to connected clients.

  Use this when the available tools have changed (added, removed, or modified).
  The client will typically re-fetch the tool list in response.
  """
  @spec send_tools_list_changed(Frame.t()) :: :ok
  def send_tools_list_changed(%Frame{} = frame) do
    queue_notification(frame, "notifications/tools/list_changed", %{})
  end

  @doc """
  Sends a log message to the client.

  Use this to send diagnostic or informational messages to the client's logging system.
  """
  @spec send_log_message(
          Frame.t(),
          level :: Logger.level(),
          message :: String.t(),
          metadata :: map() | nil
        ) :: :ok
  def send_log_message(%Frame{} = frame, level, message, data \\ nil) do
    params = %{"level" => level, "message" => message}
    params = if data, do: Map.put(params, "data", data), else: params

    queue_notification(frame, "notifications/log/message", params)
  end

  @type progress_token :: String.t() | non_neg_integer
  @type progress_step :: number
  @type progress_total :: number

  @doc """
  Sends a progress notification for an ongoing operation.

  Use this to update the client on the progress of long-running operations.
  """
  @spec send_progress(Frame.t(), progress_token, progress_step, opts) :: :ok
        when opts: list({:total, progress_total} | {:message, String.t()})
  def send_progress(%Frame{} = frame, progress_token, progress, opts \\ []) do
    total = opts[:total]
    message = opts[:message]
    params = %{"progressToken" => progress_token, "progress" => progress}
    params = if total, do: Map.put(params, "total", total), else: params
    params = if message, do: Map.put(params, "message", message), else: params

    queue_notification(frame, "notifications/progress", params)
  end

  defp queue_notification(frame, method, params) do
    registry = frame.private.server_registry
    server = frame.private.server_module
    pid = registry.whereis_server(server)
    send(pid, {:send_notification, method, params})
    :ok
  end

  # Sampling Request Functions

  @doc """
  Sends a sampling/createMessage request to the client.

  This function is used when the server needs the client to generate a message
  using its language model. The client must have declared the sampling capability
  during initialization.

  Note: This is an asynchronous operation. The response will be delivered to your
  `handle_sampling/3` callback.

  Check https://modelcontextprotocol.io/specification/2025-06-18/client/sampling for more information

  ## Examples

      messages = [
        %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}
      ]

      model_preferences = %{"costPriority" => 1.0, "speedPriority" => 0.1, "hints" => [%{"name" => "claude"}]}
      
      :ok = Hermes.Server.send_sampling_request(frame, messages,
        model_preferences: model_preferences,
        system_prompt: "You are a helpful assistant",
        max_tokens: 100
      )
  """
  @spec send_sampling_request(Frame.t(), list(map()), configuration) :: :ok
        when configuration:
               list(
                 {:model_preferences, map | nil}
                 | {:system_prompt, String.t() | nil}
                 | {:max_token, integer | nil}
               )
  def send_sampling_request(%Frame{} = frame, messages, opts \\ [])
      when is_list(messages) do
    params = %{"messages" => messages}

    params =
      opts
      |> Keyword.take([:model_preferences, :system_prompt, :max_tokens])
      |> Enum.reduce(params, fn
        {:model_preferences, prefs}, acc -> Map.put(acc, "modelPreferences", prefs)
        {:system_prompt, prompt}, acc -> Map.put(acc, "systemPrompt", prompt)
        {:max_tokens, max}, acc -> Map.put(acc, "maxTokens", max)
      end)

    metadata = Keyword.get(opts, :metadata, %{})
    registry = frame.private.server_registry
    server = frame.private.server_module
    pid = registry.whereis_server(server)
    send(pid, {:send_sampling_request, params, metadata})
    :ok
  end
end
