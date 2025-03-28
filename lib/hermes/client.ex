defmodule Hermes.Client do
  @moduledoc """
  A GenServer implementation of an MCP (Model Context Protocol) client.

  This module handles the client-side implementation of the MCP protocol,
  including initialization, request/response handling, and maintaining
  protocol state.

  > ## Notes {: .info}
  >
  > For initialization and setup, check our [Installation & Setup](./installation.html) and
  > the [Client Usage](./client_usage.html) guides for reference.
  """

  use GenServer

  import Peri

  alias Hermes.Client.Request
  alias Hermes.Client.State
  alias Hermes.MCP.Error
  alias Hermes.MCP.Message
  alias Hermes.MCP.Response

  require Hermes.MCP.Message
  require Logger

  @default_protocol_version "2024-11-05"
  @default_timeout to_timeout(second: 30)

  @type t :: GenServer.server()

  @typedoc """
  MCP client transport options

  - `:layer` - The transport layer to use, either `Hermes.Transport.STDIO` or `Hermes.Transport.SSE` (required)
  - `:name` - The transport optional custom name
  """
  @type transport ::
          list(
            {:layer, Hermes.Transport.STDIO | Hermes.Transport.SSE}
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
  - `:request_timeout` - Default timeout for requests in milliseconds (default: 30s)

  Any other option support by `GenServer`.
  """
  @type option ::
          {:name, GenServer.name()}
          | {:transport, transport}
          | {:client_info, map}
          | {:capabilities, map}
          | {:protocol_version, String.t()}
          | {:request_timeout, integer}
          | GenServer.option()

  @default_client_capabilities %{"roots" => %{"listChanged" => true}, "sampling" => %{}}

  defschema(:parse_options, [
    {:name, {{:custom, &Hermes.genserver_name/1}, {:default, __MODULE__}}},
    {:transport,
     [
       layer: {:required, :atom},
       name: {:oneof, [{:custom, &Hermes.genserver_name/1}, :pid, {:tuple, [:atom, :any]}]}
     ]},
    {:client_info, {:required, :map}},
    {:capabilities, {:map, {:default, @default_client_capabilities}}},
    {:protocol_version, {:string, {:default, @default_protocol_version}}},
    {:request_timeout, {:integer, {:default, @default_timeout}}}
  ])

  @doc """
  Starts a new MCP client process.
  """
  @spec start_link(Enumerable.t(option)) :: GenServer.on_start()
  def start_link(opts) do
    opts = parse_options!(opts)
    GenServer.start_link(__MODULE__, Map.new(opts), name: opts[:name])
  end

  @doc """
  Sends a ping request to the server to check connection health. Returns `:pong` if successful.
  """
  @spec ping(t, keyword) :: :pong | {:error, Error.t()}
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
  @spec list_resources(t, keyword) :: {:ok, Response.t()} | {:error, Error.t()}
  def list_resources(client, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    timeout = Keyword.get(opts, :timeout)
    progress_opts = Keyword.get(opts, :progress)

    params = if cursor, do: %{"cursor" => cursor}, else: %{}

    if progress_opts do
      GenServer.call(
        client,
        {:request, "resources/list", params, progress_opts},
        timeout || @default_timeout
      )
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
  @spec read_resource(t, String.t(), keyword) :: {:ok, Response.t()} | {:error, Error.t()}
  def read_resource(client, uri, opts \\ []) do
    timeout = Keyword.get(opts, :timeout)
    progress_opts = Keyword.get(opts, :progress)

    params = %{"uri" => uri}

    if progress_opts do
      GenServer.call(
        client,
        {:request, "resources/read", params, progress_opts},
        timeout || @default_timeout
      )
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
  @spec list_prompts(t, keyword) :: {:ok, Response.t()} | {:error, Error.t()}
  def list_prompts(client, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    timeout = Keyword.get(opts, :timeout)
    progress_opts = Keyword.get(opts, :progress)

    params = if cursor, do: %{"cursor" => cursor}, else: %{}

    if progress_opts do
      GenServer.call(
        client,
        {:request, "prompts/list", params, progress_opts},
        timeout || @default_timeout
      )
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
  @spec get_prompt(t, String.t(), map() | nil, keyword) ::
          {:ok, Response.t()} | {:error, Error.t()}
  def get_prompt(client, name, arguments \\ nil, opts \\ []) do
    timeout = Keyword.get(opts, :timeout)
    progress_opts = Keyword.get(opts, :progress)

    params = %{"name" => name}
    params = if arguments, do: Map.put(params, "arguments", arguments), else: params

    if progress_opts do
      GenServer.call(
        client,
        {:request, "prompts/get", params, progress_opts},
        timeout || @default_timeout
      )
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
  @spec list_tools(t, keyword) :: {:ok, Response.t()} | {:error, Error.t()}
  def list_tools(client, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    timeout = Keyword.get(opts, :timeout)
    progress_opts = Keyword.get(opts, :progress)

    params = if cursor, do: %{"cursor" => cursor}, else: %{}

    if progress_opts do
      GenServer.call(
        client,
        {:request, "tools/list", params, progress_opts},
        timeout || @default_timeout
      )
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
  @spec call_tool(t, String.t(), map() | nil, keyword) ::
          {:ok, Response.t()} | {:error, Error.t()}
  def call_tool(client, name, arguments \\ nil, opts \\ []) do
    timeout = Keyword.get(opts, :timeout)
    progress_opts = Keyword.get(opts, :progress)

    params = %{"name" => name}
    params = if arguments, do: Map.put(params, "arguments", arguments), else: params

    if progress_opts do
      GenServer.call(
        client,
        {:request, "tools/call", params, progress_opts},
        timeout || @default_timeout
      )
    else
      GenServer.call(client, {:request, "tools/call", params}, timeout || @default_timeout)
    end
  end

  @doc """
  Merges additional capabilities into the client's capabilities.
  """
  @spec merge_capabilities(t, map()) :: map()
  def merge_capabilities(client, additional_capabilities) do
    GenServer.call(client, {:merge_capabilities, additional_capabilities})
  end

  @doc """
  Gets the server's capabilities as reported during initialization.

  Returns `nil` if the client has not been initialized yet.
  """
  @spec get_server_capabilities(t) :: map() | nil
  def get_server_capabilities(client) do
    GenServer.call(client, :get_server_capabilities)
  end

  @doc """
  Gets the server's information as reported during initialization.

  Returns `nil` if the client has not been initialized yet.
  """
  @spec get_server_info(t) :: map() | nil
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
  @spec set_log_level(t, String.t()) :: {:ok, Response.t()} | {:error, Error.t()}
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
  @spec register_log_callback(t, State.log_callback()) :: :ok
  def register_log_callback(client, callback) when is_function(callback, 3) do
    GenServer.call(client, {:register_log_callback, callback})
  end

  @doc """
  Unregisters a previously registered log callback.

  ## Parameters

    * `client` - The client process
    * `callback` - The callback function to unregister
  """
  @spec unregister_log_callback(t) :: :ok
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
  @spec register_progress_callback(
          t,
          String.t() | integer(),
          State.progress_callback()
        ) ::
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
  @spec unregister_progress_callback(t, String.t() | integer()) :: :ok
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
  @spec send_progress(t, String.t() | integer(), number(), number() | nil) ::
          :ok | {:error, term()}
  def send_progress(client, progress_token, progress, total \\ nil)
      when is_number(progress) and (is_binary(progress_token) or is_integer(progress_token)) do
    GenServer.call(client, {:send_progress, progress_token, progress, total})
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
  @spec cancel_request(t, String.t(), String.t()) ::
          :ok | {:error, Error.t()}
  def cancel_request(client, request_id, reason \\ "client_cancelled") do
    GenServer.call(client, {:cancel_request, request_id, reason})
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
  @spec cancel_all_requests(t, String.t()) ::
          {:ok, list(Request.t())} | {:error, Error.t()}
  def cancel_all_requests(client, reason \\ "client_cancelled") do
    GenServer.call(client, {:cancel_all_requests, reason})
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
      with {:ok, notification} <-
             Message.encode_progress_notification(progress_token, progress, total) do
        send_to_transport(state.transport, notification)
      end

    {:reply, result, state}
  end

  def handle_call({:cancel_request, request_id, reason}, _from, state) do
    with true <- Map.has_key?(state.pending_requests, request_id),
         :ok <- send_cancellation(state, request_id, reason) do
      {request, updated_state} = State.remove_request(state, request_id)

      error =
        Error.client_error(:request_cancelled, %{
          message: "Request cancelled by client",
          reason: reason
        })

      GenServer.reply(request.from, {:error, error})
      {:reply, :ok, updated_state}
    else
      false -> {:reply, Error.client_error(:request_not_found), state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:cancel_all_requests, reason}, _from, state) do
    pending_requests = State.list_pending_requests(state)

    if Enum.empty?(pending_requests) do
      {:reply, {:ok, []}, state}
    else
      # Process all pending requests
      cancelled_requests =
        for request <- pending_requests do
          # Send cancellation notification and ignore errors
          _ = send_cancellation(state, request.id, reason)

          # Notify the original caller with error
          error =
            Error.client_error(:request_cancelled, %{
              message: "Request cancelled by client",
              reason: reason
            })

          GenServer.reply(request.from, {:error, error})

          # Return the request for the response
          request
        end

      # Return with empty pending requests map and list of cancelled requests
      {:reply, {:ok, cancelled_requests}, %{state | pending_requests: %{}}}
    end
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

  def handle_cast(:initialize, state) do
    Logger.debug("Making initial client <> server handshake")

    params = %{
      "protocolVersion" => state.protocol_version,
      "capabilities" => state.capabilities,
      "clientInfo" => state.client_info
    }

    {request_id, updated_state} =
      State.add_request(state, "initialize", params, {self(), make_ref()})

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

  @impl true
  def handle_cast({:response, response_data}, state) do
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

  @impl true
  def handle_info({:request_timeout, request_id}, state) do
    case State.handle_request_timeout(state, request_id) do
      {nil, state} ->
        {:noreply, state}

      {request, updated_state} ->
        elapsed_ms = Request.elapsed_time(request)

        error =
          Error.client_error(:request_timeout, %{
            message: "Request timed out after #{elapsed_ms}ms"
          })

        GenServer.reply(request.from, {:error, error})

        # Send cancellation notification when a request times out
        _ = send_cancellation(updated_state, request_id, "timeout")

        {:noreply, updated_state}
    end
  end

  # Response handling

  defp handle_error_response(%{"error" => json_error, "id" => id}, id, state) do
    case State.remove_request(state, id) do
      {nil, state} ->
        Logger.warning("Received error response for unknown request ID: #{id}")
        state

      {request, updated_state} ->
        # Convert JSON-RPC error to our domain error
        error = Error.from_json_rpc(json_error)

        # Unblock original caller with error
        GenServer.reply(request.from, {:error, error})

        updated_state
    end
  end

  defp handle_success_response(%{"id" => id, "result" => %{"serverInfo" => _} = result}, id, state) do
    case State.remove_request(state, id) do
      {nil, state} ->
        state

      {_request, updated_state} ->
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

      {request, updated_state} ->
        # Convert to our domain response
        response = Response.from_json_rpc(%{"result" => result, "id" => id})

        if request.method == "ping" do
          GenServer.reply(request.from, :pong)
        else
          GenServer.reply(request.from, {:ok, response})
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

  defp handle_notification(%{"method" => "notifications/cancelled"} = notification, state) do
    handle_cancelled_notification(notification, state)
  end

  defp handle_notification(_, state), do: state

  defp handle_cancelled_notification(%{"params" => params}, state) do
    request_id = params["requestId"]
    reason = Map.get(params, "reason", "unknown")

    {request, updated_state} = State.remove_request(state, request_id)

    if request do
      Logger.info("Request #{request_id} cancelled by server: #{reason}")

      error =
        Error.client_error(:request_cancelled, %{
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

  defp send_cancellation(state, request_id, reason) do
    params = %{
      "requestId" => request_id,
      "reason" => reason
    }

    send_notification(state, "notifications/cancelled", params)
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
