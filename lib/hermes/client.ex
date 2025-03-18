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

  alias Hermes.Client.State
  alias Hermes.MCP.Error
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
  @spec unregister_log_callback(GenServer.server()) :: :ok
  def unregister_log_callback(client) do
    GenServer.call(client, :unregister_log_callback)
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

    state =
      State.new(%{
        client_info: opts.client_info,
        capabilities: opts.capabilities,
        protocol_version: opts.protocol_version,
        request_timeout: opts.request_timeout,
        transport: transport
      })

    Logger.metadata(mcp_client: opts.name, mcp_transport: opts.transport)

    {:ok, state, :hibernate}
  end

  @impl true
  def handle_call({:request, method, params}, from, state) do
    with :ok <- State.validate_capability(state, method),
         {request_id, updated_state} = State.add_request(state, method, params, from),
         {:ok, request_data} <- encode_request(method, params, request_id),
         :ok <- send_to_transport(state.transport, request_data) do
      {:noreply, updated_state}
    else
      {:error, _reason} = err -> {:reply, err, state}
    end
  end

  def handle_call({:request, method, params, progress_opts}, from, state) do
    state = maybe_register_progress_callback(state, progress_opts)
    params = maybe_add_progress_token(params, progress_opts)

    with :ok <- State.validate_capability(state, method),
         {request_id, updated_state} = State.add_request(state, method, params, from),
         {:ok, request_data} <- encode_request(method, params, request_id),
         :ok <- send_to_transport(state.transport, request_data) do
      {:noreply, updated_state}
    else
      {:error, _reason} = err -> {:reply, err, state}
    end
  end

  def handle_call({:merge_capabilities, additional_capabilities}, _from, state) do
    updated_state = State.merge_capabilities(state, additional_capabilities)
    {:reply, updated_state.capabilities, updated_state}
  end

  def handle_call(:get_server_capabilities, _from, state) do
    {:reply, State.get_server_capabilities(state), state}
  end

  def handle_call(:get_server_info, _from, state) do
    {:reply, State.get_server_info(state), state}
  end

  def handle_call({:register_log_callback, callback}, _from, state) do
    updated_state = State.set_log_callback(state, callback)
    {:reply, :ok, updated_state}
  end

  def handle_call(:unregister_log_callback, _from, state) do
    updated_state = State.clear_log_callback(state)
    {:reply, :ok, updated_state}
  end

  def handle_call({:register_progress_callback, token, callback}, _from, state) do
    updated_state = State.register_progress_callback(state, token, callback)
    {:reply, :ok, updated_state}
  end

  def handle_call({:unregister_progress_callback, token}, _from, state) do
    updated_state = State.unregister_progress_callback(state, token)
    {:reply, :ok, updated_state}
  end

  def handle_call({:send_progress, progress_token, progress, total}, _from, state) do
    result =
      with {:ok, notification} <- Message.encode_progress_notification(progress_token, progress, total) do
        send_to_transport(state.transport, notification)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_cast(:close, state) do
    pending_requests = State.list_pending_requests(state)

    if length(pending_requests) > 0 do
      Logger.warning("Closing client with #{length(pending_requests)} pending requests")
    end

    for request <- pending_requests do
      send_notification(state, "notifications/cancelled", %{
        "requestId" => request.id,
        "reason" => "client closed"
      })
    end

    state.transport.layer.shutdown(state.transport.name)

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

    {request_id, updated_state} = State.add_request(state, "initialize", params, {self(), make_ref()})

    with {:ok, request_data} <- encode_request("initialize", params, request_id),
         :ok <- send_to_transport(state.transport, request_data) do
      {:noreply, updated_state}
    else
      err -> {:stop, err, state}
    end
  rescue
    e ->
      err = Exception.format(:error, e, __STACKTRACE__)
      Logger.error("Failed to initialize client: #{err}")
      {:stop, :unexpected, state}
  end

  def handle_info({:request_timeout, request_id}, state) do
    case State.handle_request_timeout(state, request_id) do
      {nil, state} ->
        {:noreply, state}

      {request_info, updated_state} ->
        error = Error.client_error(:request_timeout, %{message: "Request timed out after #{request_info.elapsed_ms}ms"})
        GenServer.reply(request_info.from, {:error, error})

        {:noreply, updated_state}
    end
  end

  def handle_info({:response, response_data}, state) do
    case Message.decode(response_data) do
      {:ok, [error]} when Message.is_error(error) ->
        Logger.debug("Received server error response: #{inspect(error)}")
        {:noreply, handle_error_response(error, error["id"], state)}

      {:ok, [response]} when Message.is_response(response) ->
        Logger.debug("Received server response: #{response["id"]}")
        {:noreply, handle_success_response(response, response["id"], state)}

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

  defp handle_error_response(%{"error" => json_error, "id" => id}, id, state) do
    case State.remove_request(state, id) do
      {nil, state} ->
        Logger.warning("Received error response for unknown request ID: #{id}")
        state

      {request_info, updated_state} ->
        # Convert JSON-RPC error to our domain error
        error = Error.from_json_rpc(json_error)

        # Unblock original caller with error
        GenServer.reply(request_info.from, {:error, error})

        updated_state
    end
  end

  defp handle_error_response(%{"id" => id}, _id, state) do
    Logger.warning("Received malformed error response for request ID: #{id}")
    state
  end

  defp handle_success_response(%{"id" => id, "result" => %{"serverInfo" => _} = result}, id, state) do
    case State.remove_request(state, id) do
      {nil, state} ->
        state

      {_request_info, updated_state} ->
        # Update server info in state
        updated_state =
          State.update_server_info(
            updated_state,
            result["capabilities"],
            result["serverInfo"]
          )

        Logger.info("Initialized successfully, notifying server")

        # Confirm to the server the handshake is complete
        :ok = send_notification(updated_state, "notifications/initialized")

        updated_state
    end
  end

  defp handle_success_response(%{"id" => id, "result" => result}, id, state) do
    case State.remove_request(state, id) do
      {nil, state} ->
        Logger.warning("Received response for unknown request ID: #{id}")
        state

      {request_info, updated_state} ->
        # Convert to our domain response
        response = Response.from_json_rpc(%{"result" => result, "id" => id})

        if request_info.method == "ping" do
          GenServer.reply(request_info.from, :pong)
        else
          GenServer.reply(request_info.from, {:ok, response})
        end

        updated_state
    end
  end

  defp handle_success_response(%{"id" => id}, _id, state) do
    Logger.warning("Received malformed response for request ID: #{id}")
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

    if callback = State.get_progress_callback(state, progress_token) do
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
    if callback = State.get_log_callback(state) do
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
      State.register_progress_callback(state, token, callback)
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
  defp encode_request(method, params, request_id) do
    Message.encode_request(%{"method" => method, "params" => params}, request_id)
  end

  defp encode_notification(method, params) do
    Message.encode_notification(%{"method" => method, "params" => params})
  end

  defp send_to_transport(transport, data) do
    with {:error, reason} <- transport.layer.send_message(transport.name, data) do
      {:error, Error.transport_error(:send_failure, %{original_reason: reason})}
    end
  end

  defp send_notification(state, method, params \\ %{}) do
    with {:ok, notification_data} <- encode_notification(method, params) do
      send_to_transport(state.transport, notification_data)
    end
  end
end
