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

  alias Hermes.Message
  require Hermes.Message

  require Logger

  @default_protocol_version "2024-11-05"
  @default_timeout :timer.seconds(30)

  @type option ::
          {:name, atom}
          | {:transport, module}
          | {:client_info, map}
          | {:capabilities, map}
          | {:protocol_version, String.t()}
          | {:request_timeout, integer}
          | Supervisor.init_option()

  defschema :parse_options, [
    {:name, {:atom, {:default, __MODULE__}}},
    {:transport, {:required, {:either, {:pid, :atom}}}},
    {:client_info, {:required, :map}},
    {:capabilities, {:map, {:default, %{"resources" => %{}, "tools" => %{}}}}},
    {:protocol_version, {:string, {:default, @default_protocol_version}}},
    {:request_timeout, {:integer, {:default, @default_timeout}}}
  ]

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
  def ping(client, timeout \\ nil) do
    GenServer.call(client, {:request, "ping", %{}}, timeout || @default_timeout)
  end

  @doc """
  Lists available resources from the server.

  ## Options

    * `:cursor` - Pagination cursor for continuing a previous request
    * `:timeout` - Request timeout in milliseconds
  """
  def list_resources(client, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    timeout = Keyword.get(opts, :timeout)

    params = if cursor, do: %{"cursor" => cursor}, else: %{}
    GenServer.call(client, {:request, "resources/list", params}, timeout || @default_timeout)
  end

  @doc """
  Reads a specific resource from the server.

  ## Options

    * `:timeout` - Request timeout in milliseconds
  """
  def read_resource(client, uri, opts \\ []) do
    timeout = Keyword.get(opts, :timeout)

    params = %{"uri" => uri}
    GenServer.call(client, {:request, "resources/read", params}, timeout || @default_timeout)
  end

  @doc """
  Lists available prompts from the server.

  ## Options

    * `:cursor` - Pagination cursor for continuing a previous request
    * `:timeout` - Request timeout in milliseconds
  """
  def list_prompts(client, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    timeout = Keyword.get(opts, :timeout)

    params = if cursor, do: %{"cursor" => cursor}, else: %{}
    GenServer.call(client, {:request, "prompts/list", params}, timeout || @default_timeout)
  end

  @doc """
  Gets a specific prompt from the server.

  ## Options

    * `:timeout` - Request timeout in milliseconds
  """
  def get_prompt(client, name, arguments \\ nil, opts \\ []) do
    timeout = Keyword.get(opts, :timeout)

    params = %{"name" => name}
    params = if arguments, do: Map.put(params, "arguments", arguments), else: params

    GenServer.call(client, {:request, "prompts/get", params}, timeout || @default_timeout)
  end

  @doc """
  Lists available tools from the server.

  ## Options

    * `:cursor` - Pagination cursor for continuing a previous request
    * `:timeout` - Request timeout in milliseconds
  """
  def list_tools(client, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    timeout = Keyword.get(opts, :timeout)

    params = if cursor, do: %{"cursor" => cursor}, else: %{}
    GenServer.call(client, {:request, "tools/list", params}, timeout || @default_timeout)
  end

  @doc """
  Calls a tool on the server.

  ## Options

    * `:timeout` - Request timeout in milliseconds
  """
  def call_tool(client, name, arguments \\ nil, opts \\ []) do
    timeout = Keyword.get(opts, :timeout)

    params = %{"name" => name}
    params = if arguments, do: Map.put(params, "arguments", arguments), else: params

    GenServer.call(client, {:request, "tools/call", params}, timeout || @default_timeout)
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
  Closes the client connection and terminates the process.
  """
  def close(client) do
    GenServer.cast(client, :close)
  end

  # GenServer Callbacks

  @impl true
  def init(%{} = opts) do
    state = %{
      transport: opts.transport,
      client_info: opts.client_info,
      capabilities: opts.capabilities,
      server_capabilities: nil,
      server_info: nil,
      protocol_version: opts.protocol_version,
      request_timeout: opts.request_timeout,
      pending_requests: Map.new()
    }

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

  def handle_call(:close, _from, %{transport: transport, pending_requests: pending} = state) do
    if map_size(pending) > 0 do
      Logger.warning("Closing client with #{map_size(pending)} pending requests")
    end

    for {request_id, _} <- pending do
      send_notification(state, "notifications/cancelled", %{
        "requestId" => request_id,
        "reason" => "client closed"
      })
    end

    transport.close()

    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:initialize, state) do
    Logger.info("Making initial client <> server handshake")

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
        Logger.error("Received error response: #{inspect(error)}")
        {:noreply, handle_error(error, error["id"], state)}

      {:ok, [response]} when Message.is_response(response) ->
        Logger.info("Received response: #{response["id"]}")
        {:noreply, handle_response(response, response["id"], state)}

      {:ok, [notification]} when Message.is_notification(notification) ->
        Logger.debug("Received notification: #{notification["method"]}")
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to decode response: #{inspect(reason)}")
        {:noreply, state}
    end
  rescue
    e ->
      err = Exception.format(:error, e, __STACKTRACE__)
      Logger.error("Failed to handle response: #{err}")
      {:noreply, state}
  end

  # Response handling

  defp handle_error(%{"error" => error, "id" => id}, id, state) do
    {{from, _method}, pending} = Map.pop(state.pending_requests, id)

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

    Logger.info("Client initialized successfully, notifing server")

    # we need to confirm to the server the handshake
    :ok = send_notification(state, "notifications/initialized")

    state
  end

  defp handle_response(%{"id" => id, "result" => result}, id, state) do
    {{from, method}, pending} = Map.pop(state.pending_requests, id)

    # unblocks original caller
    cond do
      method == "ping" -> GenServer.reply(from, :pong)
      result["isError"] -> GenServer.reply(from, {:error, result})
      true -> GenServer.reply(from, {:ok, result})
    end

    %{state | pending_requests: pending}
  end

  defp handle_response(%{"id" => _} = response, _, state) do
    Logger.warning("Received response for unknown request ID: #{response["id"]}")
    state
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

  defp valid_capability?(capabilities, ["resources", sub])
       when sub in ~w(subscribe unsubscribe) do
    if resources = Map.get(capabilities, "resources") do
      valid_capability?(resources, [sub, nil])
    end
  end

  defp valid_capability?(%{} = capabilities, [capability, _]) do
    Map.has_key?(capabilities, capability)
  end

  defp generate_request_id do
    binary = <<
      System.system_time(:nanosecond)::64,
      :erlang.phash2({node(), self()}, 16_777_216)::24,
      :erlang.unique_integer()::32
    >>

    Base.url_encode64(binary)
  end

  defp encode_request(method, params, request_id) do
    Message.encode_request(%{"method" => method, "params" => params}, request_id)
  end

  defp encode_notification(method, params) do
    Message.encode_notification(%{"method" => method, "params" => params})
  end

  defp send_to_transport(transport, data) do
    with {:error, reason} <- transport.send_message(data) do
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
