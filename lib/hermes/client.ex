defmodule Hermes.Client do
  @moduledoc """
  High-level DSL for defining MCP (Model Context Protocol) clients.

  This module provides an Ecto-like interface for creating MCP clients with minimal boilerplate.
  By using this module, you get a fully functional MCP client with automatic supervision,
  transport management, and all standard MCP operations.

  ## Usage

  Define a client module:

      defmodule MyApp.AnthropicClient do
        use Hermes.Client,
          name: "MyApp",
          version: "1.0.0",
          protocol_version: "2024-11-05",
          capabilities: [:roots, {:sampling, list_changed?: true}]
      end

  Add it to your supervision tree:

      children = [
        {MyApp.AnthropicClient, 
         transport: {:stdio, command: "uvx", args: ["mcp-server-anthropic"]}}
      ]

  Use the client:

      {:ok, tools} = MyApp.AnthropicClient.list_tools()
      {:ok, result} = MyApp.AnthropicClient.call_tool("search", %{query: "elixir"})

  ## Options

  The `use` macro accepts the following required options:

    * `:name` - The client name to advertise to the server (string)
    * `:version` - The client version (string)
    * `:protocol_version` - The MCP protocol version (string)
    * `:capabilities` - List of client capabilities (see below)

  ## Capabilities

  Capabilities can be specified as:

    * Atoms: `:roots`, `:sampling`
    * Tuples with options: `{:roots, list_changed?: true}`
    * Maps for custom capabilities: `%{"custom" => %{"feature" => true}}`

  ## Transport Configuration

  When starting the client, you must provide transport configuration:

    * `{:stdio, command: "cmd", args: ["arg1", "arg2"]}`
    * `{:sse, base_url: "http://localhost:8000"}`
    * `{:websocket, url: "ws://localhost:8000/ws"}`
    * `{:streamable_http, url: "http://localhost:8000/mcp"}`

  ## Process Naming

  By default, the client process is registered with the module name.
  You can override this with the `:name` option in `child_spec` or `start_link`:

      # Custom atom name
      {MyApp.AnthropicClient, name: :my_custom_client, transport: ...}
      
      # For distributed systems with registries (e.g., Horde)
      {MyApp.AnthropicClient,
       name: {:via, Horde.Registry, {MyCluster, "client_1"}},
       transport_name: {:via, Horde.Registry, {MyCluster, "transport_1"}},
       transport: ...}

  When using via tuples or other non-atom names, you must explicitly provide
  the `:transport_name` option. For atom names, the transport is automatically
  named as `Module.concat(ClientName, "Transport")`.
  """

  alias Hermes.Client.Base

  @client_capabilities ~w(roots sampling)a

  @type capability :: :roots | :sampling
  @type capability_opts :: [list_changed?: boolean()]
  @type capabilities :: [capability() | {capability(), capability_opts()} | map()]

  @doc """
  Guard to check if an atom is a valid client capability.
  """
  defguard is_client_capability(capability) when capability in @client_capabilities

  @doc """
  Guard to check if a capability is supported by checking map keys.
  """
  defguard is_supported_capability(capabilities, capability) when is_map_key(capabilities, capability)

  @doc """
  Generates an MCP client module with all necessary functions.

  This macro is used via the `use` directive and accepts the following options:

    * `:name` - Client name (required, string)
    * `:version` - Client version (required, string)  
    * `:protocol_version` - MCP protocol version (required, string)
    * `:capabilities` - List of capabilities (optional, defaults to empty list)

  The macro generates:

    * `child_spec/1` - For supervision tree integration
    * `start_link/1` - To start the client
    * All MCP operation functions (ping, list_tools, call_tool, etc.)
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    capabilities = Enum.reduce(opts[:capabilities] || [], %{}, &parse_capability/2)
    protocol_version = Keyword.fetch!(opts, :protocol_version)
    name = Keyword.fetch!(opts, :name)
    version = Keyword.fetch!(opts, :version)
    client_info = %{"name" => name, "version" => version}

    quote do
      @doc """
      Returns a child specification for supervision tree integration.

      This function is automatically called when adding the client to a supervisor.
      It inherits the client configuration from the `use` macro and merges it with
      runtime options.

      ## Options
        * `:name` - Custom process name (defaults to module name)
        * `:transport` - Transport configuration (required)
        * `:transport_name` - Custom transport process name (required when using via tuples)
        * All other options are passed to the underlying client

      ## Examples
          # Simple usage
          children = [
            {MyClient, transport: {:stdio, command: "mcp", args: ["server"]}}
          ]
          
          # With distributed registry
          children = [
            {MyClient, 
             name: {:via, Horde.Registry, {MyCluster, "client_1"}},
             transport_name: {:via, Horde.Registry, {MyCluster, "transport_1"}},
             transport: {:stdio, command: "mcp", args: ["server"]}}
          ]
          
          Supervisor.start_link(children, strategy: :one_for_one)
      """
      @spec child_spec(keyword()) :: Supervisor.child_spec()
      def child_spec(opts) do
        inherit = [
          client_info: unquote(client_info),
          capabilities: unquote(capabilities),
          protocol_version: unquote(protocol_version)
        ]

        opts = Keyword.merge(opts, inherit)

        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor,
          restart: :permanent
        }
      end

      defoverridable child_spec: 1

      @doc """
      Starts the client and its transport as a supervised process.

      ## Options
        * `:name` - Process name (defaults to module name)
        * `:transport_name` - Transport process name (required for via tuples)
        * `:transport` - Transport configuration (required)
          * `{:stdio, command: "cmd", args: ["arg1"]}`
          * `{:sse, base_url: "http://localhost:8000"}`
          * `{:websocket, url: "ws://localhost:8000/ws"}`
          * `{:streamable_http, url: "http://localhost:8000/mcp"}`

      ## Examples
          # Simple usage
          {:ok, pid} = MyClient.start_link(
            transport: {:stdio, command: "mcp", args: ["run", "server.py"]}
          )
          
          # With distributed registry
          {:ok, pid} = MyClient.start_link(
            name: {:via, Horde.Registry, {MyCluster, "client_1"}},
            transport_name: {:via, Horde.Registry, {MyCluster, "transport_1"}},
            transport: {:stdio, command: "mcp", args: ["run", "server.py"]}
          )
      """
      @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
      def start_link(opts) do
        Hermes.Client.Supervisor.start_link(__MODULE__, opts)
      end

      @doc """
      Sends a ping request to the MCP server.

      ## Options
        * `:timeout` - Request timeout in milliseconds (default: 5000)

      ## Examples
          {:ok, :pong} = MyClient.ping()
      """
      @spec ping(keyword()) :: {:ok, :pong} | {:error, term()}
      def ping(opts \\ []), do: Base.ping(__MODULE__, opts)

      @doc """
      Lists all available resources from the server.

      ## Options
        * `:cursor` - Pagination cursor
        * `:timeout` - Request timeout in milliseconds

      ## Examples
          {:ok, resources} = MyClient.list_resources()
      """
      @spec list_resources(keyword()) :: {:ok, map()} | {:error, term()}
      def list_resources(opts \\ []), do: Base.list_resources(__MODULE__, opts)

      @doc """
      Reads a specific resource by URI.

      ## Examples
          {:ok, content} = MyClient.read_resource("file:///path/to/file")
      """
      @spec read_resource(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
      def read_resource(uri, opts \\ []), do: Base.read_resource(__MODULE__, uri, opts)

      @doc """
      Lists all available prompts from the server.

      ## Options
        * `:cursor` - Pagination cursor
        * `:timeout` - Request timeout in milliseconds

      ## Examples
          {:ok, prompts} = MyClient.list_prompts()
      """
      @spec list_prompts(keyword()) :: {:ok, map()} | {:error, term()}
      def list_prompts(opts \\ []), do: Base.list_prompts(__MODULE__, opts)

      @doc """
      Gets a specific prompt by name with optional arguments.

      ## Examples
          {:ok, prompt} = MyClient.get_prompt("greeting", %{name: "Alice"})
      """
      @spec get_prompt(String.t(), map() | nil, keyword()) :: {:ok, map()} | {:error, term()}
      def get_prompt(name, args \\ nil, opts \\ []), do: Base.get_prompt(__MODULE__, name, args, opts)

      @doc """
      Lists all available tools from the server.

      ## Options
        * `:cursor` - Pagination cursor
        * `:timeout` - Request timeout in milliseconds

      ## Examples
          {:ok, tools} = MyClient.list_tools()
      """
      @spec list_tools(keyword()) :: {:ok, map()} | {:error, term()}
      def list_tools(opts \\ []), do: Base.list_tools(__MODULE__, opts)

      @doc """
      Calls a specific tool by name with optional arguments.

      ## Examples
          {:ok, result} = MyClient.call_tool("search", %{query: "elixir"})
      """
      @spec call_tool(String.t(), map() | nil, keyword()) :: {:ok, map()} | {:error, term()}
      def call_tool(name, args \\ nil, opts \\ []), do: Base.call_tool(__MODULE__, name, args, opts)

      @doc """
      Merges additional capabilities into the client.

      ## Examples
          :ok = MyClient.merge_capabilities(%{"experimental" => %{}})
      """
      @spec merge_capabilities(map(), keyword()) :: :ok | {:error, term()}
      def merge_capabilities(add, opts \\ []), do: Base.merge_capabilities(__MODULE__, add, opts)

      @doc """
      Gets the server's declared capabilities.

      ## Examples
          {:ok, capabilities} = MyClient.get_server_capabilities()
      """
      @spec get_server_capabilities(keyword()) :: {:ok, map()} | {:error, term()}
      def get_server_capabilities(opts \\ []), do: Base.get_server_capabilities(__MODULE__, opts)

      @doc """
      Gets the server information including name and version.

      ## Examples
          {:ok, info} = MyClient.get_server_info()
      """
      @spec get_server_info(keyword()) :: {:ok, map()} | {:error, term()}
      def get_server_info(opts \\ []), do: Base.get_server_info(__MODULE__, opts)

      @doc """
      Completes a partial result reference.

      ## Examples
          {:ok, result} = MyClient.complete(ref, "completed")
      """
      @spec complete(reference(), term(), keyword()) :: {:ok, term()} | {:error, term()}
      def complete(ref, argument, opts \\ []), do: Base.complete(__MODULE__, ref, argument, opts)

      @doc """
      Sets the server's log level.

      ## Examples
          :ok = MyClient.set_log_level("debug")
      """
      @spec set_log_level(String.t()) :: :ok | {:error, term()}
      def set_log_level(level), do: Base.set_log_level(__MODULE__, level)

      @doc """
      Registers a callback for log messages.

      ## Examples
          :ok = MyClient.register_log_callback(fn log -> IO.puts(log) end)
      """
      @spec register_log_callback(function(), keyword()) :: :ok | {:error, term()}
      def register_log_callback(cb, opts \\ []), do: Base.register_log_callback(__MODULE__, cb, opts)

      @doc """
      Unregisters the log callback.
      """
      @spec unregister_log_callback(keyword()) :: :ok | {:error, term()}
      def unregister_log_callback(opts \\ []), do: Base.unregister_log_callback(__MODULE__, opts)

      @doc """
      Registers a callback for progress updates.

      ## Examples
          :ok = MyClient.register_progress_callback("task-1", fn progress -> 
            IO.puts("Progress: #{progress}")
          end)
      """
      @spec register_progress_callback(String.t(), function(), keyword()) :: :ok | {:error, term()}
      def register_progress_callback(token, callback, opts \\ []) do
        Base.register_progress_callback(__MODULE__, token, callback, opts)
      end

      @doc """
      Unregisters a progress callback.
      """
      @spec unregister_progress_callback(String.t(), keyword()) :: :ok | {:error, term()}
      def unregister_progress_callback(token, opts \\ []) do
        Base.unregister_progress_callback(__MODULE__, token, opts)
      end

      @doc """
      Sends a progress update for a token.

      ## Examples
          :ok = MyClient.send_progress("task-1", 50, 100)
      """
      @spec send_progress(String.t(), number(), number() | nil, keyword()) :: :ok | {:error, term()}
      def send_progress(token, progress, total \\ nil, opts \\ []) do
        Base.send_progress(__MODULE__, token, progress, total, opts)
      end

      @doc """
      Cancels a specific request by ID.

      ## Examples
          :ok = MyClient.cancel_request("req-123")
      """
      @spec cancel_request(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
      def cancel_request(request_id, reason \\ "client_cancelled", opts \\ []) do
        Base.cancel_request(__MODULE__, request_id, reason, opts)
      end

      @doc """
      Cancels all pending requests.

      ## Examples
          :ok = MyClient.cancel_all_requests("shutting_down")
      """
      @spec cancel_all_requests(String.t(), keyword()) :: :ok | {:error, term()}
      def cancel_all_requests(reason \\ "client_cancelled", opts \\ []) do
        Base.cancel_all_requests(__MODULE__, reason, opts)
      end

      @doc """
      Adds a root directory or resource.

      ## Examples
          :ok = MyClient.add_root("file:///project", "My Project")
      """
      @spec add_root(String.t(), String.t() | nil, keyword()) :: :ok | {:error, term()}
      def add_root(uri, name \\ nil, opts \\ []), do: Base.add_root(__MODULE__, uri, name, opts)

      @doc """
      Removes a root directory or resource.

      ## Examples
          :ok = MyClient.remove_root("file:///project")
      """
      @spec remove_root(String.t(), keyword()) :: :ok | {:error, term()}
      def remove_root(uri, opts \\ []), do: Base.remove_root(__MODULE__, uri, opts)

      @doc """
      Lists all registered roots.

      ## Examples
          {:ok, roots} = MyClient.list_roots()
      """
      @spec list_roots(keyword()) :: {:ok, list()} | {:error, term()}
      def list_roots(opts \\ []), do: Base.list_roots(__MODULE__, opts)

      @doc """
      Clears all registered roots.

      ## Examples
          :ok = MyClient.clear_roots()
      """
      @spec clear_roots(keyword()) :: :ok | {:error, term()}
      def clear_roots(opts \\ []), do: Base.clear_roots(__MODULE__, opts)

      @doc """
      Closes the client connection gracefully.

      ## Examples
          :ok = MyClient.close()
      """
      @spec close() :: :ok
      def close, do: Base.close(__MODULE__)
    end
  end

  @spec parse_capability(capability() | {capability(), capability_opts()}, map()) :: map()
  defp parse_capability(capability, %{} = capabilities) when is_client_capability(capability) do
    Map.put(capabilities, to_string(capability), %{})
  end

  defp parse_capability({capability, opts}, %{} = capabilities) when is_client_capability(capability) do
    list_changed? = opts[:list_changed?]

    capabilities
    |> Map.put(to_string(capability), %{})
    |> then(&if(is_nil(list_changed?), do: &1, else: Map.put(&1, "listChanged", list_changed?)))
  end
end
