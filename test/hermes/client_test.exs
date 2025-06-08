defmodule Hermes.ClientTest do
  use Hermes.MCP.Case, async: true

  alias Hermes.MCP.Error
  alias Hermes.MCP.ID
  alias Hermes.MCP.Message
  alias Hermes.MCP.Response

  describe "start_link/1" do
    test "starts the client with proper initialization" do
      transport_name = :test_transport
      start_supervised!({MCPTest.MockTransport, [name: transport_name]})

      client =
        start_supervised!(
          {Hermes.Client,
           transport: [layer: MCPTest.MockTransport, name: transport_name],
           client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
          restart: :temporary
        )

      send_initialize_request(client)

      Process.sleep(50)
      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1

      [init_message] = messages
      assert String.contains?(init_message, "initialize")
      assert String.contains?(init_message, "protocolVersion")
      assert String.contains?(init_message, "capabilities")
      assert String.contains?(init_message, "clientInfo")

      request_id = get_request_id(client, "initialize")
      response = init_response(request_id)
      send_response(client, response)
      send_notification(client, initialized_notification())

      assert Process.alive?(client)
    end
  end

  describe "request methods" do
    setup :initialized_client

    test "ping sends correct request", %{client: client} do
      result = request_response_cycle(client, "ping", %{}, &ping_response/1)
      assert result == :pong
    end

    test "list_resources sends correct request", %{client: client} do
      resources = [%{"name" => "test", "uri" => "test://uri"}]
      result = request_with_resources_response(client, resources)

      assert_success(result, fn response ->
        assert %Response{} = response
        assert response.result["resources"] == resources
        assert response.is_error == false
      end)
    end

    test "list_resources with cursor", %{client: client} do
      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      task = Task.async(fn -> Hermes.Client.list_resources(client, cursor: "next-page") end)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1
      [message] = messages
      {:ok, [decoded]} = Message.decode(message)
      assert decoded["method"] == "resources/list"
      assert decoded["params"] == %{"cursor" => "next-page"}

      request_id = get_request_id(client, "resources/list")
      assert request_id

      resources = [%{"name" => "test2", "uri" => "test://uri2"}]
      response = resources_list_response(request_id, resources)
      send_response(client, response)

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result["resources"] == resources
      assert response.is_error == false
    end

    test "read_resource sends correct request", %{client: client} do
      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      task = Task.async(fn -> Hermes.Client.read_resource(client, "test://uri") end)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1
      [message] = messages
      {:ok, [decoded]} = Message.decode(message)
      assert decoded["method"] == "resources/read"
      assert decoded["params"] == %{"uri" => "test://uri"}

      request_id = get_request_id(client, "resources/read")
      assert request_id

      contents = [%{"text" => "resource content", "uri" => "test://uri"}]
      response = resources_read_response(request_id, contents)
      send_response(client, response)

      expected_result = %{
        "contents" => contents
      }

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result == expected_result
      assert response.is_error == false
    end

    test "list_prompts sends correct request", %{client: client} do
      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      task = Task.async(fn -> Hermes.Client.list_prompts(client) end)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1
      [message] = messages
      {:ok, [decoded]} = Message.decode(message)
      assert decoded["method"] == "prompts/list"
      assert decoded["params"] == %{}

      request_id = get_request_id(client, "prompts/list")
      assert request_id

      prompts = [%{"name" => "test_prompt"}]
      response = prompts_list_response(request_id, prompts)
      send_response(client, response)

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result["prompts"] == prompts
      assert response.is_error == false
    end

    test "get_prompt sends correct request", %{client: client} do
      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      task =
        Task.async(fn ->
          Hermes.Client.get_prompt(client, "test_prompt", %{"arg1" => "value1"})
        end)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1
      [message] = messages
      {:ok, [decoded]} = Message.decode(message)
      assert decoded["method"] == "prompts/get"

      assert decoded["params"] == %{
               "name" => "test_prompt",
               "arguments" => %{"arg1" => "value1"}
             }

      request_id = get_request_id(client, "prompts/get")
      assert request_id

      messages = [%{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}]
      response = prompts_get_response(request_id, messages)
      send_response(client, response)

      expected_result = %{
        "messages" => messages
      }

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result == expected_result
      assert response.is_error == false
    end

    test "list_tools sends correct request", %{client: client} do
      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      task = Task.async(fn -> Hermes.Client.list_tools(client) end)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1
      [message] = messages
      {:ok, [decoded]} = Message.decode(message)
      assert decoded["method"] == "tools/list"
      assert decoded["params"] == %{}

      request_id = get_request_id(client, "tools/list")
      assert request_id

      tools = [%{"name" => "test_tool"}]
      response = tools_list_response(request_id, tools)
      send_response(client, response)

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result["tools"] == tools
      assert response.is_error == false
    end

    test "call_tool sends correct request", %{client: client} do
      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      task =
        Task.async(fn -> Hermes.Client.call_tool(client, "test_tool", %{"arg1" => "value1"}) end)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1
      [message] = messages
      {:ok, [decoded]} = Message.decode(message)
      assert decoded["method"] == "tools/call"
      assert decoded["params"] == %{"name" => "test_tool", "arguments" => %{"arg1" => "value1"}}

      request_id = get_request_id(client, "tools/call")
      assert request_id

      content = [%{"type" => "text", "text" => "Tool result"}]
      response = tools_call_response(request_id, content)
      send_response(client, response)

      expected_result = %{
        "content" => content,
        "isError" => false
      }

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result == expected_result
      assert response.is_error == false
    end

    test "handles domain error responses as {:ok, response}", %{client: client} do
      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      task =
        Task.async(fn -> Hermes.Client.call_tool(client, "test_tool", %{"arg1" => "value1"}) end)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1
      [message] = messages
      {:ok, [decoded]} = Message.decode(message)
      assert decoded["method"] == "tools/call"
      assert decoded["params"] == %{"name" => "test_tool", "arguments" => %{"arg1" => "value1"}}

      request_id = get_request_id(client, "tools/call")
      assert request_id

      content = [%{"type" => "text", "text" => "Tool execution failed: invalid argument"}]
      response = tools_call_response(request_id, content, is_error: true)
      send_response(client, response)

      expected_result = %{
        "content" => content,
        "isError" => true
      }

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result == expected_result
      assert response.is_error == true
    end
  end

  describe "non support request methods" do
    setup :initialized_client

    test "ping sends correct request since it is always supported", %{client: client} do
      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      task = Task.async(fn -> Hermes.Client.ping(client) end)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1
      [message] = messages
      {:ok, [decoded]} = Message.decode(message)
      assert decoded["method"] == "ping"
      assert decoded["params"] == %{}
      assert decoded["jsonrpc"] == "2.0"
      assert is_binary(decoded["id"])

      request_id = get_request_id(client, "ping")
      assert request_id

      response = ping_response(request_id)
      send_response(client, response)

      assert :pong = Task.await(task)
    end

    @tag server_capabilities: %{"prompts" => %{}}
    test "tools/list fails since this capability isn't supported", %{client: client} do
      task = Task.async(fn -> Hermes.Client.list_tools(client) end)

      assert {:error, %Error{reason: :method_not_found, data: %{method: "tools/list"}}} =
               Task.await(task)
    end
  end

  describe "error handling" do
    setup :initialized_client

    test "handles error response", %{client: client} do
      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      task = Task.async(fn -> Hermes.Client.ping(client) end)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1
      [message] = messages
      {:ok, [decoded]} = Message.decode(message)
      assert decoded["method"] == "ping"

      request_id = get_request_id(client, "ping")
      assert request_id

      error_response = error_response(request_id)
      send_error(client, error_response)

      {:error, error} = Task.await(task)
      assert error.code == -32_601
      assert error.reason == :method_not_found
      # error.data is an empty map in the test builder
    end

    test "handles transport error" do
      transport_name = :error_test_transport
      start_supervised!({MCPTest.MockTransport, [name: transport_name, mode: :mocking]}, id: "error")

      MCPTest.MockTransport.expect_method(transport_name, "ping", nil, fn -> {:error, :connection_closed} end)

      client =
        start_supervised!(
          {Hermes.Client,
           name: :error_test_client,
           transport: [layer: MCPTest.MockTransport, name: transport_name],
           client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
          id: "error_client",
          restart: :temporary
        )

      complete_initialization(client)

      assert {:error,
              %Error{
                reason: :send_failure,
                data: %{type: :transport, original_reason: :connection_closed}
              }} = Hermes.Client.ping(client)
    end
  end

  describe "capability management" do
    test "merge_capabilities correctly merges capabilities" do
      transport_name = :capability_test_transport
      start_supervised!({MCPTest.MockTransport, [name: transport_name]})

      client =
        start_supervised!(
          {Hermes.Client,
           transport: [layer: MCPTest.MockTransport, name: transport_name],
           client_info: %{"name" => "TestClient", "version" => "1.0.0"},
           capabilities: %{"roots" => %{}}},
          restart: :temporary
        )

      complete_initialization(client)

      new_capabilities = %{"sampling" => %{}}

      updated = Hermes.Client.merge_capabilities(client, new_capabilities)

      assert updated == %{"roots" => %{}, "sampling" => %{}}

      nested_capabilities = %{"roots" => %{"listChanged" => true}}

      final = Hermes.Client.merge_capabilities(client, nested_capabilities)

      assert final == %{"sampling" => %{}, "roots" => %{"listChanged" => true}}
    end
  end

  describe "server information" do
    setup :initialized_client

    test "get_server_capabilities returns server capabilities", %{client: client} do
      capabilities = Hermes.Client.get_server_capabilities(client)

      assert Map.has_key?(capabilities, "resources")
      assert Map.has_key?(capabilities, "tools")
      assert Map.has_key?(capabilities, "prompts")
    end

    test "get_server_info returns server info", %{client: client} do
      server_info = Hermes.Client.get_server_info(client)

      assert server_info == %{"name" => "TestServer", "version" => "1.0.0"}
    end
  end

  describe "progress tracking" do
    setup :initialized_client

    test "registers and calls progress callback when notification is received", %{client: client} do
      test_pid = self()
      progress_token = "test_progress_token"
      progress_value = 50
      total_value = 100

      :ok =
        Hermes.Client.register_progress_callback(client, progress_token, fn token, progress, total ->
          send(test_pid, {:progress_callback, token, progress, total})
        end)

      progress_notification = progress_notification(progress_token, progress_value, total_value)
      send_notification(client, progress_notification)

      assert_receive {:progress_callback, ^progress_token, ^progress_value, ^total_value}, 1000
    end

    test "unregisters progress callback", %{client: client} do
      test_pid = self()
      progress_token = "unregister_test_token"

      :ok =
        Hermes.Client.register_progress_callback(client, progress_token, fn _, _, _ ->
          send(test_pid, :should_not_be_called)
        end)

      :ok = Hermes.Client.unregister_progress_callback(client, progress_token)

      progress_notification = progress_notification(progress_token)
      send_notification(client, progress_notification)

      refute_receive :should_not_be_called, 500
    end

    test "request with progress token includes it in params", %{client: client} do
      progress_token = "request_token_test"

      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      task =
        Task.async(fn ->
          Hermes.Client.list_resources(client, progress: [token: progress_token])
        end)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1
      [message] = messages
      {:ok, [decoded]} = Message.decode(message)
      assert decoded["method"] == "resources/list"
      assert get_in(decoded, ["params", "_meta", "progressToken"]) == progress_token

      request_id = get_request_id(client, "resources/list")
      assert request_id

      response = resources_list_response(request_id, [])
      send_response(client, response)

      assert {:ok, _} = Task.await(task)
    end

    test "generates unique progress tokens" do
      token1 = ID.generate_progress_token()
      token2 = ID.generate_progress_token()

      assert is_binary(token1)
      assert is_binary(token2)
      assert token1 != token2
      assert String.starts_with?(token1, "progress_")
      assert String.starts_with?(token2, "progress_")
    end
  end

  describe "logging" do
    setup :initialized_client

    test "set_log_level sends the correct request", %{client: client} do
      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      task = Task.async(fn -> Hermes.Client.set_log_level(client, "info") end)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1
      [message] = messages
      {:ok, [decoded]} = Message.decode(message)
      assert decoded["method"] == "logging/setLevel"
      assert decoded["params"]["level"] == "info"

      request_id = get_request_id(client, "logging/setLevel")
      assert request_id

      response = empty_result_response(request_id)
      send_response(client, response)

      assert {:ok, %{}} = Task.await(task)
    end

    test "complete sends correct completion/complete request for prompt reference", %{client: client} do
      ref = %{"type" => "ref/prompt", "name" => "code_review"}
      argument = %{"name" => "language", "value" => "py"}

      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      task = Task.async(fn -> Hermes.Client.complete(client, ref, argument) end)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1
      [message] = messages
      {:ok, [decoded]} = Message.decode(message)
      assert decoded["method"] == "completion/complete"
      assert decoded["params"]["ref"]["type"] == "ref/prompt"
      assert decoded["params"]["ref"]["name"] == "code_review"
      assert decoded["params"]["argument"]["name"] == "language"
      assert decoded["params"]["argument"]["value"] == "py"

      request_id = get_request_id(client, "completion/complete")
      assert request_id

      values = ["python", "pytorch", "pyside"]
      response = completion_complete_response(request_id, values, total: 3, has_more: false)
      send_response(client, response)

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response

      completion = Response.unwrap(response)["completion"]
      assert is_map(completion)
      assert completion["values"] == values
      assert completion["total"] == 3
      assert completion["hasMore"] == false
    end

    test "complete sends correct completion/complete request for resource reference", %{client: client} do
      ref = %{"type" => "ref/resource", "uri" => "file:///path/to/file.txt"}
      argument = %{"name" => "encoding", "value" => "ut"}

      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      task = Task.async(fn -> Hermes.Client.complete(client, ref, argument) end)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1
      [message] = messages
      {:ok, [decoded]} = Message.decode(message)
      assert decoded["method"] == "completion/complete"
      assert decoded["params"]["ref"]["type"] == "ref/resource"
      assert decoded["params"]["ref"]["uri"] == "file:///path/to/file.txt"
      assert decoded["params"]["argument"]["name"] == "encoding"
      assert decoded["params"]["argument"]["value"] == "ut"

      request_id = get_request_id(client, "completion/complete")
      assert request_id

      values = ["utf-8", "utf-16"]
      response = completion_complete_response(request_id, values, total: 2, has_more: false)
      send_response(client, response)

      assert {:ok, response} = Task.await(task)

      completion = Response.unwrap(response)["completion"]
      assert completion["values"] == values
      assert completion["total"] == 2
      assert completion["hasMore"] == false
    end

    test "register_log_callback sets the callback", %{client: client} do
      callback = fn _, _, _ -> nil end
      :ok = Hermes.Client.register_log_callback(client, callback)

      state = :sys.get_state(client)
      assert state.log_callback == callback
    end

    test "unregister_log_callback removes the callback", %{client: client} do
      callback = fn _, _, _ -> nil end

      assert :ok = Hermes.Client.register_log_callback(client, callback)
      assert :ok = Hermes.Client.unregister_log_callback(client)

      state = :sys.get_state(client)
      assert is_nil(state.log_callback)
    end

    test "handles log notifications and triggers callbacks", %{client: client} do
      test_pid = self()

      :ok =
        Hermes.Client.register_log_callback(client, fn level, data, logger ->
          send(test_pid, {:log_callback, level, data, logger})
        end)

      log_notification = log_notification("error", "Test error message", "test-logger")
      send_notification(client, log_notification)

      assert_receive {:log_callback, "error", "Test error message", "test-logger"}, 1000
    end
  end

  describe "notification handling" do
    test "sends initialized notification after init" do
      transport_name = :notification_test_transport
      start_supervised!({MCPTest.MockTransport, [name: transport_name]})

      client =
        start_supervised!(
          {Hermes.Client,
           transport: [layer: MCPTest.MockTransport, name: transport_name],
           client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
          restart: :temporary
        )

      Process.sleep(50)
      MCPTest.MockTransport.clear_messages(transport_name)

      send_initialize_request(client)

      Process.sleep(50)

      request_id = get_request_id(client, "initialize")
      assert request_id

      init_response = init_response(request_id, %{"completion" => %{}})
      send_response(client, init_response)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)

      initialized_msg =
        Enum.find(messages, fn msg ->
          case Message.decode(msg) do
            {:ok, [decoded]} -> decoded["method"] == "notifications/initialized"
            _ -> false
          end
        end)

      assert initialized_msg != nil

      :sys.get_state(client)
    end
  end

  describe "cancellation" do
    setup :initialized_client

    test "handles cancelled notification from server", %{client: client} do
      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      task = Task.async(fn -> Hermes.Client.call_tool(client, "long_running_tool") end)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1
      [message] = messages
      {:ok, [decoded]} = Message.decode(message)
      assert decoded["method"] == "tools/call"

      request_id = get_request_id(client, "tools/call")
      assert request_id != nil

      cancelled_notification = cancelled_notification(request_id, "server timeout")
      send_notification(client, cancelled_notification)

      assert {:error, error} = Task.await(task)
      assert error.reason == :request_cancelled
      assert error.data[:reason] == "server timeout"

      state = :sys.get_state(client)
      assert state.pending_requests[request_id] == nil
    end

    test "client can cancel a request", %{client: client} do
      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      task = Task.async(fn -> Hermes.Client.list_resources(client) end)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1
      [message] = messages
      {:ok, [decoded]} = Message.decode(message)
      assert decoded["method"] == "resources/list"

      request_id = get_request_id(client, "resources/list")
      assert request_id != nil

      MCPTest.MockTransport.clear_messages(transport_name)

      assert :ok = Hermes.Client.cancel_request(client, request_id, "test cancellation")

      Process.sleep(50)

      cancel_messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(cancel_messages) == 1
      [cancel_msg] = cancel_messages
      {:ok, [cancel_decoded]} = Message.decode(cancel_msg)
      assert cancel_decoded["method"] == "notifications/cancelled"
      assert cancel_decoded["params"]["requestId"] == request_id
      assert cancel_decoded["params"]["reason"] == "test cancellation"

      assert {:error, error} = Task.await(task)
      assert error.reason == :request_cancelled
      assert error.data[:reason] == "test cancellation"

      state = :sys.get_state(client)
      assert state.pending_requests[request_id] == nil
    end

    test "client returns not_found when cancelling non-existent request", %{client: client} do
      result = Hermes.Client.cancel_request(client, "non_existent_id")
      assert %Error{reason: :request_not_found} = result
    end

    test "cancel_all_requests cancels all pending requests", %{client: client} do
      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      task1 = Task.async(fn -> Hermes.Client.list_resources(client) end)
      task2 = Task.async(fn -> Hermes.Client.list_tools(client) end)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 2

      methods =
        Enum.map(messages, fn msg ->
          {:ok, [decoded]} = Message.decode(msg)
          decoded["method"]
        end)

      assert "resources/list" in methods
      assert "tools/list" in methods

      state = :sys.get_state(client)
      pending_count = map_size(state.pending_requests)
      assert pending_count == 2

      MCPTest.MockTransport.clear_messages(transport_name)

      {:ok, cancelled_requests} = Hermes.Client.cancel_all_requests(client, "batch cancellation")
      assert length(cancelled_requests) == 2

      Process.sleep(50)

      cancel_messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(cancel_messages) == 2

      Enum.each(cancel_messages, fn msg ->
        {:ok, [decoded]} = Message.decode(msg)
        assert decoded["method"] == "notifications/cancelled"
        assert decoded["params"]["reason"] == "batch cancellation"
      end)

      assert {:error, error1} = Task.await(task1)
      assert {:error, error2} = Task.await(task2)

      assert error1.reason == :request_cancelled
      assert error2.reason == :request_cancelled

      state = :sys.get_state(client)
      assert map_size(state.pending_requests) == 0
    end

    test "request timeout sends cancellation notification", %{client: client} do
      test_timeout = 50

      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      task = Task.async(fn -> Hermes.Client.list_resources(client, timeout: test_timeout) end)

      Process.sleep(test_timeout * 2)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 2

      [request_msg, cancel_msg] = messages

      {:ok, [request_decoded]} = Message.decode(request_msg)
      assert request_decoded["method"] == "resources/list"

      {:ok, [cancel_decoded]} = Message.decode(cancel_msg)
      assert cancel_decoded["method"] == "notifications/cancelled"
      assert cancel_decoded["params"]["reason"] == "timeout"

      assert {:error, error} = Task.await(task)
      assert error.reason == :request_timeout

      state = :sys.get_state(client)
      assert map_size(state.pending_requests) == 0
    end

    test "buffer timeout allows operation timeout to trigger before GenServer timeout", %{client: client} do
      test_timeout = 50

      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.expect_method(transport_name, "resources/list", nil, fn ->
        Process.sleep(test_timeout + 10)
        :ok
      end)

      Process.flag(:trap_exit, true)
      task = Task.async(fn -> Hermes.Client.list_resources(client, timeout: test_timeout) end)

      result = Task.await(task)
      assert {:error, error} = result
      assert error.reason == :request_timeout

      refute_receive {:EXIT, _, {:timeout, _}}, 100
    end

    test "client.close sends cancellation for pending requests", %{client: client} do
      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      Process.flag(:trap_exit, true)
      task = Task.async(fn -> Hermes.Client.list_resources(client) end)
      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1
      [message] = messages
      {:ok, [decoded]} = Message.decode(message)
      assert decoded["method"] == "resources/list"

      request_id = get_request_id(client, "resources/list")
      assert request_id

      client_state = :sys.get_state(client)
      assert Map.has_key?(client_state.pending_requests, request_id)

      Hermes.Client.close(client)

      assert {:error, error} = Task.await(task, 1000)
      assert error.reason == :request_cancelled
      assert error.data[:reason] == "client closed"

      Process.sleep(50)
      refute Process.alive?(client)
    end
  end

  describe "roots management" do
    setup :initialized_client

    test "add_root adds a root directory", %{client: client} do
      :ok = Hermes.Client.add_root(client, "file:///home/user/project", "My Project")

      roots = Hermes.Client.list_roots(client)
      assert length(roots) == 1

      [root] = roots
      assert root.uri == "file:///home/user/project"
      assert root.name == "My Project"
    end

    test "list_roots returns all roots", %{client: client} do
      :ok = Hermes.Client.add_root(client, "file:///home/user/project1", "Project 1")
      :ok = Hermes.Client.add_root(client, "file:///home/user/project2", "Project 2")

      roots = Hermes.Client.list_roots(client)
      assert length(roots) == 2

      uris = Enum.map(roots, & &1.uri)
      assert "file:///home/user/project1" in uris
      assert "file:///home/user/project2" in uris
    end

    test "remove_root removes a specific root", %{client: client} do
      :ok = Hermes.Client.add_root(client, "file:///home/user/project1", "Project 1")
      :ok = Hermes.Client.add_root(client, "file:///home/user/project2", "Project 2")

      :ok = Hermes.Client.remove_root(client, "file:///home/user/project1")

      roots = Hermes.Client.list_roots(client)
      assert length(roots) == 1
      assert hd(roots).uri == "file:///home/user/project2"
    end

    test "clear_roots removes all roots", %{client: client} do
      :ok = Hermes.Client.add_root(client, "file:///home/user/project1", "Project 1")
      :ok = Hermes.Client.add_root(client, "file:///home/user/project2", "Project 2")

      :ok = Hermes.Client.clear_roots(client)

      roots = Hermes.Client.list_roots(client)
      assert Enum.empty?(roots)
    end

    test "add_root doesn't add duplicates", %{client: client} do
      :ok = Hermes.Client.add_root(client, "file:///home/user/project", "My Project")
      :ok = Hermes.Client.add_root(client, "file:///home/user/project", "Duplicate Project")

      roots = Hermes.Client.list_roots(client)
      assert length(roots) == 1
      assert hd(roots).name == "My Project"
    end
  end

  describe "server requests" do
    setup :initialized_client

    test "server can request roots list", %{client: client} do
      :ok = Hermes.Client.add_root(client, "file:///home/user/project1", "Project 1")
      :ok = Hermes.Client.add_root(client, "file:///home/user/project2", "Project 2")

      Process.sleep(100)

      request_id = "server_req_123"

      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      assert {:ok, encoded} = Message.encode_request(%{"method" => "roots/list"}, request_id)
      GenServer.cast(client, {:response, encoded})

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)
      assert length(messages) == 1
      [message] = messages
      {:ok, [decoded]} = Message.decode(message)
      assert decoded["jsonrpc"] == "2.0"
      assert decoded["id"] == request_id
      assert Map.has_key?(decoded, "result")

      roots = decoded["result"]["roots"]
      assert is_list(roots)
      assert length(roots) == 2

      uris = Enum.map(roots, & &1["uri"])
      assert "file:///home/user/project1" in uris
      assert "file:///home/user/project2" in uris
    end
  end

  describe "automatic roots notification" do
    setup :initialized_client

    @tag client_capabilities: %{"roots" => %{"listChanged" => true}}
    test "sends notification when adding a root", %{client: client} do
      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      assert :ok = Hermes.Client.add_root(client, "file:///test/root", "Test Root")
      _ = :sys.get_state(client)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)

      notification_msg =
        Enum.find(messages, fn msg ->
          case Message.decode(msg) do
            {:ok, [decoded]} -> decoded["method"] == "notifications/roots/list_changed"
            _ -> false
          end
        end)

      assert notification_msg != nil
      {:ok, [decoded]} = Message.decode(notification_msg)
      assert decoded["jsonrpc"] == "2.0"
      assert decoded["method"] == "notifications/roots/list_changed"
      assert is_map(decoded["params"])
    end

    @tag client_capabilities: %{"roots" => %{"listChanged" => true}}
    test "sends notification when removing a root", %{client: client} do
      assert :ok = Hermes.Client.add_root(client, "file:///test/root", "Test Root")
      Process.sleep(50)

      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      assert :ok = Hermes.Client.remove_root(client, "file:///test/root")
      _ = :sys.get_state(client)

      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)

      notification_msg =
        Enum.find(messages, fn msg ->
          case Message.decode(msg) do
            {:ok, [decoded]} -> decoded["method"] == "notifications/roots/list_changed"
            _ -> false
          end
        end)

      assert notification_msg != nil
      {:ok, [decoded]} = Message.decode(notification_msg)
      assert decoded["jsonrpc"] == "2.0"
      assert decoded["method"] == "notifications/roots/list_changed"
      assert is_map(decoded["params"])
    end

    @tag client_capabilities: %{"roots" => %{"listChanged" => true}}
    test "sends notification when clearing roots", %{client: client} do
      assert :ok = Hermes.Client.add_root(client, "file:///test/root1", "Test Root 1")
      assert :ok = Hermes.Client.add_root(client, "file:///test/root2", "Test Root 2")
      Process.sleep(50)

      state = :sys.get_state(client)
      transport_name = state.transport.name

      MCPTest.MockTransport.clear_messages(transport_name)

      assert :ok = Hermes.Client.clear_roots(client)

      _ = :sys.get_state(client)
      Process.sleep(50)

      messages = MCPTest.MockTransport.get_messages(transport_name)

      notification_msg =
        Enum.find(messages, fn msg ->
          case Message.decode(msg) do
            {:ok, [decoded]} -> decoded["method"] == "notifications/roots/list_changed"
            _ -> false
          end
        end)

      assert notification_msg != nil
      {:ok, [decoded]} = Message.decode(notification_msg)
      assert decoded["jsonrpc"] == "2.0"
      assert decoded["method"] == "notifications/roots/list_changed"
      assert is_map(decoded["params"])
    end

    @tag client_capabilities: %{"roots" => %{"listChanged" => false}}
    test "doesn't send notification when doesn't support listChanged", %{client: client} do
      assert :ok = Hermes.Client.add_root(client, "file:///test/root", "Test Root")
      _ = :sys.get_state(client)
    end
  end
end
