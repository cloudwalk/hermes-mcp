defmodule Hermes.Client.State do
  @moduledoc false

  alias Hermes.Client.Base
  alias Hermes.Client.Operation
  alias Hermes.Client.Request
  alias Hermes.MCP.Error
  alias Hermes.MCP.ID
  alias Hermes.Telemetry

  @type t :: %__MODULE__{
          client_info: map(),
          capabilities: map(),
          server_capabilities: map() | nil,
          server_info: map() | nil,
          protocol_version: String.t(),
          transport: map(),
          pending_requests: %{String.t() => Request.t()},
          progress_callbacks: %{String.t() => Base.progress_callback()},
          log_callback: Base.log_callback() | nil,
          sampling_callback: (map() -> {:ok, map()} | {:error, String.t()}) | nil,
          # Use a map with URI as key for faster access
          roots: %{String.t() => Base.root()}
        }

  defstruct [
    :client_info,
    :capabilities,
    :server_capabilities,
    :server_info,
    :protocol_version,
    :transport,
    pending_requests: %{},
    progress_callbacks: %{},
    log_callback: nil,
    sampling_callback: nil,
    roots: %{}
  ]

  @spec new(map()) :: t()
  def new(opts) do
    %__MODULE__{
      client_info: opts.client_info,
      capabilities: opts.capabilities,
      protocol_version: opts.protocol_version,
      transport: opts.transport
    }
  end

  @spec add_request_from_operation(t(), Operation.t(), GenServer.from()) ::
          {String.t(), t()}
  def add_request_from_operation(state, %Operation{} = operation, from) do
    state = register_progress_callback_from_opts(state, operation.progress_opts)

    request_id = ID.generate_request_id()

    timer_ref =
      Process.send_after(self(), {:request_timeout, request_id}, operation.timeout)

    request =
      Request.new(%{
        id: request_id,
        method: operation.method,
        from: from,
        timer_ref: timer_ref,
        params: operation.params
      })

    pending_requests = Map.put(state.pending_requests, request_id, request)

    {request_id, %{state | pending_requests: pending_requests}}
  end

  @doc """
  Helper function to add progress token to params if provided.
  """
  @spec add_progress_token_to_params(map(), keyword() | nil) :: map()
  def add_progress_token_to_params(params, nil), do: params
  def add_progress_token_to_params(params, []), do: params

  def add_progress_token_to_params(params, progress_opts) when is_list(progress_opts) do
    token = Keyword.get(progress_opts, :token)

    if is_binary(token) or is_integer(token) do
      Map.put(params, "_meta", %{"progressToken" => token})
    else
      params
    end
  end

  @doc """
  Helper function to register progress callback from options.
  """
  @spec register_progress_callback_from_opts(t(), keyword() | nil) :: t()
  def register_progress_callback_from_opts(state, progress_opts) do
    with {:ok, opts} when not is_nil(opts) <- {:ok, progress_opts},
         {:ok, callback} when is_function(callback, 3) <-
           {:ok, Keyword.get(opts, :callback)},
         {:ok, token} when not is_nil(token) <- {:ok, Keyword.get(opts, :token)} do
      register_progress_callback(state, token, callback)
    else
      _ -> state
    end
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
  @spec get_request(t(), String.t()) :: Request.t() | nil
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
  @spec remove_request(t(), String.t()) :: {Request.t() | nil, t()}
  def remove_request(state, id) do
    case Map.pop(state.pending_requests, id) do
      {nil, _} ->
        {nil, state}

      {request, updated_requests} ->
        # Cancel the timeout timer
        Process.cancel_timer(request.timer_ref)

        {request, %{state | pending_requests: updated_requests}}
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
  @spec handle_request_timeout(t(), String.t()) :: {Request.t() | nil, t()}
  def handle_request_timeout(state, id) do
    case Map.pop(state.pending_requests, id) do
      {nil, _} ->
        {nil, state}

      {request, updated_requests} ->
        {request, %{state | pending_requests: updated_requests}}
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
  @spec register_progress_callback(t(), String.t(), Base.progress_callback()) :: t()
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
  @spec get_progress_callback(t(), String.t()) :: Base.progress_callback() | nil
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
  @spec set_log_callback(t(), Base.log_callback()) :: t()
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
  @spec get_log_callback(t()) :: Base.log_callback() | nil
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
  @spec list_pending_requests(t()) :: list(Request.t())
  def list_pending_requests(state) do
    Map.values(state.pending_requests)
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
    * `{:error, %Hermes.MCP.Error{}}` if the method is not supported

  ## Examples

      iex> Hermes.Client.State.validate_capability(state_with_resources, "resources/list")
      :ok
      
      iex> {:error, error} = Hermes.Client.State.validate_capability(state_without_tools, "tools/list")
      iex> error.reason
      :method_not_found
  """
  @spec validate_capability(t(), String.t()) :: :ok | {:error, Error.t()}
  def validate_capability(%{server_capabilities: nil}, _method) do
    {:error, Error.protocol(:internal_error, %{message: "Server capabilities not set"})}
  end

  def validate_capability(%{server_capabilities: _}, "ping"), do: :ok
  def validate_capability(%{server_capabilities: _}, "initialize"), do: :ok

  def validate_capability(%{server_capabilities: server_capabilities}, method) do
    capability = String.split(method, "/", parts: 2)

    if valid_capability?(server_capabilities, capability) do
      :ok
    else
      {:error, Error.protocol(:method_not_found, %{method: method})}
    end
  end

  @doc """
  Adds a root directory to the state.

  ## Parameters

    * `state` - The current client state
    * `uri` - The URI of the root directory (must start with "file://")
    * `name` - Optional human-readable name for display purposes

  ## Examples

      iex> updated_state = Hermes.Client.State.add_root(state, "file:///home/user/project", "My Project")
      iex> updated_state.roots
      [%{uri: "file:///home/user/project", name: "My Project"}]
  """
  @spec add_root(t(), String.t(), String.t() | nil) :: t()
  def add_root(state, uri, name \\ nil) when is_binary(uri) do
    if Map.has_key?(state.roots, uri) do
      state
    else
      root = %{uri: uri, name: name}

      Telemetry.execute(
        Telemetry.event_client_roots(),
        %{system_time: System.system_time()},
        %{action: :add, uri: uri}
      )

      %{state | roots: Map.put(state.roots, uri, root)}
    end
  end

  @doc """
  Removes a root directory from the state.

  ## Parameters

    * `state` - The current client state
    * `uri` - The URI of the root directory to remove

  ## Examples

      iex> updated_state = Hermes.Client.State.remove_root(state, "file:///home/user/project")
      iex> updated_state.roots
      []
  """
  @spec remove_root(t(), String.t()) :: t()
  def remove_root(state, uri) when is_binary(uri) do
    if Map.has_key?(state.roots, uri) do
      Telemetry.execute(
        Telemetry.event_client_roots(),
        %{system_time: System.system_time()},
        %{action: :remove, uri: uri}
      )

      %{state | roots: Map.delete(state.roots, uri)}
    else
      state
    end
  end

  @doc """
  Gets a root directory by its URI.

  ## Parameters

    * `state` - The current client state
    * `uri` - The URI of the root directory to get

  ## Examples

      iex> Hermes.Client.State.get_root_by_uri(state, "file:///home/user/project")
      %{uri: "file:///home/user/project", name: "My Project"}
  """
  @spec get_root_by_uri(t(), String.t()) :: Base.root() | nil
  def get_root_by_uri(state, uri) when is_binary(uri) do
    Map.get(state.roots, uri)
  end

  @doc """
  Lists all root directories.

  ## Parameters

    * `state` - The current client state

  ## Examples

      iex> Hermes.Client.State.list_roots(state)
      [%{uri: "file:///home/user/project", name: "My Project"}]
  """
  @spec list_roots(t()) :: [Base.root()]
  def list_roots(state) do
    Map.values(state.roots)
  end

  @doc """
  Clears all root directories.

  ## Parameters

    * `state` - The current client state

  ## Examples

      iex> updated_state = Hermes.Client.State.clear_roots(state)
      iex> updated_state.roots
      []
  """
  @spec clear_roots(t()) :: t()
  def clear_roots(state) do
    if map_size(state.roots) > 0 do
      Telemetry.execute(
        Telemetry.event_client_roots(),
        %{system_time: System.system_time()},
        %{action: :clear, count: map_size(state.roots)}
      )

      %{state | roots: %{}}
    else
      state
    end
  end

  @doc """
  Sets the sampling callback function.

  ## Parameters

    * `state` - The current client state
    * `callback` - The callback function to handle sampling requests

  ## Examples

      iex> callback = fn params -> {:ok, %{role: "assistant", content: %{type: "text", text: "Hello"}}} end
      iex> updated_state = Hermes.Client.State.set_sampling_callback(state, callback)
      iex> is_function(updated_state.sampling_callback, 1)
      true
  """
  @spec set_sampling_callback(t(), (map() -> {:ok, map()} | {:error, String.t()})) ::
          t()
  def set_sampling_callback(state, callback) when is_function(callback, 1) do
    %{state | sampling_callback: callback}
  end

  @doc """
  Gets the sampling callback function.

  ## Parameters

    * `state` - The current client state

  ## Examples

      iex> Hermes.Client.State.get_sampling_callback(state)
      nil
  """
  @spec get_sampling_callback(t()) ::
          (map() -> {:ok, map()} | {:error, String.t()}) | nil
  def get_sampling_callback(state) do
    state.sampling_callback
  end

  @doc """
  Clears the sampling callback function.

  ## Parameters

    * `state` - The current client state

  ## Examples

      iex> updated_state = Hermes.Client.State.clear_sampling_callback(state)
      iex> updated_state.sampling_callback
      nil
  """
  @spec clear_sampling_callback(t()) :: t()
  def clear_sampling_callback(state) do
    %{state | sampling_callback: nil}
  end

  # Helper functions

  defp valid_capability?(_capabilities, ["ping"]), do: true
  defp valid_capability?(_capabilities, ["initialize"]), do: true
  defp valid_capability?(_capabilities, ["roots", "list"]), do: true

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
