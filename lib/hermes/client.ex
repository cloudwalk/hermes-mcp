defmodule Hermes.Client do
  @moduledoc """
  A GenServer implementation of an MCP (Model Context Protocol) client.

  This module handles the client-side implementation of the MCP protocol,
  including initialization, request/response handling, and maintaining
  protocol state.

  ## Examples

      # Start a client process
      {:ok, client} = Hermes.Client.start_link(
        name: MyApp.MCPClient,
        transport: Hermes.Transport.STDIO,
        client_info: %{"name" => "MyApp", "version" => "1.0.0"},
        capabilities: %{"resources" => %{}, "tools" => %{}}
      )

      # List available resources
      {:ok, resources} = Hermes.Client.list_resources(client)

  ## Notes

  The initial client <> server handshake is performed automatically when the client is started.
  """

  use GenServer

  import Peri

  alias Hermes.MCP.Error
  alias Hermes.MCP.ID
  alias Hermes.MCP.Message
  alias Hermes.MCP.Response

  require Hermes.MCP.Message
  require Logger

  @default_protocol_version "2024-11-05"
  @default_timeout to_timeout(second: 30)

  @type progress_callback :: (String.t() | integer(), number(), number() | nil -> any())
  @type log_callback :: (String.t(), term(), String.t() | nil -> any())
  @type option ::
          {:name, atom}
          | {:transport, module}
          | {:client_info, map}
          | {:capabilities, map}
          | {:protocol_version, String.t()}
          | {:request_timeout, integer}
          | Supervisor.init_option()

  @transports [Hermes.Transport.STDIO, Hermes.Transport.SSE]

  defschema(:parse_options, [
    {:name, {:atom, {:default, __MODULE__}}},
    {:transport,
     [
       layer: {:required, {:enum, if(Hermes.dev_env?(), do: [Hermes.MockTransport | @transports], else: @transports)}},
       name: :atom
     ]},
    {:client_info, {:required, :map}},
    {:capabilities, {:map, {:default, %{"resources" => %{}, "tools" => %{}, "logging" => %{}}}}},
    {:protocol_version, {:string, {:default, @default_protocol_version}}},
    {:request_timeout, {:integer, {:default, @default_timeout}}}
  ])

  @doc """
  Starts a new MCP client process.

  ## Options

    * `:name` - Optional name to register the client process
    * `:transport` - The transport process or name to use (required)
    * `:client_info` - Information about the client (required)
    * `:capabilities` - Client capabilities to advertise
    * `:protocol_version` - Protocol version to use (defaults to "2024-11-05")
    * `:request_timeout` - Default timeout for requests in milliseconds (default: 30s)
  """
  @spec start_link(list(option)) :: Supervisor.on_start()
  def start_link(opts) do
    opts = parse_options!(opts)
    GenServer.start_link(__MODULE__, Map.new(opts), name: opts[:name])
  end

  @doc """
  Sends a ping request to the server to check connection health. Returns `:pong` if successful.
  """
  def ping(client, opts \\ []) when is_list(opts) do
    timeout = Keyword.get(opts, :timeout)
    progress_opts = Keyword.get(opts, :progress)

    if progress_opts do
      GenServer.call(client, {:request, "ping", %{}, progress_opts}, timeout || @default_timeout)
    else
      GenServer.call(client, {:request, "ping", %{}}, timeout || @default_timeout)
    end
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
  def list_resources(client, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    timeout = Keyword.get(opts, :timeout)
    progress_opts = Keyword.get(opts, :progress)

    params = if cursor, do: %{"cursor" => cursor}, else: %{}

    if progress_opts do
      GenServer.call(client, {:request, "resources/list", params, progress_opts}, timeout || @default_timeout)
    else
      GenServer.call(client, {:request, "resources/list", params}, timeout || @default_timeout)
    end
  end

  @doc """
  Reads a specific resource from the server.

  ## Options

    * `:timeout` - Request timeout in milliseconds
    * `:progress` - Progress tracking options
      * `:token` - A unique token to track progress (string or integer)
      * `:callback` - A function to call when progress updates are received
  """
  def read_resource(client, uri, opts \\ []) do
    timeout = Keyword.get(opts, :timeout)
    progress_opts = Keyword.get(opts, :progress)

    params = %{"uri" => uri}

    if progress_opts do
      GenServer.call(client, {:request, "resources/read", params, progress_opts}, timeout || @default_timeout)
    else
      GenServer.call(client, {:request, "resources/read", params}, timeout || @default_timeout)
    end
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
  def list_prompts(client, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    timeout = Keyword.get(opts, :timeout)
    progress_opts = Keyword.get(opts, :progress)

    params = if cursor, do: %{"cursor" => cursor}, else: %{}

    if progress_opts do
      GenServer.call(client, {:request, "prompts/list", params, progress_opts}, timeout || @default_timeout)
    else
      GenServer.call(client, {:request, "prompts/list", params}, timeout || @default_timeout)
    end
  end

  @doc """
  Gets a specific prompt from the server.

  ## Options

    * `:timeout` - Request timeout in milliseconds
    * `:progress` - Progress tracking options
      * `:token` - A unique token to track progress (string or integer)
      * `:callback` - A function to call when progress updates are received
  """
  def get_prompt(client, name, arguments \\ nil, opts \\ []) do
    timeout = Keyword.get(opts, :timeout)
    progress_opts = Keyword.get(opts, :progress)

    params = %{"name" => name}
    params = if arguments, do: Map.put(params, "arguments", arguments), else: params

    if progress_opts do
      GenServer.call(client, {:request, "prompts/get", params, progress_opts}, timeout || @default_timeout)
    else
      GenServer.call(client, {:request, "prompts/get", params}, timeout || @default_timeout)
    end
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
  def list_tools(client, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    timeout = Keyword.get(opts, :timeout)
    progress_opts = Keyword.get(opts, :progress)

    params = if cursor, do: %{"cursor" => cursor}, else: %{}

    if progress_opts do
      GenServer.call(client, {:request, "tools/list", params, progress_opts}, timeout || @default_timeout)
    else
      GenServer.call(client, {:request, "tools/list", params}, timeout || @default_timeout)
    end
  end

  @doc """
  Calls a tool on the server.

  ## Options

    * `:timeout` - Request timeout in milliseconds
    * `:progress` - Progress tracking options
      * `:token` - A unique token to track progress (string or integer)
      * `:callback` - A function to call when progress updates are received
  """
  def call_tool(client, name, arguments \\ nil, opts \\ []) do
    timeout = Keyword.get(opts, :timeout)
    progress_opts = Keyword.get(opts, :progress)

    params = %{"name" => name}
    params = if arguments, do: Map.put(params, "arguments", arguments), else: params

    if progress_opts do
      GenServer.call(client, {:request, "tools/call", params, progress_opts}, timeout || @default_timeout)
    else
      GenServer.call(client, {:request, "tools/call", params}, timeout || @default_timeout)
    end
  end

  @doc """
  Merges additional capabilities into the client's capabilities.
  """
  def merge_capabilities(client, additional_capabilities) do
    GenServer.call(client, {:merge_capabilities, additional_capabilities})
  end

  @doc """
  Gets the server's capabilities as reported during initialization.

  Returns `nil` if the client has not been initialized yet.
  """
  def get_server_capabilities(client) do
    GenServer.call(client, :get_server_capabilities)
  end

  @doc """
  Gets the server's information as reported during initialization.

  Returns `nil` if the client has not been initialized yet.
  """
  def get_server_info(client) do
    GenServer.call(client, :get_server_info)
  end

  @doc """
  Sets the minimum log level for the server to send log messages.

  ## Parameters

    * `client` - The client process
    * `level` - The minimum log level (debug, info, notice, warning, error, critical, alert, emergency)

  Returns {:ok, result} if successful, {:error, reason} otherwise.
  """
  @spec set_log_level(GenServer.server(), String.t()) :: {:ok, map()} | {:error, term()}
  def set_log_level(client, level) when level in ~w(debug info notice warning error critical alert emergency) do
    GenServer.call(client, {:request, "logging/setLevel", %{"level" => level}})
  end

  @doc """
  Registers a callback function to be called when log messages are received.

  ## Parameters

    * `client` - The client process
    * `callback` - A function that takes three arguments: level, data, and logger name

  The callback function will be called whenever a log message notification is received.
  """
  @spec register_log_callback(GenServer.server(), log_callback()) :: :ok
  def register_log_callback(client, callback) when is_function(callback, 3) do
    GenServer.call(client, {:register_log_callback, callback})
  end

  @doc """
  Unregisters a previously registered log callback.

  ## Parameters

    * `client` - The client process
    * `callback` - The callback function to unregister
  """
  @spec unregister_log_callback(GenServer.server(), log_callback()) :: :ok
  def unregister_log_callback(client, callback) when is_function(callback, 3) do
    GenServer.call(client, {:unregister_log_callback, callback})
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
  @spec register_progress_callback(GenServer.server(), String.t() | integer(), progress_callback()) ::
          :ok
  def register_progress_callback(client, progress_token, callback)
      when is_function(callback, 3) and (is_binary(progress_token) or is_integer(progress_token)) do
    GenServer.call(client, {:register_progress_callback, progress_token, callback})
  end

  @doc """
  Unregisters a previously registered progress callback for the specified token.

  ## Parameters

    * `client` - The client process
    * `progress_token` - The progress token to stop watching (string or integer)
  """
  @spec unregister_progress_callback(GenServer.server(), String.t() | integer()) :: :ok
  def unregister_progress_callback(client, progress_token) when is_binary(progress_token) or is_integer(progress_token) do
    GenServer.call(client, {:unregister_progress_callback, progress_token})
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
  @spec send_progress(GenServer.server(), String.t() | integer(), number(), number() | nil) ::
          :ok | {:error, term()}
  def send_progress(client, progress_token, progress, total \\ nil)
      when is_number(progress) and (is_binary(progress_token) or is_integer(progress_token)) do
    GenServer.call(client, {:send_progress, progress_token, progress, total})
  end

  @doc """
  Closes the client connection and terminates the process.
  """
  def close(client) do
    GenServer.cast(client, :close)
  end

  # GenServer Callbacks

  @impl true
  def init(%{} = opts) do
    layer = opts.transport[:layer]
    name = opts.transport[:name] || layer

    transport = %{layer: layer, name: name}

    state = %{
      transport: transport,
      client_info: opts.client_info,
      capabilities: opts.capabilities,
      server_capabilities: nil,
      server_info: nil,
      protocol_version: opts.protocol_version,
      request_timeout: opts.request_timeout,
      pending_requests: Map.new(),
      progress_callbacks: Map.new(),
      log_level: nil,
      log_callback: nil
    }

    Logger.metadata(mcp_client: opts.name, mcp_transport: opts.transport)

    {:ok, state, :hibernate}
  end

  @impl true
  def handle_call({:request, method, params}, from, state) do
    request_id = generate_request_id()

    with :ok <- validate_capability(state, method),
         {:ok, request_data} <- encode_request(method, params, request_id),
         :ok <- send_to_transport(state.transport, request_data) do
      pending = Map.put(state.pending_requests, request_id, {from, method})

      {:noreply, %{state | pending_requests: pending}}
    else
      err -> {:reply, err, state}
    end
  end

  def handle_call({:request, method, params, progress_opts}, from, state) do
    request_id = generate_request_id()
    state = maybe_register_progress_callback(state, progress_opts)
    params = maybe_add_progress_token(params, progress_opts)

    with :ok <- validate_capability(state, method),
         {:ok, request_data} <- encode_request(method, params, request_id),
         :ok <- send_to_transport(state.transport, request_data) do
      pending = Map.put(state.pending_requests, request_id, {from, method})

      {:noreply, %{state | pending_requests: pending}}
    else
      err -> {:reply, err, state}
    end
  end

  def handle_call({:merge_capabilities, additional_capabilities}, _from, state) do
    updated_capabilities = deep_merge(state.capabilities, additional_capabilities)

    {:reply, updated_capabilities, %{state | capabilities: updated_capabilities}}
  end

  def handle_call(:get_server_capabilities, _from, state) do
    {:reply, state.server_capabilities, state}
  end

  def handle_call(:get_server_info, _from, state) do
    {:reply, state.server_info, state}
  end

  def handle_call({:register_log_callback, callback}, _from, state) do
    {:reply, :ok, %{state | log_callback: callback}}
  end

  def handle_call({:unregister_log_callback, _callback}, _from, state) do
    {:reply, :ok, %{state | log_callback: nil}}
  end

  def handle_call({:register_progress_callback, token, callback}, _from, state) do
    progress_callbacks = Map.put(state.progress_callbacks, token, callback)
    {:reply, :ok, %{state | progress_callbacks: progress_callbacks}}
  end

  def handle_call({:unregister_progress_callback, token}, _from, state) do
    progress_callbacks = Map.delete(state.progress_callbacks, token)
    {:reply, :ok, %{state | progress_callbacks: progress_callbacks}}
  end

  def handle_call({:send_progress, progress_token, progress, total}, _from, state) do
    result =
      with {:ok, notification} <- Message.encode_progress_notification(progress_token, progress, total) do
        send_to_transport(state.transport, notification)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_cast(:close, %{transport: transport, pending_requests: pending} = state) do
    if map_size(pending) > 0 do
      Logger.warning("Closing client with #{map_size(pending)} pending requests")
    end

    for {request_id, _} <- pending do
      send_notification(state, "notifications/cancelled", %{
        "requestId" => request_id,
        "reason" => "client closed"
      })
    end

    transport.layer.shutdown(transport.name)

    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:initialize, state) do
    Logger.debug("Making initial client <> server handshake")

    params = %{
      "protocolVersion" => state.protocol_version,
      "capabilities" => state.capabilities,
      "clientInfo" => state.client_info
    }

    request_id = generate_request_id()

    with {:ok, request_data} <- encode_request("initialize", params, request_id),
         :ok <- send_to_transport(state.transport, request_data) do
      from = {self(), generate_request_id()}
      pending = Map.put(state.pending_requests, request_id, {from, "initialize"})

      {:noreply, %{state | pending_requests: pending}}
    else
      err -> {:stop, err, state}
    end
  rescue
    e ->
      err = Exception.format(:error, e, __STACKTRACE__)
      Logger.error("Failed to initialize client: #{err}")
      {:stop, :unexpected, state}
  end

  def handle_info({:response, response_data}, state) do
    case Message.decode(response_data) do
      {:ok, [error]} when Message.is_error(error) ->
        Logger.debug("Received server error response: #{inspect(error)}")
        {:noreply, handle_error(error, error["id"], state)}

      {:ok, [response]} when Message.is_response(response) ->
        Logger.debug("Received server response: #{response["id"]}")
        {:noreply, handle_response(response, response["id"], state)}

      {:ok, [notification]} when Message.is_notification(notification) ->
        method = notification["method"]
        Logger.debug("Received server notification: #{method}")
        {:noreply, handle_notification(notification, state)}

      {:error, error} ->
        Logger.error("Failed to decode response: #{inspect(error)}")
        {:noreply, state}
    end
  rescue
    e ->
      err = Exception.format(:error, e, __STACKTRACE__)
      Logger.error("Failed to handle response: #{err}")
      {:noreply, state}
  end

  # Response handling

  defp handle_error(%{"error" => json_error, "id" => id}, id, state) do
    {{from, _method}, pending} = Map.pop(state.pending_requests, id)

    # Convert JSON-RPC error to our domain error
    error = Error.from_json_rpc(json_error)

    # unblocks original caller
    GenServer.reply(from, {:error, error})

    %{state | pending_requests: pending}
  end

  defp handle_error(response, _, state) do
    Logger.warning("Received error response for unknown request ID: #{response["id"]}")
    state
  end

  defp handle_response(%{"id" => id, "result" => %{"serverInfo" => _} = result}, id, state) do
    %{pending_requests: pending} = state

    state = %{
      state
      | server_capabilities: result["capabilities"],
        server_info: result["serverInfo"],
        pending_requests: Map.delete(pending, id)
    }

    Logger.info("Initialized successfully, notifing server")

    # we need to confirm to the server the handshake
    :ok = send_notification(state, "notifications/initialized")

    state
  end

  defp handle_response(%{"id" => id, "result" => result}, id, state) do
    {{from, method}, pending} = Map.pop(state.pending_requests, id)

    # Convert to our domain response
    response = Response.from_json_rpc(%{"result" => result, "id" => id})

    # unblocks original caller
    cond do
      method == "ping" -> GenServer.reply(from, :pong)
      Response.error?(response) -> GenServer.reply(from, {:error, response.result})
      true -> GenServer.reply(from, {:ok, response.result})
    end

    %{state | pending_requests: pending}
  end

  defp handle_response(%{"id" => _} = response, _, state) do
    Logger.warning("Received response for unknown request ID: #{response["id"]}")
    state
  end

  # Notification handling

  defp handle_notification(%{"method" => "notifications/progress"} = notification, state) do
    handle_progress_notification(notification, state)
  end

  defp handle_notification(%{"method" => "notifications/message"} = notification, state) do
    handle_log_notification(notification, state)
  end

  defp handle_notification(_, state), do: state

  defp handle_progress_notification(%{"params" => params}, state) do
    progress_token = params["progressToken"]
    progress = params["progress"]
    total = Map.get(params, "total")

    if callback = Map.get(state.progress_callbacks, progress_token) do
      # Execute the callback in a separate process to avoid blocking
      Task.start(fn -> callback.(progress_token, progress, total) end)
    end

    state
  end

  defp handle_log_notification(%{"params" => params}, state) do
    level = params["level"]
    data = params["data"]
    logger = Map.get(params, "logger")

    # Execute callback if registered
    if callback = state.log_callback do
      Task.start(fn -> callback.(level, data, logger) end)
    end

    # Log to Elixir's Logger for convenience
    log_to_logger(level, data, logger)

    state
  end

  defp log_to_logger(level, data, logger) do
    prefix = if logger, do: "[#{logger}] ", else: ""
    message = "#{prefix}#{inspect(data)}"

    # Map MCP log levels to Elixir Logger levels
    case level do
      level when level in ["debug"] ->
        Logger.debug(message)

      level when level in ["info", "notice"] ->
        Logger.info(message)

      level when level in ["warning"] ->
        Logger.warning(message)

      level when level in ["error", "critical", "alert", "emergency"] ->
        Logger.error(message)

      _ ->
        Logger.info(message)
    end
  end

  defp maybe_register_progress_callback(state, progress_opts) do
    with {:ok, opts} when not is_nil(opts) <- {:ok, progress_opts},
         {:ok, callback} when is_function(callback, 3) <- {:ok, Keyword.get(opts, :callback)},
         {:ok, token} when not is_nil(token) <- {:ok, Keyword.get(opts, :token)} do
      progress_callbacks = Map.put(state.progress_callbacks, token, callback)
      %{state | progress_callbacks: progress_callbacks}
    else
      _ -> state
    end
  end

  defp maybe_add_progress_token(params, progress_opts) do
    with {:ok, opts} when not is_nil(opts) <- {:ok, progress_opts},
         {:ok, token} when not is_nil(token) and (is_binary(token) or is_integer(token)) <-
           {:ok, Keyword.get(opts, :token)} do
      meta = %{"progressToken" => token}
      Map.put(params, "_meta", meta)
    else
      _ -> params
    end
  end

  # Helper functions

  defp validate_capability(%{server_capabilities: nil}, _method) do
    {:error, :server_capabilities_not_set}
  end

  defp validate_capability(%{server_capabilities: server_capabilities}, method) do
    capability = String.split(method, "/", parts: 2)

    if valid_capability?(server_capabilities, capability) do
      :ok
    else
      {:error, {:capability_not_supported, method}}
    end
  end

  defp valid_capability?(_capabilities, ["initialize"]), do: true
  defp valid_capability?(_capabilities, ["ping"]), do: true

  defp valid_capability?(capabilities, ["resources", sub]) when sub in ~w(subscribe unsubscribe) do
    if resources = Map.get(capabilities, "resources") do
      valid_capability?(resources, [sub, nil])
    end
  end

  defp valid_capability?(%{} = capabilities, [capability, _]) do
    Map.has_key?(capabilities, capability)
  end

  defp generate_request_id do
    ID.generate_request_id()
  end

  defp encode_request(method, params, request_id) do
    Message.encode_request(%{"method" => method, "params" => params}, request_id)
  end

  defp encode_notification(method, params) do
    Message.encode_notification(%{"method" => method, "params" => params})
  end

  defp send_to_transport(transport, data) do
    with {:error, reason} <- transport.layer.send_message(transport.name, data) do
      {:error, {:transport_error, reason}}
    end
  end

  defp send_notification(state, method, params \\ %{}) do
    with {:ok, notification_data} <- encode_notification(method, params) do
      send_to_transport(state.transport, notification_data)
    end
  end

  defp deep_merge(map1, map2) do
    Map.merge(map1, map2, fn
      _, v1, v2 when is_map(v1) and is_map(v2) -> deep_merge(v1, v2)
      _, _, v2 -> v2
    end)
  end
end
