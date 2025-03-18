defmodule Hermes.Client.State do
  @moduledoc """
  Manages state for the Hermes MCP client.

  This module provides a structured representation of client state,
  including capabilities, server info, and request tracking.

  ## State Structure

  Each client state includes:
  - `client_info`: Information about the client
  - `capabilities`: Client capabilities
  - `server_capabilities`: Server capabilities received during initialization
  - `server_info`: Server information received during initialization
  - `protocol_version`: MCP protocol version being used
  - `request_timeout`: Default timeout for requests
  - `transport`: Transport module or transport info
  - `pending_requests`: Map of pending requests with details and timers
  - `progress_callbacks`: Map of callbacks for progress tracking
  - `log_callback`: Callback for handling log messages

  ## Examples

  ```elixir
  # Create a new client state
  state = Hermes.Client.State.new(%{
    client_info: %{"name" => "MyClient", "version" => "1.0.0"},
    capabilities: %{"resources" => %{}},
    protocol_version: "2024-11-05",
    request_timeout: 30000,
    transport: %{layer: Hermes.Transport.SSE, name: MyTransport}
  })

  # Add a request to the state
  {request_id, updated_state} = Hermes.Client.State.add_request(state, "ping", %{}, from)

  # Get server capabilities
  server_capabilities = Hermes.Client.State.get_server_capabilities(state)
  ```
  """

  alias Hermes.MCP.ID

  @type progress_callback :: (String.t() | integer(), number(), number() | nil -> any())
  @type log_callback :: (String.t(), term(), String.t() | nil -> any())

  @type pending_request :: {GenServer.from(), String.t(), reference(), integer()}

  @type t :: %__MODULE__{
          client_info: map(),
          capabilities: map(),
          server_capabilities: map() | nil,
          server_info: map() | nil,
          protocol_version: String.t(),
          request_timeout: integer(),
          transport: map(),
          pending_requests: %{String.t() => pending_request()},
          progress_callbacks: %{String.t() => progress_callback()},
          log_callback: log_callback() | nil
        }

  defstruct [
    :client_info,
    :capabilities,
    :server_capabilities,
    :server_info,
    :protocol_version,
    :request_timeout,
    :transport,
    pending_requests: %{},
    progress_callbacks: %{},
    log_callback: nil
  ]

  @doc """
  Creates a new client state with the given options.

  ## Parameters

    * `opts` - Map containing the initialization options

  ## Options

    * `:client_info` - Information about the client (required)
    * `:capabilities` - Client capabilities to advertise
    * `:protocol_version` - Protocol version to use
    * `:request_timeout` - Default timeout for requests in milliseconds
    * `:transport` - Transport configuration

  ## Examples

      iex> Hermes.Client.State.new(%{
      ...>   client_info: %{"name" => "MyClient", "version" => "1.0.0"},
      ...>   capabilities: %{"resources" => %{}},
      ...>   protocol_version: "2024-11-05",
      ...>   request_timeout: 30000,
      ...>   transport: %{layer: Hermes.Transport.SSE, name: MyTransport}
      ...> })
      %Hermes.Client.State{
        client_info: %{"name" => "MyClient", "version" => "1.0.0"},
        capabilities: %{"resources" => %{}},
        protocol_version: "2024-11-05",
        request_timeout: 30000,
        transport: %{layer: Hermes.Transport.SSE, name: MyTransport}
      }
  """
  @spec new(map()) :: t()
  def new(opts) do
    %__MODULE__{
      client_info: opts.client_info,
      capabilities: opts.capabilities,
      protocol_version: opts.protocol_version,
      request_timeout: opts.request_timeout,
      transport: opts.transport
    }
  end

  @doc """
  Adds a new request to the state and returns the request ID and updated state.

  ## Parameters

    * `state` - The current client state
    * `method` - The method being requested
    * `params` - The parameters for the request
    * `from` - The GenServer.from for the caller

  ## Examples

      iex> {req_id, updated_state} = Hermes.Client.State.add_request(state, "ping", %{}, {pid, ref})
      iex> is_binary(req_id)
      true
      iex> map_size(updated_state.pending_requests) > map_size(state.pending_requests)
      true
  """
  @spec add_request(t(), String.t(), map(), GenServer.from()) :: {String.t(), t()}
  def add_request(state, method, _params, from) do
    request_id = ID.generate_request_id()
    timer_ref = Process.send_after(self(), {:request_timeout, request_id}, state.request_timeout)
    start_time = System.monotonic_time(:millisecond)

    request = {from, method, timer_ref, start_time}
    pending_requests = Map.put(state.pending_requests, request_id, request)

    {request_id, %{state | pending_requests: pending_requests}}
  end

  @doc """
  Gets a request by ID.

  ## Parameters

    * `state` - The current client state
    * `id` - The request ID to retrieve

  ## Examples

      iex> Hermes.Client.State.get_request(state, "req_123")
      {{pid, ref}, "ping", timer_ref, start_time} # or nil if not found
  """
  @spec get_request(t(), String.t()) :: pending_request() | nil
  def get_request(state, id) do
    Map.get(state.pending_requests, id)
  end

  @doc """
  Removes a request and returns its info along with the updated state.

  ## Parameters

    * `state` - The current client state
    * `id` - The request ID to remove

  ## Examples

      iex> {request_info, updated_state} = Hermes.Client.State.remove_request(state, "req_123")
      iex> request_info.method
      "ping"
      iex> request_info.elapsed_ms > 0
      true
  """
  @spec remove_request(t(), String.t()) :: {map() | nil, t()}
  def remove_request(state, id) do
    case Map.pop(state.pending_requests, id) do
      {nil, _} ->
        {nil, state}

      {{from, method, timer_ref, start_time}, requests} ->
        # Cancel the timeout timer
        Process.cancel_timer(timer_ref)
        elapsed = System.monotonic_time(:millisecond) - start_time

        request_info = %{from: from, method: method, elapsed_ms: elapsed}
        {request_info, %{state | pending_requests: requests}}
    end
  end

  @doc """
  Handles a request timeout, cancelling the timer and returning the updated state.

  ## Parameters

    * `state` - The current client state
    * `id` - The request ID that timed out

  ## Examples

      iex> Hermes.Client.State.handle_request_timeout(state, "req_123")
      {%{from: from, method: "ping", elapsed_ms: 30000}, updated_state}
  """
  @spec handle_request_timeout(t(), String.t()) :: {map() | nil, t()}
  def handle_request_timeout(state, id) do
    case Map.pop(state.pending_requests, id) do
      {nil, _} ->
        {nil, state}

      {{from, method, _timer, start_time}, requests} ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        request_info = %{from: from, method: method, elapsed_ms: elapsed}

        {request_info, %{state | pending_requests: requests}}
    end
  end

  @doc """
  Registers a progress callback for a token.

  ## Parameters

    * `state` - The current client state
    * `token` - The progress token to register a callback for
    * `callback` - The callback function to call when progress updates are received

  ## Examples

      iex> updated_state = Hermes.Client.State.register_progress_callback(state, "token123", fn token, progress, total -> IO.inspect({token, progress, total}) end)
      iex> Map.has_key?(updated_state.progress_callbacks, "token123")
      true
  """
  @spec register_progress_callback(t(), String.t(), progress_callback()) :: t()
  def register_progress_callback(state, token, callback) when is_function(callback, 3) do
    progress_callbacks = Map.put(state.progress_callbacks, token, callback)
    %{state | progress_callbacks: progress_callbacks}
  end

  @doc """
  Gets a progress callback for a token.

  ## Parameters

    * `state` - The current client state
    * `token` - The progress token to get the callback for

  ## Examples

      iex> callback = Hermes.Client.State.get_progress_callback(state, "token123")
      iex> is_function(callback, 3)
      true
  """
  @spec get_progress_callback(t(), String.t()) :: progress_callback() | nil
  def get_progress_callback(state, token) do
    Map.get(state.progress_callbacks, token)
  end

  @doc """
  Unregisters a progress callback for a token.

  ## Parameters

    * `state` - The current client state
    * `token` - The progress token to unregister the callback for

  ## Examples

      iex> updated_state = Hermes.Client.State.unregister_progress_callback(state, "token123")
      iex> Map.has_key?(updated_state.progress_callbacks, "token123")
      false
  """
  @spec unregister_progress_callback(t(), String.t()) :: t()
  def unregister_progress_callback(state, token) do
    progress_callbacks = Map.delete(state.progress_callbacks, token)
    %{state | progress_callbacks: progress_callbacks}
  end

  @doc """
  Sets the log callback.

  ## Parameters

    * `state` - The current client state
    * `callback` - The callback function to call when log messages are received

  ## Examples

      iex> updated_state = Hermes.Client.State.set_log_callback(state, fn level, data, logger -> IO.inspect({level, data, logger}) end)
      iex> is_function(updated_state.log_callback, 3)
      true
  """
  @spec set_log_callback(t(), log_callback()) :: t()
  def set_log_callback(state, callback) when is_function(callback, 3) do
    %{state | log_callback: callback}
  end

  @doc """
  Clears the log callback.

  ## Parameters

    * `state` - The current client state

  ## Examples

      iex> updated_state = Hermes.Client.State.clear_log_callback(state)
      iex> is_nil(updated_state.log_callback)
      true
  """
  @spec clear_log_callback(t()) :: t()
  def clear_log_callback(state) do
    %{state | log_callback: nil}
  end

  @doc """
  Gets the log callback.

  ## Parameters

    * `state` - The current client state

  ## Examples

      iex> callback = Hermes.Client.State.get_log_callback(state)
      iex> is_function(callback, 3) or is_nil(callback)
      true
  """
  @spec get_log_callback(t()) :: log_callback() | nil
  def get_log_callback(state) do
    state.log_callback
  end

  @doc """
  Updates server info and capabilities after initialization.

  ## Parameters

    * `state` - The current client state
    * `server_capabilities` - The server capabilities received from initialization
    * `server_info` - The server information received from initialization

  ## Examples

      iex> updated_state = Hermes.Client.State.update_server_info(state, %{"resources" => %{}}, %{"name" => "TestServer"})
      iex> updated_state.server_capabilities
      %{"resources" => %{}}
      iex> updated_state.server_info
      %{"name" => "TestServer"}
  """
  @spec update_server_info(t(), map(), map()) :: t()
  def update_server_info(state, server_capabilities, server_info) do
    %{state | server_capabilities: server_capabilities, server_info: server_info}
  end

  @doc """
  Returns a list of all pending requests.

  ## Parameters

    * `state` - The current client state

  ## Examples

      iex> requests = Hermes.Client.State.list_pending_requests(state)
      iex> length(requests) > 0
      true
      iex> hd(requests).method
      "ping"
  """
  @spec list_pending_requests(t()) :: list(map())
  def list_pending_requests(state) do
    current_time = System.monotonic_time(:millisecond)

    Enum.map(state.pending_requests, fn {id, {_from, method, _timer, start_time}} ->
      elapsed = current_time - start_time
      %{id: id, method: method, elapsed_ms: elapsed}
    end)
  end

  @doc """
  Gets the server capabilities.

  ## Parameters

    * `state` - The current client state

  ## Examples

      iex> Hermes.Client.State.get_server_capabilities(state)
      %{"resources" => %{}, "tools" => %{}}
  """
  @spec get_server_capabilities(t()) :: map() | nil
  def get_server_capabilities(state) do
    state.server_capabilities
  end

  @doc """
  Gets the server info.

  ## Parameters

    * `state` - The current client state

  ## Examples

      iex> Hermes.Client.State.get_server_info(state)
      %{"name" => "TestServer", "version" => "1.0.0"}
  """
  @spec get_server_info(t()) :: map() | nil
  def get_server_info(state) do
    state.server_info
  end

  @doc """
  Merges additional capabilities into the client's capabilities.

  ## Parameters

    * `state` - The current client state
    * `additional_capabilities` - The capabilities to merge

  ## Examples

      iex> updated_state = Hermes.Client.State.merge_capabilities(state, %{"tools" => %{"execute" => true}})
      iex> updated_state.capabilities["tools"]["execute"]
      true
  """
  @spec merge_capabilities(t(), map()) :: t()
  def merge_capabilities(state, additional_capabilities) do
    updated_capabilities = deep_merge(state.capabilities, additional_capabilities)
    %{state | capabilities: updated_capabilities}
  end

  @doc """
  Validates if a method is supported by the server's capabilities.

  ## Parameters

    * `state` - The current client state
    * `method` - The method to validate

  ## Returns

    * `:ok` if the method is supported
    * `{:error, reason}` if the method is not supported

  ## Examples

      iex> Hermes.Client.State.validate_capability(state_with_resources, "resources/list")
      :ok
      
      iex> Hermes.Client.State.validate_capability(state_without_tools, "tools/list")
      {:error, {:capability_not_supported, "tools/list"}}
  """
  @spec validate_capability(t(), String.t()) :: :ok | {:error, term()}
  def validate_capability(%{server_capabilities: nil}, _method) do
    {:error, :server_capabilities_not_set}
  end

  def validate_capability(%{server_capabilities: _}, "ping"), do: :ok
  def validate_capability(%{server_capabilities: _}, "initialize"), do: :ok

  def validate_capability(%{server_capabilities: server_capabilities}, method) do
    capability = String.split(method, "/", parts: 2)

    if valid_capability?(server_capabilities, capability) do
      :ok
    else
      {:error, {:capability_not_supported, method}}
    end
  end

  # Helper functions

  defp valid_capability?(_capabilities, ["ping"]), do: true
  defp valid_capability?(_capabilities, ["initialize"]), do: true

  defp valid_capability?(capabilities, ["resources", sub]) when sub in ~w(subscribe unsubscribe) do
    if resources = Map.get(capabilities, "resources") do
      valid_capability?(resources, [sub, nil])
    end
  end

  defp valid_capability?(%{} = capabilities, [capability, _]) do
    Map.has_key?(capabilities, capability)
  end

  defp deep_merge(map1, map2) do
    Map.merge(map1, map2, fn
      _, v1, v2 when is_map(v1) and is_map(v2) -> deep_merge(v1, v2)
      _, _, v2 -> v2
    end)
  end
end
