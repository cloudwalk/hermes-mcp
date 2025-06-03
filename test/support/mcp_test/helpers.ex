defmodule MCPTest.Helpers do
  @moduledoc """
  Helper functions for MCP request/response testing.

  Provides high-level functions that abstract away the boilerplate
  of MCP protocol testing, including request/response cycles,
  async operations, and message handling.
  """

  import MCPTest.Builders

  alias Hermes.Client.State
  alias Hermes.MCP.Message

  @default_timeout 1000

  @doc """
  Performs a complete MCP request/response cycle.

  This function handles the full flow:
  1. Sets up mock expectation
  2. Sends request asynchronously
  3. Extracts request ID
  4. Sends response
  5. Returns the result

  ## Examples

      response_data = %{"resources" => []}
      result = request_response_cycle(client, "resources/list", %{}, resources_list_response(response_data))
      
      # With custom timeout
      result = request_response_cycle(client, "ping", %{}, ping_response(), timeout: 5000)
  """
  def request_response_cycle(client, method, params, response_builder, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout

    task = start_async_request(client, method, params)

    Process.sleep(10)

    request_id = get_request_id(client, method)
    response = build_response_with_id(response_builder, request_id)
    send_response(client, response)

    Task.await(task, timeout)
  end

  @doc """
  Shorthand for request/response cycle with automatic response building.

  ## Examples

      resources = [%{"uri" => "test://res", "name" => "Test"}]
      result = request_with_resources_response(client, resources)
      
      tools = [%{"name" => "my_tool"}]
      result = request_with_tools_response(client, tools)
  """
  def request_with_resources_response(client, resources \\ [], opts \\ []) do
    request_response_cycle(
      client,
      "resources/list",
      [],
      fn request_id ->
        resources_list_response(request_id, resources)
      end,
      opts
    )
  end

  def request_with_tools_response(client, tools \\ [], opts \\ []) do
    request_response_cycle(
      client,
      "tools/list",
      [],
      fn request_id ->
        tools_list_response(request_id, tools)
      end,
      opts
    )
  end

  def request_with_prompts_response(client, prompts \\ [], opts \\ []) do
    request_response_cycle(
      client,
      "prompts/list",
      [],
      fn request_id ->
        prompts_list_response(request_id, prompts)
      end,
      opts
    )
  end

  @doc """
  Sends a request and returns the request ID for manual response handling.

  Useful when you need more control over the response timing or content.

  ## Examples

      request_id = send_request(client, "tools/call", %{"name" => "my_tool"})
      # ... do other setup ...
      send_response(client, tools_call_response(request_id, [...]))
  """
  def send_request(client, method, params \\ []) do
    task = start_async_request(client, method, params)
    Process.put(:current_request_task, task)

    Process.sleep(10)

    get_request_id(client, method)
  end

  @doc """
  Awaits the result of the current request.

  Use this after send_request/3 and send_response/2.
  """
  def await_request_result(timeout \\ @default_timeout) do
    case Process.get(:current_request_task) do
      nil ->
        {:error, :no_pending_request}

      task ->
        result = Task.await(task, timeout)
        Process.delete(:current_request_task)
        result
    end
  end

  @doc """
  Sends a response message to the client.

  Handles encoding and proper message delivery using Hermes.MCP.Message.
  """
  def send_response(client, response) do
    {:ok, encoded} = Message.encode_response(response, response["id"])
    GenServer.cast(client, {:response, encoded})
  end

  @doc """
  Sends a notification message to the client using Hermes.MCP.Message.
  """
  def send_notification(client, notification) do
    {:ok, encoded} = Message.encode_notification(notification)
    GenServer.cast(client, {:response, encoded})
  end

  @doc """
  Sends an error response to the client using Hermes.MCP.Message.
  """
  def send_error(client, error) do
    {:ok, encoded} = Message.encode_error(error, error["id"])
    GenServer.cast(client, {:response, encoded})
  end

  @doc """
  Sends an initialize request to the client.

  This triggers the client to send an initialize request.
  """
  def send_initialize_request(client) do
    GenServer.cast(client, :initialize)
  end

  @doc """
  Performs complete client initialization.

  Sends initialize request, waits for it, responds with server capabilities,
  and sends initialized notification.
  """
  def complete_initialization(client, opts \\ []) do
    send_initialize_request(client)

    request_id = get_request_id(client, "initialize")
    response = init_response(request_id, opts)
    send_response(client, response)

    notification = initialized_notification()
    send_notification(client, notification)

    :ok
  end

  @doc """
  Extracts the request ID for a specific method from client state.

  This is useful for getting the ID to include in response messages.
  """
  def get_request_id(client, expected_method) do
    state = :sys.get_state(client)
    pending_requests = State.list_pending_requests(state)

    Enum.find_value(pending_requests, nil, fn
      %{method: ^expected_method, id: id} -> id
      _ -> nil
    end)
  end

  @doc """
  Gets all pending request IDs from the client.
  """
  def get_all_request_ids(client) do
    state = :sys.get_state(client)
    pending_requests = State.list_pending_requests(state)

    Enum.map(pending_requests, & &1.id)
  end

  @doc """
  Sends a progress notification for a specific request.
  """
  def send_progress(client, request_id, progress \\ 50, total \\ 100) do
    notification = progress_notification(request_id, progress, total)
    send_notification(client, notification)
  end

  @doc """
  Sends a cancellation notification for a specific request.
  """
  def send_cancellation(client, request_id, reason \\ "test cancellation") do
    notification = cancelled_notification(request_id, reason)
    send_notification(client, notification)
  end

  @doc """
  Sends a log notification.
  """
  def send_log(client, level \\ "info", message \\ "test log", logger \\ "test") do
    notification = log_notification(level, message, logger)
    send_notification(client, notification)
  end

  @doc """
  Sends an error response instead of a successful response.

  ## Examples

      request_id = send_request(client, "invalid/method", %{})
      send_error_response(client, request_id, -32601, "Method not found")
      assert {:error, _} = await_request_result()
  """
  def send_error_response(client, request_id, code, message, data \\ %{}) do
    error = build_error(request_id, code, message, data)
    send_error(client, error)
  end

  @doc """
  Simulates a server error during request processing.
  """
  def simulate_server_error(client, request_id, opts \\ []) do
    code = opts[:code] || -32_603
    message = opts[:message] || "Internal error"
    data = opts[:data] || %{}

    send_error_response(client, request_id, code, message, data)
  end

  defp start_async_request(client, method, params) do
    Task.async(fn -> execute_client_method(client, method, params) end)
  end

  defp execute_client_method(_client, "initialize", _params), do: :ok
  defp execute_client_method(client, "ping", _params), do: Hermes.Client.ping(client)
  defp execute_client_method(client, "resources/list", params), do: Hermes.Client.list_resources(client, params)
  defp execute_client_method(client, "tools/list", params), do: Hermes.Client.list_tools(client, params)
  defp execute_client_method(client, "prompts/list", params), do: Hermes.Client.list_prompts(client, params)

  defp execute_client_method(client, "resources/read", params) do
    uri = Keyword.get(params, :uri, "test://uri")
    Hermes.Client.read_resource(client, uri)
  end

  defp execute_client_method(client, "tools/call", params) do
    name = Keyword.get(params, :name, "test_tool")
    arguments = Keyword.get(params, :arguments, %{})
    Hermes.Client.call_tool(client, name, arguments)
  end

  defp execute_client_method(client, "prompts/get", params) do
    name = Keyword.get(params, :name, "test_prompt")
    arguments = Keyword.get(params, :arguments, %{})
    Hermes.Client.get_prompt(client, name, arguments)
  end

  defp execute_client_method(client, "completion/complete", params) do
    ref = Keyword.get(params, :ref, %{})
    argument = Keyword.get(params, :argument, %{})
    Hermes.Client.complete(client, ref, argument)
  end

  defp execute_client_method(_client, method, _params) do
    {:error, {:unsupported_method, method}}
  end

  defp build_response_with_id(response_builder, request_id) when is_function(response_builder) do
    response_builder.(request_id)
  end

  defp build_response_with_id(response, _request_id) when is_map(response) do
    response
  end
end
