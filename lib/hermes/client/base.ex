defmodule Hermes.Client.Base do
  @moduledoc false

  use GenServer
  use Hermes.Logging

  import Peri

  alias Hermes.Client.Operation
  alias Hermes.Client.Request
  alias Hermes.Client.State
  alias Hermes.MCP.Error
  alias Hermes.MCP.Message
  alias Hermes.MCP.Response
  alias Hermes.Protocol
  alias Hermes.Telemetry
  alias Hermes.Transport.StreamableHTTP

  require Message

  @default_protocol_version Protocol.latest_version()

  @type t :: GenServer.server()

  @typedoc """
  Progress callback function type.

  Called when progress notifications are received for a specific progress token.

  ## Parameters
    - `progress_token` - String or integer identifier for the progress operation
    - `progress` - Current progress value
    - `total` - Total expected value (nil if unknown)

  ## Returns
    - The return value is ignored
  """
  @type progress_callback ::
          (progress_token :: String.t() | integer(), progress :: number(), total :: number() | nil ->
             any())

  @typedoc """
  Log callback function type.

  Called when log message notifications are received from the server.

  ## Parameters
    - `level` - Log level as a string (e.g., "debug", "info", "warning", "error")
    - `data` - Log message data, typically a map with message details
    - `logger` - Optional logger name identifying the source

  ## Returns
    - The return value is ignored
  """
  @type log_callback ::
          (level :: String.t(), data :: term(), logger :: String.t() | nil -> any())

  @typedoc """
  Root directory specification.

  Represents a root directory that the client has access to.

  ## Fields
    - `:uri` - File URI for the root directory (e.g., "file:///home/user/project")
    - `:name` - Optional human-readable name for the root
  """
  @type root :: %{
          uri: String.t(),
          name: String.t() | nil
        }

  @typedoc """
  MCP client transport options

  - `:layer` - The transport layer to use, either `Hermes.Transport.STDIO`, `Hermes.Transport.SSE`, `Hermes.Transport.WebSocket`, or `Hermes.Transport.StreamableHTTP` (required)
  - `:name` - The transport optional custom name
  """
  @type transport ::
          list(
            {:layer,
             Hermes.Transport.STDIO
             | Hermes.Transport.SSE
             | Hermes.Transport.WebSocket
             | StreamableHTTP}
            | {:name, GenServer.server()}
          )

  @typedoc """
  MCP client metadata info

  - `:name` - The name of the client (required)
  - `:version` - The version of the client
  """
  @type client_info :: %{
          required(:name | String.t()) => String.t(),
          optional(:version | String.t()) => String.t()
        }

  @typedoc """
  MCP client capabilities

  - `:roots` - Capabilities related to the roots resource
    - `:listChanged` - Whether the client can handle listChanged notifications
  - `:sampling` - Capabilities related to sampling

  MCP describes these client capabilities on it [specification](https://spec.modelcontextprotocol.io/specification/2024-11-05/client/)
  """
  @type capabilities :: %{
          optional(:roots | String.t()) => %{
            optional(:listChanged | String.t()) => boolean
          },
          optional(:sampling | String.t()) => %{}
        }

  @typedoc """
  MCP client initialization options

  - `:name` - Following the `GenServer` patterns described on "Name registration".
  - `:transport` - The MCP transport options
  - `:client_info` - Information about the client
  - `:capabilities` - Client capabilities to advertise to the MCP server
  - `:protocol_version` - Protocol version to use (defaults to "2024-11-05")

  Any other option support by `GenServer`.
  """
  @type option ::
          {:name, GenServer.name()}
          | {:transport, transport}
          | {:client_info, map}
          | {:capabilities, map}
          | {:protocol_version, String.t()}
          | GenServer.option()

  defschema(:parse_options, [
    {:name, {{:custom, &Hermes.genserver_name/1}, {:default, __MODULE__}}},
    {:transport, {:required, {:custom, &Hermes.client_transport/1}}},
    {:client_info, {:required, :map}},
    {:capabilities, {:required, :map}},
    {:protocol_version, {:string, {:default, @default_protocol_version}}}
  ])

  @doc """
  Starts a new MCP client process.
  """
  @spec start_link(Enumerable.t(option)) :: GenServer.on_start()
  def start_link(opts) do
    opts = parse_options!(opts)

    protocol_version = opts[:protocol_version]
    layer = opts[:transport][:layer]

    with :ok <- Protocol.validate_version(protocol_version),
         :ok <- Protocol.validate_transport(protocol_version, layer) do
      GenServer.start_link(__MODULE__, Map.new(opts), name: opts[:name])
    end
  end

  @doc """
  Sends a ping request to the server to check connection health. Returns `:pong` if successful.

  ## Options

    * `:timeout` - Request timeout in milliseconds (default: 30s)
    * `:progress` - Progress tracking options
      * `:token` - A unique token to track progress (string or integer)
      * `:callback` - A function to call when progress updates are received
  """
  @spec ping(t, keyword) :: :pong | {:error, Error.t()}
  def ping(client, opts \\ []) when is_list(opts) do
    operation =
      Operation.new(%{
        method: "ping",
        params: %{},
        progress_opts: Keyword.get(opts, :progress),
        timeout: Keyword.get(opts, :timeout)
      })

    buffer_timeout = operation.timeout + to_timeout(second: 1)
    GenServer.call(client, {:operation, operation}, buffer_timeout)
  end

  @doc """
  Lists available resources from the server.

  ## Options

    * `:cursor` - Pagination cursor for continuing a previous request
    * `:timeout` - Request timeout in milliseconds
    * `:progress` - Progress tracking options
      * `:token` - A unique token to track progress (string or integer)
      * `:callback` - A function to call when progress updates are received
  """
  @spec list_resources(t, keyword) :: {:ok, Response.t()} | {:error, Error.t()}
  def list_resources(client, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    params = if cursor, do: %{"cursor" => cursor}, else: %{}

    operation =
      Operation.new(%{
        method: "resources/list",
        params: params,
        progress_opts: Keyword.get(opts, :progress),
        timeout: Keyword.get(opts, :timeout)
      })

    buffer_timeout = operation.timeout + to_timeout(second: 1)
    GenServer.call(client, {:operation, operation}, buffer_timeout)
  end

  @doc """
  Reads a specific resource from the server.

  ## Options

    * `:timeout` - Request timeout in milliseconds
    * `:progress` - Progress tracking options
      * `:token` - A unique token to track progress (string or integer)
      * `:callback` - A function to call when progress updates are received
  """
  @spec read_resource(t, String.t(), keyword) ::
          {:ok, Response.t()} | {:error, Error.t()}
  def read_resource(client, uri, opts \\ []) do
    operation =
      Operation.new(%{
        method: "resources/read",
        params: %{"uri" => uri},
        progress_opts: Keyword.get(opts, :progress),
        timeout: Keyword.get(opts, :timeout)
      })

    buffer_timeout = operation.timeout + to_timeout(second: 1)
    GenServer.call(client, {:operation, operation}, buffer_timeout)
  end

  @doc """
  Lists available prompts from the server.

  ## Options

    * `:cursor` - Pagination cursor for continuing a previous request
    * `:timeout` - Request timeout in milliseconds
    * `:progress` - Progress tracking options
      * `:token` - A unique token to track progress (string or integer)
      * `:callback` - A function to call when progress updates are received
  """
  @spec list_prompts(t, keyword) :: {:ok, Response.t()} | {:error, Error.t()}
  def list_prompts(client, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    params = if cursor, do: %{"cursor" => cursor}, else: %{}

    operation =
      Operation.new(%{
        method: "prompts/list",
        params: params,
        progress_opts: Keyword.get(opts, :progress),
        timeout: Keyword.get(opts, :timeout)
      })

    buffer_timeout = operation.timeout + to_timeout(second: 1)
    GenServer.call(client, {:operation, operation}, buffer_timeout)
  end

  @doc """
  Gets a specific prompt from the server.

  ## Options

    * `:timeout` - Request timeout in milliseconds
    * `:progress` - Progress tracking options
      * `:token` - A unique token to track progress (string or integer)
      * `:callback` - A function to call when progress updates are received
  """
  @spec get_prompt(t, String.t(), map() | nil, keyword) ::
          {:ok, Response.t()} | {:error, Error.t()}
  def get_prompt(client, name, arguments \\ nil, opts \\ []) do
    params = %{"name" => name}
    params = if arguments, do: Map.put(params, "arguments", arguments), else: params

    operation =
      Operation.new(%{
        method: "prompts/get",
        params: params,
        progress_opts: Keyword.get(opts, :progress),
        timeout: Keyword.get(opts, :timeout)
      })

    buffer_timeout = operation.timeout + to_timeout(second: 1)
    GenServer.call(client, {:operation, operation}, buffer_timeout)
  end

  @doc """
  Lists available tools from the server.

  ## Options

    * `:cursor` - Pagination cursor for continuing a previous request
    * `:timeout` - Request timeout in milliseconds
    * `:progress` - Progress tracking options
      * `:token` - A unique token to track progress (string or integer)
      * `:callback` - A function to call when progress updates are received
  """
  @spec list_tools(t, keyword) :: {:ok, Response.t()} | {:error, Error.t()}
  def list_tools(client, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    params = if cursor, do: %{"cursor" => cursor}, else: %{}

    operation =
      Operation.new(%{
        method: "tools/list",
        params: params,
        progress_opts: Keyword.get(opts, :progress),
        timeout: Keyword.get(opts, :timeout)
      })

    buffer_timeout = operation.timeout + to_timeout(second: 1)
    GenServer.call(client, {:operation, operation}, buffer_timeout)
  end

  @doc """
  Calls a tool on the server.

  ## Options

    * `:timeout` - Request timeout in milliseconds
    * `:progress` - Progress tracking options
      * `:token` - A unique token to track progress (string or integer)
      * `:callback` - A function to call when progress updates are received
    * `:headers` - HTTP headers to send with this request (map, only for StreamableHTTP transport)
  """
  @spec call_tool(t, String.t(), map() | nil, keyword) ::
          {:ok, Response.t()} | {:error, Error.t()}
  def call_tool(client, name, arguments \\ nil, opts \\ []) do
    params = %{"name" => name}
    params = if arguments, do: Map.put(params, "arguments", arguments), else: params

    operation =
      Operation.new(%{
        method: "tools/call",
        params: params,
        progress_opts: Keyword.get(opts, :progress),
        timeout: Keyword.get(opts, :timeout),
        headers: Keyword.get(opts, :headers)
      })

    buffer_timeout = operation.timeout + to_timeout(second: 1)
    GenServer.call(client, {:operation, operation}, buffer_timeout)
  end

  @doc """
  Merges additional capabilities into the client's capabilities.
  """
  @spec merge_capabilities(t, map(), opts :: Keyword.t()) :: map()
  def merge_capabilities(client, additional_capabilities, opts \\ []) do
    timeout = opts[:timeout] || to_timeout(second: 5)
    GenServer.call(client, {:merge_capabilities, additional_capabilities}, timeout)
  end

  @doc """
  Gets the server's capabilities as reported during initialization.

  Returns `nil` if the client has not been initialized yet.
  """
  @spec get_server_capabilities(t, opts :: Keyword.t()) :: map() | nil
  def get_server_capabilities(client, opts \\ []) do
    timeout = opts[:timeout] || to_timeout(second: 5)
    GenServer.call(client, :get_server_capabilities, timeout)
  end

  @doc """
  Gets the server's information as reported during initialization.

  Returns `nil` if the client has not been initialized yet.
  """
  @spec get_server_info(t, opts :: Keyword.t()) :: map() | nil
  def get_server_info(client, opts \\ []) do
    timeout = opts[:timeout] || to_timeout(second: 5)
    GenServer.call(client, :get_server_info, timeout)
  end

  @doc """
  Sets the minimum log level for the server to send log messages.

  ## Parameters

    * `client` - The client process
    * `level` - The minimum log level (debug, info, notice, warning, error, critical, alert, emergency)

  Returns {:ok, result} if successful, {:error, reason} otherwise.
  """
  @spec set_log_level(t, String.t()) :: {:ok, Response.t()} | {:error, Error.t()}
  def set_log_level(client, level) when level in ~w(debug info notice warning error critical alert emergency) do
    operation =
      Operation.new(%{
        method: "logging/setLevel",
        params: %{"level" => level}
      })

    buffer_timeout = operation.timeout + to_timeout(second: 1)
    GenServer.call(client, {:operation, operation}, buffer_timeout)
  end

  @doc """
  Requests autocompletion suggestions for prompt arguments or resource URIs.

  ## Parameters

    * `client` - The client process
    * `ref` - Reference to what is being completed (required)
      * For prompts: `%{"type" => "ref/prompt", "name" => prompt_name}`
      * For resources: `%{"type" => "ref/resource", "uri" => resource_uri}`
    * `argument` - The argument being completed (required)
      * `%{"name" => arg_name, "value" => current_value}`
    * `opts` - Additional options
      * `:timeout` - Request timeout in milliseconds
      * `:progress` - Progress tracking options
        * `:token` - A unique token to track progress (string or integer)
        * `:callback` - A function to call when progress updates are received

  ## Returns

  Returns `{:ok, response}` with completion suggestions if successful, or `{:error, reason}` if an error occurs.

  The response result contains a "completion" object with:
  * `values` - List of completion suggestions (maximum 100)
  * `total` - Optional total number of matching items
  * `hasMore` - Boolean indicating if more results are available

  ## Examples

      # Get completion for a prompt argument
      ref = %{"type" => "ref/prompt", "name" => "code_review"}
      argument = %{"name" => "language", "value" => "py"}
      {:ok, response} = Hermes.Client.complete(client, ref, argument)

      # Access the completion values
      values = get_in(Response.unwrap(response), ["completion", "values"])
  """
  @spec complete(t, map(), map(), keyword()) ::
          {:ok, Response.t()} | {:error, Error.t()}
  def complete(client, ref, argument, opts \\ []) do
    params = %{
      "ref" => ref,
      "argument" => argument
    }

    operation =
      Operation.new(%{
        method: "completion/complete",
        params: params,
        progress_opts: Keyword.get(opts, :progress),
        timeout: Keyword.get(opts, :timeout)
      })

    buffer_timeout = operation.timeout + to_timeout(second: 1)
    GenServer.call(client, {:operation, operation}, buffer_timeout)
  end

  @doc """
  Registers a callback function to be called when log messages are received.

  ## Parameters

    * `client` - The client process
    * `callback` - A function that takes three arguments: level, data, and logger name

  The callback function will be called whenever a log message notification is received.
  """
  @spec register_log_callback(t, log_callback(), opts :: Keyword.t()) :: :ok
  def register_log_callback(client, callback, opts \\ []) when is_function(callback, 3) do
    timeout = opts[:timeout] || to_timeout(second: 5)
    GenServer.call(client, {:register_log_callback, callback}, timeout)
  end

  @doc """
  Unregisters a previously registered log callback.

  ## Parameters

    * `client` - The client process
    * `callback` - The callback function to unregister
  """
  @spec unregister_log_callback(t, opts :: Keyword.t()) :: :ok
  def unregister_log_callback(client, opts \\ []) do
    timeout = opts[:timeout] || to_timeout(second: 5)
    GenServer.call(client, :unregister_log_callback, timeout)
  end

  @doc """
  Registers a callback function to be called when progress notifications are received
  for the specified progress token.

  ## Parameters

    * `client` - The client process
    * `progress_token` - The progress token to watch for (string or integer)
    * `callback` - A function that takes three arguments: progress_token, progress, and total

  The callback function will be called whenever a progress notification with the
  matching token is received.
  """
  @spec register_progress_callback(
          t,
          String.t() | integer(),
          progress_callback(),
          opts :: Keyword.t()
        ) ::
          :ok
  def register_progress_callback(client, progress_token, callback, opts \\ [])
      when is_function(callback, 3) and (is_binary(progress_token) or is_integer(progress_token)) do
    timeout = opts[:timeout] || to_timeout(second: 5)

    GenServer.call(
      client,
      {:register_progress_callback, progress_token, callback},
      timeout
    )
  end

  @doc """
  Unregisters a previously registered progress callback for the specified token.

  ## Parameters

    * `client` - The client process
    * `progress_token` - The progress token to stop watching (string or integer)
  """
  @spec unregister_progress_callback(t, String.t() | integer(), opts :: Keyword.t()) ::
          :ok
  def unregister_progress_callback(client, progress_token, opts \\ [])
      when is_binary(progress_token) or is_integer(progress_token) do
    timeout = opts[:timeout] || to_timeout(second: 5)
    GenServer.call(client, {:unregister_progress_callback, progress_token}, timeout)
  end

  @doc """
  Sends a progress notification to the server for a long-running operation.

  ## Parameters

    * `client` - The client process
    * `progress_token` - The progress token provided in the original request (string or integer)
    * `progress` - The current progress value (number)
    * `total` - The optional total value for the operation (number)

  Returns `:ok` if notification was sent successfully, or `{:error, reason}` otherwise.
  """
  @spec send_progress(
          t,
          String.t() | integer(),
          number(),
          number() | nil,
          opts :: Keyword.t()
        ) ::
          :ok | {:error, term()}
  def send_progress(client, progress_token, progress, total \\ nil, opts \\ [])
      when is_number(progress) and (is_binary(progress_token) or is_integer(progress_token)) do
    timeout = opts[:timeout] || to_timeout(second: 5)

    GenServer.call(
      client,
      {:send_progress, progress_token, progress, total},
      timeout
    )
  end

  @doc """
  Cancels an in-progress request.

  ## Parameters

    * `client` - The client process
    * `request_id` - The ID of the request to cancel
    * `reason` - Optional reason for cancellation

  ## Returns

    * `:ok` if the cancellation was successful
    * `{:error, reason}` if an error occurred
    * `{:not_found, request_id}` if the request ID was not found
  """
  @spec cancel_request(t, String.t(), String.t(), opts :: Keyword.t()) ::
          :ok | {:error, Error.t()}
  def cancel_request(client, request_id, reason \\ "client_cancelled", opts \\ []) do
    timeout = opts[:timeout] || to_timeout(second: 5)
    GenServer.call(client, {:cancel_request, request_id, reason}, timeout)
  end

  @doc """
  Cancels all pending requests.

  ## Parameters

    * `client` - The client process
    * `reason` - Optional reason for cancellation (defaults to "client_cancelled")

  ## Returns

    * `{:ok, requests}` - A list of the Request structs that were cancelled
    * `{:error, reason}` - If an error occurred
  """
  @spec cancel_all_requests(t, String.t(), opts :: Keyword.t()) ::
          {:ok, list(Request.t())} | {:error, Error.t()}
  def cancel_all_requests(client, reason \\ "client_cancelled", opts \\ []) do
    timeout = opts[:timeout] || to_timeout(second: 5)
    GenServer.call(client, {:cancel_all_requests, reason}, timeout)
  end

  @doc """
  Adds a root directory to the client's roots list.

  ## Parameters

    * `client` - The client process
    * `uri` - The URI of the root directory (must start with "file://")
    * `name` - Optional human-readable name for the root
    * `opts` - Additional options
      * `:timeout` - Request timeout in milliseconds

  ## Examples

      iex> Hermes.Client.add_root(client, "file:///home/user/project", "My Project")
      :ok
  """
  @spec add_root(t, String.t(), String.t() | nil, opts :: Keyword.t()) :: :ok
  def add_root(client, uri, name \\ nil, opts \\ []) when is_binary(uri) do
    timeout = opts[:timeout] || to_timeout(second: 5)
    GenServer.call(client, {:add_root, uri, name}, timeout)
  end

  @doc """
  Removes a root directory from the client's roots list.

  ## Parameters

    * `client` - The client process
    * `uri` - The URI of the root directory to remove
    * `opts` - Additional options
      * `:timeout` - Request timeout in milliseconds

  ## Examples

      iex> Hermes.Client.remove_root(client, "file:///home/user/project")
      :ok
  """
  @spec remove_root(t, String.t(), opts :: Keyword.t()) :: :ok
  def remove_root(client, uri, opts \\ []) when is_binary(uri) do
    timeout = opts[:timeout] || to_timeout(second: 5)
    GenServer.call(client, {:remove_root, uri}, timeout)
  end

  @doc """
  Gets a list of all root directories.

  ## Parameters

    * `client` - The client process
    * `opts` - Additional options
      * `:timeout` - Request timeout in milliseconds

  ## Examples

      iex> Hermes.Client.list_roots(client)
      [%{uri: "file:///home/user/project", name: "My Project"}]
  """
  @spec list_roots(t, opts :: Keyword.t()) :: [map()]
  def list_roots(client, opts \\ []) do
    timeout = opts[:timeout] || to_timeout(second: 5)
    GenServer.call(client, :list_roots, timeout)
  end

  @doc """
  Clears all root directories.

  ## Parameters

    * `client` - The client process
    * `opts` - Additional options
      * `:timeout` - Request timeout in milliseconds

  ## Examples

      iex> Hermes.Client.clear_roots(client)
      :ok
  """
  @spec clear_roots(t, opts :: Keyword.t()) :: :ok
  def clear_roots(client, opts \\ []) do
    timeout = opts[:timeout] || to_timeout(second: 5)
    GenServer.call(client, :clear_roots, timeout)
  end

  @doc """
  Registers a callback function to handle sampling requests from the server.

  The callback function will be called when the server sends a `sampling/createMessage` request.
  The callback should implement user approval and return the LLM response.

  ## Callback Function

  The callback receives the sampling parameters and must return:
  - `{:ok, response_map}` - Where response_map contains:
    - `"role"` - Usually "assistant"
    - `"content"` - Message content (text, image, or audio)
    - `"model"` - The model that was used
    - `"stopReason"` - Why generation stopped (e.g., "endTurn")
  - `{:error, reason}` - If the user rejects or an error occurs

  ## Example

      MyClient.register_sampling_callback(fn params ->
        messages = params["messages"]

        # Show UI for user approval
        case MyUI.approve_sampling(messages) do
          {:approved, edited_messages} ->
            # Call LLM with approved/edited messages
            response = MyLLM.generate(edited_messages, params["modelPreferences"])
            {:ok, response}

          :rejected ->
            {:error, "User rejected sampling request"}
        end
      end)
  """
  @spec register_sampling_callback(
          t,
          (map() -> {:ok, map()} | {:error, String.t()})
        ) :: :ok
  def register_sampling_callback(client, callback) when is_function(callback, 1) do
    GenServer.call(client, {:register_sampling_callback, callback})
  end

  @doc """
  Unregisters the sampling callback.
  """
  @spec unregister_sampling_callback(t) :: :ok
  def unregister_sampling_callback(client) do
    GenServer.call(client, :unregister_sampling_callback)
  end

  @doc """
  Closes the client connection and terminates the process.
  """
  @spec close(t) :: :ok
  def close(client) do
    GenServer.cast(client, :close)
  end

  # GenServer Callbacks

  @impl true
  def init(%{} = opts) do
    layer = opts.transport[:layer]
    name = opts.transport[:name] || layer
    protocol_version = opts.protocol_version
    transport = %{layer: layer, name: name}

    state =
      State.new(%{
        client_info: opts.client_info,
        capabilities: opts.capabilities,
        protocol_version: protocol_version,
        transport: transport
      })

    client_name = get_in(opts, [:client_info, "name"])

    Logger.metadata(
      mcp_client: opts.name,
      mcp_client_name: client_name,
      mcp_transport: opts.transport
    )

    Logging.client_event("initializing", %{
      protocol_version: protocol_version,
      capabilities: opts.capabilities,
      transport: layer
    })

    Telemetry.execute(
      Telemetry.event_client_init(),
      %{system_time: System.system_time()},
      %{
        client_name: client_name,
        transport: transport,
        protocol_version: protocol_version,
        capabilities: opts.capabilities
      }
    )

    {:ok, state, :hibernate}
  end

  @impl true
  def handle_call({:operation, %Operation{} = operation}, from, state) do
    method = operation.method
    opts = [headers: operation.headers, timeout: operation.timeout]

    params_with_token =
      State.add_progress_token_to_params(operation.params, operation.progress_opts)

    with :ok <- State.validate_capability(state, method),
         {request_id, updated_state} =
           State.add_request_from_operation(state, operation, from),
         {:ok, request_data} <- encode_request(method, params_with_token, request_id),
         :ok <- send_to_transport(state.transport, request_data, opts) do
      Telemetry.execute(
        Telemetry.event_client_request(),
        %{system_time: System.system_time()},
        %{method: method, request_id: request_id}
      )

      {:noreply, updated_state}
    else
      err -> {:reply, err, state}
    end
  end

  def handle_call({:merge_capabilities, additional_capabilities}, _from, state) do
    updated = State.merge_capabilities(state, additional_capabilities)
    {:reply, updated.capabilities, updated}
  end

  def handle_call(:get_server_capabilities, _from, state) do
    {:reply, State.get_server_capabilities(state), state}
  end

  def handle_call(:get_server_info, _from, state) do
    {:reply, State.get_server_info(state), state}
  end

  def handle_call({:register_log_callback, callback}, _from, state) do
    {:reply, :ok, State.set_log_callback(state, callback)}
  end

  def handle_call(:unregister_log_callback, _from, state) do
    {:reply, :ok, State.clear_log_callback(state)}
  end

  def handle_call({:register_sampling_callback, callback}, _from, state) do
    {:reply, :ok, State.set_sampling_callback(state, callback)}
  end

  def handle_call(:unregister_sampling_callback, _from, state) do
    {:reply, :ok, State.clear_sampling_callback(state)}
  end

  def handle_call({:register_progress_callback, token, callback}, _from, state) do
    {:reply, :ok, State.register_progress_callback(state, token, callback)}
  end

  def handle_call({:unregister_progress_callback, token}, _from, state) do
    {:reply, :ok, State.unregister_progress_callback(state, token)}
  end

  def handle_call({:send_progress, progress_token, progress, total}, _from, state) do
    {:reply,
     with {:ok, notification} <-
            Message.encode_progress_notification(%{
              "progressToken" => progress_token,
              "progress" => progress,
              "total" => total
            }) do
       send_to_transport(state.transport, notification)
     end, state}
  end

  def handle_call({:add_root, uri, name}, _from, state) do
    {:reply, :ok, State.add_root(state, uri, name), {:continue, :roots_list_changed}}
  end

  def handle_call({:remove_root, uri}, _from, state) do
    {:reply, :ok, State.remove_root(state, uri), {:continue, :roots_list_changed}}
  end

  def handle_call(:list_roots, _from, state) do
    {:reply, State.list_roots(state), state}
  end

  def handle_call(:clear_roots, _from, state) do
    {:reply, :ok, State.clear_roots(state), {:continue, :roots_list_changed}}
  end

  def handle_call({:cancel_request, request_id, reason}, _from, state) do
    with true <- Map.has_key?(state.pending_requests, request_id),
         :ok <- send_cancellation(state, request_id, reason) do
      {request, updated_state} = State.remove_request(state, request_id)

      error =
        Error.transport(:request_cancelled, %{
          message: "Request cancelled by client",
          reason: reason
        })

      GenServer.reply(request.from, {:error, error})
      {:reply, :ok, updated_state}
    else
      false -> {:reply, Error.transport(:request_not_found), state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:cancel_all_requests, reason}, _from, state) do
    pending_requests = State.list_pending_requests(state)

    if Enum.empty?(pending_requests) do
      {:reply, {:ok, []}, state}
    else
      cancelled_requests =
        for request <- pending_requests do
          _ = send_cancellation(state, request.id, reason)

          error =
            Error.transport(:request_cancelled, %{
              message: "Request cancelled by client",
              reason: reason
            })

          GenServer.reply(request.from, {:error, error})

          request
        end

      {:reply, {:ok, cancelled_requests}, %{state | pending_requests: %{}}}
    end
  end

  @impl true
  def handle_continue(:roots_list_changed, state) do
    Task.start(fn -> send_roots_list_changed_notification(state) end)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:close, state) do
    {:stop, :normal, state}
  end

  def handle_cast(:initialize, state) do
    Logging.client_event("handshake", "Making initial client <> server handshake")

    params = %{
      "protocolVersion" => state.protocol_version,
      "capabilities" => state.capabilities,
      "clientInfo" => state.client_info
    }

    operation =
      Operation.new(%{
        method: "initialize",
        params: params
      })

    {request_id, updated_state} =
      State.add_request_from_operation(state, operation, {self(), make_ref()})

    with {:ok, request_data} <- encode_request("initialize", params, request_id),
         :ok <- send_to_transport(state.transport, request_data) do
      {:noreply, updated_state}
    else
      err -> {:stop, err, state}
    end
  rescue
    e ->
      err = Exception.format(:error, e, __STACKTRACE__)
      Logging.client_event("initialization_failed", %{error: err})
      {:stop, :unexpected, state}
  end

  @impl true
  def handle_cast({:response, response_data}, state) do
    case Message.decode(response_data) do
      {:ok, [message]} ->
        {:noreply, handle_message(message, state)}

      {:error, error} ->
        Logging.client_event("decode_failed", %{error: error}, level: :warning)
        {:noreply, state}
    end
  rescue
    e ->
      err = Exception.format(:error, e, __STACKTRACE__)
      Logging.client_event("response_handling_failed", %{error: err}, level: :error)

      {:noreply, state}
  end

  # Server request handling

  defp handle_server_request(%{"method" => "roots/list", "id" => id}, state) do
    roots = State.list_roots(state)
    roots_result = %{"roots" => roots}
    roots_count = Enum.count(roots)

    with {:ok, response_data} <-
           Message.encode_response(%{"result" => roots_result}, id),
         :ok <- send_to_transport(state.transport, response_data) do
      Logging.client_event("roots_list_request", %{id: id, roots_count: roots_count})

      Telemetry.execute(
        Telemetry.event_client_roots(),
        %{system_time: System.system_time()},
        %{action: :list, count: roots_count, request_id: id}
      )

      {:noreply, state}
    else
      err ->
        Logging.client_event("roots_list_error", %{id: id, error: err}, level: :error)

        Telemetry.execute(
          Telemetry.event_client_error(),
          %{system_time: System.system_time()},
          %{method: "roots/list", request_id: id, error: err}
        )

        {:noreply, state}
    end
  end

  defp handle_server_request(%{"method" => "ping", "id" => id}, state) do
    with {:ok, response_data} <- Message.encode_response(%{"result" => %{}}, id),
         :ok <- send_to_transport(state.transport, response_data) do
      {:noreply, state}
    else
      err ->
        Logging.client_event("ping_response_error", %{id: id, error: err}, level: :error)

        Telemetry.execute(
          Telemetry.event_client_error(),
          %{system_time: System.system_time()},
          %{method: "ping", request_id: id, error: err}
        )

        {:noreply, state}
    end
  end

  defp handle_server_request(%{"method" => "sampling/createMessage", "id" => id} = request, state) do
    params = Map.get(request, "params", %{})

    case validate_sampling_capability(state) do
      :ok ->
        handle_sampling_with_callback(id, params, state)

      {:error, reason} ->
        send_sampling_error(id, reason, "capability_disabled", %{}, state)
    end
  end

  @impl true
  def handle_info({:request_timeout, request_id}, state) do
    case State.handle_request_timeout(state, request_id) do
      {nil, state} ->
        {:noreply, state}

      {request, updated_state} ->
        elapsed_ms = Request.elapsed_time(request)

        error =
          Error.transport(:request_timeout, %{
            message: "Request timed out after #{elapsed_ms}ms"
          })

        GenServer.reply(request.from, {:error, error})

        _ = send_cancellation(updated_state, request_id, "timeout")

        {:noreply, updated_state}
    end
  end

  @impl true
  def terminate(reason, %{client_info: %{"name" => name}} = state) do
    Logging.client_event("terminating", %{
      name: name,
      reason: reason
    })

    pending_requests = State.list_pending_requests(state)
    pending_count = length(pending_requests)

    if pending_count > 0 do
      Logging.client_event("pending_requests", %{
        count: pending_count
      })
    end

    Telemetry.execute(
      Telemetry.event_client_terminate(),
      %{system_time: System.system_time()},
      %{
        client_name: name,
        reason: reason,
        pending_requests: pending_count
      }
    )

    for request <- pending_requests do
      error =
        Error.transport(:request_cancelled, %{
          message: "Request cancelled by client",
          reason: "client closed"
        })

      GenServer.reply(request.from, {:error, error})

      send_notification(state, "notifications/cancelled", %{
        "requestId" => request.id,
        "reason" => "client closed"
      })
    end

    state.transport.layer.shutdown(state.transport.name)
  end

  # Message handling

  defp handle_message(message, state) do
    cond do
      Message.is_error(message) ->
        Logging.message("incoming", "error", message["id"], message)
        handle_error_response(message, message["id"], state)

      Message.is_response(message) ->
        Logging.message("incoming", "response", message["id"], message)
        handle_success_response(message, message["id"], state)

      Message.is_notification(message) ->
        Logging.message("incoming", "notification", nil, message)
        handle_notification(message, state)

      Message.is_request(message) ->
        Logging.message("incoming", "request", message["id"], message)
        {_, state} = handle_server_request(message, state)
        state

      true ->
        state
    end
  end

  # Response handling

  defp handle_error_response(%{"error" => json_error, "id" => id}, id, state) do
    case State.remove_request(state, id) do
      {nil, state} ->
        log_unknown_error_response(id, json_error)
        state

      {request, updated_state} ->
        process_error_response(request, json_error, id, updated_state)
    end
  end

  defp log_unknown_error_response(id, json_error) do
    Logging.client_event("unknown_error_response", %{
      id: id,
      code: json_error["code"],
      message: json_error["message"]
    })
  end

  defp process_error_response(request, json_error, id, state) do
    error = Error.from_json_rpc(json_error)
    elapsed_ms = Request.elapsed_time(request)

    log_error_response(request, id, elapsed_ms, json_error)
    GenServer.reply(request.from, {:error, error})

    state
  end

  defp log_error_response(request, id, elapsed_ms, error) do
    Logging.client_event("error_response", %{
      id: id,
      method: request.method
    })

    Telemetry.execute(
      Telemetry.event_client_error(),
      %{duration: elapsed_ms, system_time: System.system_time()},
      %{
        id: id,
        method: request.method,
        error_code: error["code"],
        error_message: error["message"]
      }
    )
  end

  defp handle_success_response(%{"id" => id, "result" => %{"serverInfo" => _} = result}, id, state) do
    case State.remove_request(state, id) do
      {nil, state} ->
        state

      {_request, state} ->
        state =
          State.update_server_info(
            state,
            result["capabilities"],
            result["serverInfo"]
          )

        Logging.client_event("initialized", %{
          server_info: result["serverInfo"],
          capabilities: result["capabilities"]
        })

        :ok = send_notification(state, "notifications/initialized")

        state
    end
  end

  defp handle_success_response(%{"id" => id, "result" => result}, id, state) do
    case State.remove_request(state, id) do
      {nil, state} ->
        Logging.client_event("unknown_response", %{id: id})
        state

      {request, updated_state} ->
        process_successful_response(request, result, id, updated_state)
    end
  end

  defp process_successful_response(request, result, id, state) do
    response = Response.from_json_rpc(%{"result" => result, "id" => id})
    response = %{response | method: request.method}
    elapsed_ms = Request.elapsed_time(request)

    log_success_response(request, id, elapsed_ms)

    method = request.method
    from = request.from

    if method == "ping",
      do: GenServer.reply(from, :pong),
      else: GenServer.reply(from, {:ok, response})

    state
  end

  defp log_success_response(request, id, elapsed_ms) do
    Logging.client_event("success_response", %{id: id, method: request.method})

    Telemetry.execute(
      Telemetry.event_client_response(),
      %{duration: elapsed_ms, system_time: System.system_time()},
      %{
        id: id,
        method: request.method,
        status: :success
      }
    )
  end

  # Notification handling

  defp handle_notification(%{"method" => "notifications/progress"} = notification, state) do
    handle_progress_notification(notification, state)
  end

  defp handle_notification(%{"method" => "notifications/message"} = notification, state) do
    handle_log_notification(notification, state)
  end

  defp handle_notification(%{"method" => "notifications/cancelled"} = notification, state) do
    handle_cancelled_notification(notification, state)
  end

  defp handle_notification(%{"method" => "notifications/resources/list_changed"} = notification, state) do
    handle_resources_list_changed_notification(notification, state)
  end

  defp handle_notification(%{"method" => "notifications/resources/updated"} = notification, state) do
    handle_resource_updated_notification(notification, state)
  end

  defp handle_notification(%{"method" => "notifications/prompts/list_changed"} = notification, state) do
    handle_prompts_list_changed_notification(notification, state)
  end

  defp handle_notification(%{"method" => "notifications/tools/list_changed"} = notification, state) do
    handle_tools_list_changed_notification(notification, state)
  end

  defp handle_notification(_, state), do: state

  defp handle_cancelled_notification(%{"params" => params}, state) do
    request_id = params["requestId"]
    reason = Map.get(params, "reason", "unknown")

    {request, updated_state} = State.remove_request(state, request_id)

    if request do
      Logging.client_event("request_cancelled", %{
        id: request_id,
        reason: reason
      })

      error =
        Error.transport(:request_cancelled, %{
          message: "Request cancelled by server",
          reason: reason
        })

      GenServer.reply(request.from, {:error, error})
    end

    updated_state
  end

  defp handle_progress_notification(%{"params" => params}, state) do
    progress_token = params["progressToken"]
    progress = params["progress"]
    total = Map.get(params, "total")

    if callback = State.get_progress_callback(state, progress_token) do
      Task.start(fn -> callback.(progress_token, progress, total) end)
    end

    state
  end

  defp handle_log_notification(%{"params" => params}, state) do
    level = params["level"]
    data = params["data"]
    logger = Map.get(params, "logger")

    if callback = State.get_log_callback(state) do
      Task.start(fn -> callback.(level, data, logger) end)
    end

    log_to_logger(level, data, logger)

    state
  end

  defp log_to_logger(level, data, logger) do
    elixir_level =
      case level do
        level when level in ["debug"] -> :debug
        level when level in ["info", "notice"] -> :info
        level when level in ["warning"] -> :warning
        level when level in ["error", "critical", "alert", "emergency"] -> :error
        _ -> :info
      end

    Logging.client_event("server_log", %{level: level, data: data, logger: logger}, level: elixir_level)
  end

  defp handle_resources_list_changed_notification(_notification, state) do
    Logging.client_event("resources_list_changed", nil)

    Telemetry.execute(
      Telemetry.event_client_notification(),
      %{system_time: System.system_time()},
      %{method: "resources/list_changed"}
    )

    state
  end

  defp handle_resource_updated_notification(%{"params" => params}, state) do
    uri = params["uri"]

    Logging.client_event("resource_updated", %{uri: uri})

    Telemetry.execute(
      Telemetry.event_client_notification(),
      %{system_time: System.system_time()},
      %{method: "resources/updated", uri: uri}
    )

    state
  end

  defp handle_prompts_list_changed_notification(_notification, state) do
    Logging.client_event("prompts_list_changed", nil)

    Telemetry.execute(
      Telemetry.event_client_notification(),
      %{system_time: System.system_time()},
      %{method: "prompts/list_changed"}
    )

    state
  end

  defp handle_tools_list_changed_notification(_notification, state) do
    Logging.client_event("tools_list_changed", nil)

    Telemetry.execute(
      Telemetry.event_client_notification(),
      %{system_time: System.system_time()},
      %{method: "tools/list_changed"}
    )

    state
  end

  # Helper functions

  defp encode_request(method, params, request_id) do
    request = %{"method" => method, "params" => params}
    Logging.message("outgoing", "request", request_id, request)
    Message.encode_request(request, request_id)
  end

  defp encode_notification(method, params) do
    notification = %{"method" => method, "params" => params}
    Logging.message("outgoing", "notification", nil, notification)
    Message.encode_notification(notification)
  end

  defp send_cancellation(state, request_id, reason) do
    params = %{
      "requestId" => request_id,
      "reason" => reason
    }

    send_notification(state, "notifications/cancelled", params)
  end

  defp send_to_transport(transport, data, opts \\ []) do
    with {:error, reason} <- transport.layer.send_message(transport.name, data, opts) do
      {:error, Error.transport(:send_failure, %{original_reason: reason})}
    end
  end

  defp send_notification(state, method, params \\ %{}) do
    with {:ok, notification_data} <- encode_notification(method, params) do
      send_to_transport(state.transport, notification_data)
    end
  end

  defp send_roots_list_changed_notification(state) do
    Logging.client_event("sending_roots_list_changed", nil)
    send_notification(state, "notifications/roots/list_changed")
  end

  defp validate_sampling_capability(state) do
    if Map.has_key?(state.capabilities, "sampling") do
      :ok
    else
      {:error, "Client does not have sampling capability enabled"}
    end
  end

  defp handle_sampling_with_callback(id, params, state) do
    case State.get_sampling_callback(state) do
      nil ->
        send_sampling_error(
          id,
          "No sampling callback registered",
          "sampling_not_configured",
          %{},
          state
        )

      callback when is_function(callback, 1) ->
        execute_sampling_callback(id, params, callback, state)
    end
  end

  defp execute_sampling_callback(id, params, callback, state) do
    Task.start(fn ->
      try do
        case callback.(params) do
          {:ok, result} ->
            handle_sampling_result(id, result, state)

          {:error, message} ->
            send_sampling_error(id, message, "sampling_error", %{}, state)
        end
      rescue
        e ->
          error_message = "Sampling callback error: #{Exception.message(e)}"

          send_sampling_error(
            id,
            error_message,
            "sampling_callback_error",
            %{},
            state
          )
      end
    end)

    {:noreply, state}
  end

  defp handle_sampling_result(id, result, state) do
    case Message.encode_sampling_response(%{"result" => result}, id) do
      {:ok, validated} ->
        send_sampling_response(id, validated, state)

      {:error, [%Peri.Error{} | _] = errors} ->
        error_message = "Invalid sampling response"

        send_sampling_error(
          id,
          error_message,
          "invalid_sampling_response",
          errors,
          state
        )

      {:error, reason} ->
        error_message = "Invalid sampling response: #{reason}"

        send_sampling_error(
          id,
          error_message,
          "invalid_sampling_response",
          reason,
          state
        )
    end
  end

  defp send_sampling_response(id, response, state) do
    transport = state.transport
    :ok = transport.layer.send_message(transport.name, response, [])

    Telemetry.execute(
      Telemetry.event_client_response(),
      %{system_time: System.system_time()},
      %{id: id, method: "sampling/createMessage"}
    )
  end

  defp send_sampling_error(id, message, code, reason, %{transport: transport} = state) do
    error = %Error{code: -1, message: message, data: %{"reason" => reason}}
    {:ok, response} = Error.to_json_rpc(error, id)
    :ok = transport.layer.send_message(transport.name, response, [])

    Logging.client_event(
      "sampling_error",
      %{
        id: id,
        error_code: code,
        error_message: message
      },
      level: :error
    )

    Telemetry.execute(
      Telemetry.event_client_error(),
      %{system_time: System.system_time()},
      %{id: id, method: "sampling/createMessage", error_code: code}
    )

    {:noreply, state}
  end
end
