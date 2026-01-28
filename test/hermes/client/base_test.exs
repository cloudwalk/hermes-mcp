defmodule Hermes.Client.BaseTest do
  use Hermes.MCP.Case, async: false

  import Mox

  alias Hermes.MCP.Error
  alias Hermes.MCP.ID
  alias Hermes.MCP.Message
  alias Hermes.MCP.Response

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Mox.stub_with(Hermes.MockTransport, MockTransport)
    :ok
  end

  describe "start_link/1" do
    test "starts the client with proper initialization" do
      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        assert String.contains?(message, "initialize")
        assert String.contains?(message, "protocolVersion")
        assert String.contains?(message, "capabilities")
        assert String.contains?(message, "clientInfo")
        :ok
      end)

      client =
        start_supervised!(
          {Hermes.Client.Base,
           transport: [layer: Hermes.MockTransport, name: MockTransport],
           client_info: %{"name" => "TestClient", "version" => "1.0.0"},
           capabilities: %{}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)
      initialize_client(client)

      assert Process.alive?(client)
    end
  end

  describe "request methods" do
    setup :initialized_client

    test "ping sends correct request", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "ping"
        assert decoded["params"] == %{}
        assert decoded["jsonrpc"] == "2.0"
        assert is_binary(decoded["id"])
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.Base.ping(client) end)

      Process.sleep(50)

      request_id = get_request_id(client, "ping")
      assert request_id

      response = ping_response(request_id)
      send_response(client, response)

      assert :pong = Task.await(task)
    end

    test "list_resources sends correct request", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/list"
        assert decoded["params"] == %{}
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.Base.list_resources(client) end)

      Process.sleep(50)

      request_id = get_request_id(client, "resources/list")
      assert request_id

      resources = [%{"name" => "test", "uri" => "test://uri"}]
      response = resources_list_response(request_id, resources)
      send_response(client, response)

      expected_result = %{
        "resources" => resources,
        "nextCursor" => nil
      }

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result == expected_result
      assert response.is_error == false
    end

    test "list_resources with cursor", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/list"
        assert decoded["params"] == %{"cursor" => "next-page"}
        :ok
      end)

      task =
        Task.async(fn ->
          Hermes.Client.Base.list_resources(client, cursor: "next-page")
        end)

      Process.sleep(50)

      request_id = get_request_id(client, "resources/list")
      assert request_id

      resources = [%{"name" => "test2", "uri" => "test://uri2"}]
      response = resources_list_response(request_id, resources)
      send_response(client, response)

      expected_result = %{
        "resources" => resources,
        "nextCursor" => nil
      }

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result == expected_result
      assert response.is_error == false
    end

    test "read_resource sends correct request", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/read"
        assert decoded["params"] == %{"uri" => "test://uri"}
        :ok
      end)

      task =
        Task.async(fn -> Hermes.Client.Base.read_resource(client, "test://uri") end)

      Process.sleep(50)

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
      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "prompts/list"
        assert decoded["params"] == %{}
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.Base.list_prompts(client) end)

      Process.sleep(50)

      request_id = get_request_id(client, "prompts/list")
      assert request_id

      prompts = [%{"name" => "test_prompt"}]
      response = prompts_list_response(request_id, prompts)
      send_response(client, response)

      expected_result = %{
        "prompts" => prompts,
        "nextCursor" => nil
      }

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result == expected_result
      assert response.is_error == false
    end

    test "get_prompt sends correct request", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "prompts/get"

        assert decoded["params"] == %{
                 "name" => "test_prompt",
                 "arguments" => %{"arg1" => "value1"}
               }

        :ok
      end)

      task =
        Task.async(fn ->
          Hermes.Client.Base.get_prompt(client, "test_prompt", %{"arg1" => "value1"})
        end)

      Process.sleep(50)

      request_id = get_request_id(client, "prompts/get")
      assert request_id

      messages = [
        %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}
      ]

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
      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "tools/list"
        assert decoded["params"] == %{}
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.Base.list_tools(client) end)

      Process.sleep(50)

      request_id = get_request_id(client, "tools/list")
      assert request_id

      tools = [%{"name" => "test_tool"}]
      response = tools_list_response(request_id, tools)
      send_response(client, response)

      expected_result = %{
        "tools" => tools,
        "nextCursor" => nil
      }

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result == expected_result
      assert response.is_error == false
    end

    test "call_tool sends correct request", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "tools/call"

        assert decoded["params"] == %{
                 "name" => "test_tool",
                 "arguments" => %{"arg1" => "value1"}
               }

        :ok
      end)

      task =
        Task.async(fn ->
          Hermes.Client.Base.call_tool(client, "test_tool", %{"arg1" => "value1"})
        end)

      Process.sleep(50)

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
      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "tools/call"

        assert decoded["params"] == %{
                 "name" => "test_tool",
                 "arguments" => %{"arg1" => "value1"}
               }

        :ok
      end)

      task =
        Task.async(fn ->
          Hermes.Client.Base.call_tool(client, "test_tool", %{"arg1" => "value1"})
        end)

      Process.sleep(50)

      request_id = get_request_id(client, "tools/call")
      assert request_id

      # Response with isError: true but still a valid domain response
      content = [
        %{"type" => "text", "text" => "Tool execution failed: invalid argument"}
      ]

      response = tools_call_response(request_id, content, true)
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
      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "ping"
        assert decoded["params"] == %{}
        assert decoded["jsonrpc"] == "2.0"
        assert is_binary(decoded["id"])
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.Base.ping(client) end)

      Process.sleep(50)

      request_id = get_request_id(client, "ping")
      assert request_id

      response = ping_response(request_id)
      send_response(client, response)

      assert :pong = Task.await(task)
    end

    @tag server_capabilities: %{"prompts" => %{}}
    test "tools/list fails since this capability isn't supported", %{client: client} do
      task = Task.async(fn -> Hermes.Client.Base.list_tools(client) end)

      assert {:error, %Error{reason: :method_not_found, data: %{method: "tools/list"}}} =
               Task.await(task)
    end
  end

  describe "error handling" do
    setup :initialized_client

    test "handles error response", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "ping"
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.Base.ping(client) end)

      Process.sleep(50)

      request_id = get_request_id(client, "ping")
      assert request_id

      error_response = error_response(request_id)
      send_error(client, error_response)

      {:error, error} = Task.await(task)
      assert error.code == -32_601
      assert error.reason == :method_not_found
      assert error.message == "Method not found"
    end

    test "handles transport error", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, _message, _opts ->
        {:error, :connection_closed}
      end)

      assert {:error, error} = Hermes.Client.Base.ping(client)
      assert error.reason == :send_failure
      assert error.data.original_reason == :connection_closed
    end
  end

  describe "capability management" do
    test "merge_capabilities correctly merges capabilities" do
      expect(Hermes.MockTransport, :send_message, fn _, _message, _opts -> :ok end)

      client =
        start_supervised!(
          {Hermes.Client.Base,
           transport: [layer: Hermes.MockTransport, name: MockTransport],
           client_info: %{"name" => "TestClient", "version" => "1.0.0"},
           capabilities: %{"roots" => %{}}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)

      initialize_client(client)

      new_capabilities = %{"sampling" => %{}}

      updated = Hermes.Client.Base.merge_capabilities(client, new_capabilities)

      assert updated == %{"roots" => %{}, "sampling" => %{}}

      nested_capabilities = %{"roots" => %{"listChanged" => true}}

      final = Hermes.Client.Base.merge_capabilities(client, nested_capabilities)

      assert final == %{"sampling" => %{}, "roots" => %{"listChanged" => true}}
    end
  end

  describe "server information" do
    setup :initialized_client

    test "get_server_capabilities returns server capabilities", %{client: client} do
      capabilities = Hermes.Client.Base.get_server_capabilities(client)

      assert Map.has_key?(capabilities, "resources")
      assert Map.has_key?(capabilities, "tools")
      assert Map.has_key?(capabilities, "prompts")
    end

    test "get_server_info returns server info", %{client: client} do
      server_info = Hermes.Client.Base.get_server_info(client)

      assert server_info == %{"name" => "TestServer", "version" => "1.0.0"}
    end
  end

  describe "progress tracking" do
    setup :initialized_client

    test "registers and calls progress callback when notification is received", %{
      client: client
    } do
      test_pid = self()
      progress_token = "test_progress_token"
      progress_value = 50
      total_value = 100

      :ok =
        Hermes.Client.Base.register_progress_callback(
          client,
          progress_token,
          fn token, progress, total ->
            send(test_pid, {:progress_callback, token, progress, total})
          end
        )

      progress_notification =
        progress_notification(progress_token, progress_value, total_value)

      send_notification(client, progress_notification)

      assert_receive {:progress_callback, ^progress_token, ^progress_value, ^total_value},
                     1000
    end

    test "unregisters progress callback", %{client: client} do
      test_pid = self()
      progress_token = "unregister_test_token"

      :ok =
        Hermes.Client.Base.register_progress_callback(client, progress_token, fn _, _, _ ->
          send(test_pid, :should_not_be_called)
        end)

      :ok = Hermes.Client.Base.unregister_progress_callback(client, progress_token)

      progress_notification = progress_notification(progress_token)
      send_notification(client, progress_notification)

      refute_receive :should_not_be_called, 500
    end

    test "request with progress token includes it in params", %{client: client} do
      progress_token = "request_token_test"

      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/list"

        assert decoded["params"] == %{
                 "_meta" => %{"progressToken" => progress_token}
               }

        :ok
      end)

      task =
        Task.async(fn ->
          Hermes.Client.Base.list_resources(client,
            progress: [token: progress_token]
          )
        end)

      Process.sleep(50)

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

    @tag server_capabilities: %{
           "logging" => %{},
           "resources" => %{},
           "tools" => %{},
           "prompts" => %{}
         }

    test "set_log_level sends the correct request", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "logging/setLevel"
        assert decoded["params"]["level"] == "info"
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.Base.set_log_level(client, "info") end)

      Process.sleep(50)

      request_id = get_request_id(client, "logging/setLevel")
      assert request_id

      response = empty_result_response(request_id)
      send_response(client, response)

      assert {:ok, %{}} = Task.await(task)
    end

    @tag server_capabilities: %{
           "completion" => %{},
           "logging" => %{},
           "resources" => %{},
           "tools" => %{},
           "prompts" => %{}
         }
    test "complete sends correct completion/complete request for prompt reference",
         %{client: client} do
      ref = %{"type" => "ref/prompt", "name" => "code_review"}
      argument = %{"name" => "language", "value" => "py"}

      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "completion/complete"
        assert decoded["params"]["ref"]["type"] == "ref/prompt"
        assert decoded["params"]["ref"]["name"] == "code_review"
        assert decoded["params"]["argument"]["name"] == "language"
        assert decoded["params"]["argument"]["value"] == "py"
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.Base.complete(client, ref, argument) end)

      Process.sleep(50)

      request_id = get_request_id(client, "completion/complete")
      assert request_id

      values = ["python", "pytorch", "pyside"]
      response = completion_complete_response(request_id, values, 3, false)
      send_response(client, response)

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response

      completion = Response.unwrap(response)["completion"]
      assert is_map(completion)
      assert completion["values"] == values
      assert completion["total"] == 3
      assert completion["hasMore"] == false
    end

    @tag server_capabilities: %{
           "completion" => %{},
           "logging" => %{},
           "resources" => %{},
           "tools" => %{},
           "prompts" => %{}
         }
    test "complete sends correct completion/complete request for resource reference",
         %{client: client} do
      ref = %{"type" => "ref/resource", "uri" => "file:///path/to/file.txt"}
      argument = %{"name" => "encoding", "value" => "ut"}

      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "completion/complete"
        assert decoded["params"]["ref"]["type"] == "ref/resource"
        assert decoded["params"]["ref"]["uri"] == "file:///path/to/file.txt"
        assert decoded["params"]["argument"]["name"] == "encoding"
        assert decoded["params"]["argument"]["value"] == "ut"
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.Base.complete(client, ref, argument) end)

      Process.sleep(50)

      request_id = get_request_id(client, "completion/complete")
      assert request_id

      values = ["utf-8", "utf-16"]
      response = completion_complete_response(request_id, values, 2, false)
      send_response(client, response)

      assert {:ok, response} = Task.await(task)

      completion = Response.unwrap(response)["completion"]
      assert completion["values"] == values
      assert completion["total"] == 2
      assert completion["hasMore"] == false
    end

    test "register_log_callback sets the callback", %{client: client} do
      callback = fn _, _, _ -> nil end
      :ok = Hermes.Client.Base.register_log_callback(client, callback)

      state = :sys.get_state(client)
      assert state.log_callback == callback
    end

    test "unregister_log_callback removes the callback", %{client: client} do
      callback = fn _, _, _ -> nil end

      assert :ok = Hermes.Client.Base.register_log_callback(client, callback)
      assert :ok = Hermes.Client.Base.unregister_log_callback(client)

      state = :sys.get_state(client)
      assert is_nil(state.log_callback)
    end

    test "handles log notifications and triggers callbacks", %{client: client} do
      test_pid = self()

      :ok =
        Hermes.Client.Base.register_log_callback(client, fn level, data, logger ->
          send(test_pid, {:log_callback, level, data, logger})
        end)

      log_notification =
        log_notification("error", "Test error message", "test-logger")

      send_notification(client, log_notification)

      assert_receive {:log_callback, "error", "Test error message", "test-logger"},
                     1000
    end
  end

  describe "notification handling" do
    test "sends initialized notification after init" do
      Hermes.MockTransport
      # the handle_continue
      |> expect(:send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "initialize"
        assert decoded["jsonrpc"] == "2.0"
        :ok
      end)
      # the send_notification
      |> expect(:send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "notifications/initialized"
        :ok
      end)

      client =
        start_supervised!(
          {Hermes.Client.Base,
           transport: [layer: Hermes.MockTransport, name: MockTransport],
           client_info: %{"name" => "TestClient", "version" => "1.0.0"},
           capabilities: %{}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)

      initialize_client(client)

      # The client should have sent the initialized notification
      state = :sys.get_state(client)
      assert state.server_info
      assert state.server_capabilities
    end
  end

  describe "cancellation" do
    setup :initialized_client

    test "handles cancelled notification from server", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "tools/call"
        :ok
      end)

      task =
        Task.async(fn ->
          Hermes.Client.Base.call_tool(client, "long_running_tool")
        end)

      Process.sleep(50)

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
      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/list"
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.Base.list_resources(client) end)

      Process.sleep(50)

      request_id = get_request_id(client, "resources/list")
      assert request_id != nil

      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "notifications/cancelled"
        assert decoded["params"]["requestId"] == request_id
        assert decoded["params"]["reason"] == "test cancellation"
        :ok
      end)

      assert :ok =
               Hermes.Client.Base.cancel_request(
                 client,
                 request_id,
                 "test cancellation"
               )

      assert {:error, error} = Task.await(task)
      assert error.reason == :request_cancelled
      assert error.data[:reason] == "test cancellation"

      state = :sys.get_state(client)
      assert state.pending_requests[request_id] == nil
    end

    test "client returns not_found when cancelling non-existent request", %{
      client: client
    } do
      result = Hermes.Client.Base.cancel_request(client, "non_existent_id")
      assert %Error{reason: :request_not_found} = result
    end

    test "cancel_all_requests cancels all pending requests", %{client: client} do
      expect(Hermes.MockTransport, :send_message, 2, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] in ["resources/list", "tools/list"]
        :ok
      end)

      task1 = Task.async(fn -> Hermes.Client.Base.list_resources(client) end)
      task2 = Task.async(fn -> Hermes.Client.Base.list_tools(client) end)

      Process.sleep(50)

      state = :sys.get_state(client)
      pending_count = map_size(state.pending_requests)
      assert pending_count == 2

      expect(Hermes.MockTransport, :send_message, 2, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "notifications/cancelled"
        assert decoded["params"]["reason"] == "batch cancellation"
        :ok
      end)

      {:ok, cancelled_requests} =
        Hermes.Client.Base.cancel_all_requests(client, "batch cancellation")

      assert length(cancelled_requests) == 2

      assert {:error, error1} = Task.await(task1)
      assert {:error, error2} = Task.await(task2)

      assert error1.reason == :request_cancelled
      assert error2.reason == :request_cancelled

      state = :sys.get_state(client)
      assert map_size(state.pending_requests) == 0
    end

    test "request timeout sends cancellation notification", %{client: client} do
      test_timeout = 50

      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/list"
        :ok
      end)

      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "notifications/cancelled"
        assert decoded["params"]["reason"] == "timeout"
        :ok
      end)

      task =
        Task.async(fn ->
          Hermes.Client.Base.list_resources(client, timeout: test_timeout)
        end)

      Process.sleep(test_timeout * 2)

      assert {:error, error} = Task.await(task)
      assert error.reason == :request_timeout

      state = :sys.get_state(client)
      assert map_size(state.pending_requests) == 0
    end

    test "buffer timeout allows operation timeout to trigger before GenServer timeout",
         %{client: client} do
      test_timeout = 50

      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/list"
        Process.sleep(test_timeout + 10)
        :ok
      end)

      expect(Hermes.MockTransport, :send_message, fn _, _, _opts -> :ok end)

      Process.flag(:trap_exit, true)

      task =
        Task.async(fn ->
          Hermes.Client.Base.list_resources(client, timeout: test_timeout)
        end)

      result = Task.await(task)
      assert {:error, error} = result
      assert error.reason == :request_timeout

      refute_receive {:EXIT, _, {:timeout, _}}, 100
    end

    test "client.close sends cancellation for pending requests", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/list"
        :ok
      end)

      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "notifications/cancelled"
        assert decoded["params"]["reason"] == "client closed"
        :ok
      end)

      expect(Hermes.MockTransport, :shutdown, fn _ -> :ok end)

      Process.flag(:trap_exit, true)
      %{pid: pid} = Task.async(fn -> Hermes.Client.Base.list_resources(client) end)
      Process.sleep(50)

      assert get_request_id(client, "resources/list")

      Hermes.Client.Base.close(client)

      Process.sleep(50)
      refute Process.alive?(client)

      # The task exits normally when the client closes
      assert_receive {:EXIT, ^pid, :normal}
    end
  end

  describe "roots management" do
    setup :initialized_client

    test "add_root adds a root directory", %{client: client} do
      :ok =
        Hermes.Client.Base.add_root(
          client,
          "file:///home/user/project",
          "My Project"
        )

      roots = Hermes.Client.Base.list_roots(client)
      assert length(roots) == 1

      [root] = roots
      assert root.uri == "file:///home/user/project"
      assert root.name == "My Project"
    end

    test "list_roots returns all roots", %{client: client} do
      :ok =
        Hermes.Client.Base.add_root(
          client,
          "file:///home/user/project1",
          "Project 1"
        )

      :ok =
        Hermes.Client.Base.add_root(
          client,
          "file:///home/user/project2",
          "Project 2"
        )

      roots = Hermes.Client.Base.list_roots(client)
      assert length(roots) == 2

      uris = Enum.map(roots, & &1.uri)
      assert "file:///home/user/project1" in uris
      assert "file:///home/user/project2" in uris
    end

    test "remove_root removes a specific root", %{client: client} do
      :ok =
        Hermes.Client.Base.add_root(
          client,
          "file:///home/user/project1",
          "Project 1"
        )

      :ok =
        Hermes.Client.Base.add_root(
          client,
          "file:///home/user/project2",
          "Project 2"
        )

      :ok = Hermes.Client.Base.remove_root(client, "file:///home/user/project1")

      roots = Hermes.Client.Base.list_roots(client)
      assert length(roots) == 1
      assert hd(roots).uri == "file:///home/user/project2"
    end

    test "clear_roots removes all roots", %{client: client} do
      :ok =
        Hermes.Client.Base.add_root(
          client,
          "file:///home/user/project1",
          "Project 1"
        )

      :ok =
        Hermes.Client.Base.add_root(
          client,
          "file:///home/user/project2",
          "Project 2"
        )

      :ok = Hermes.Client.Base.clear_roots(client)

      roots = Hermes.Client.Base.list_roots(client)
      assert Enum.empty?(roots)
    end

    test "add_root doesn't add duplicates", %{client: client} do
      :ok =
        Hermes.Client.Base.add_root(
          client,
          "file:///home/user/project",
          "My Project"
        )

      :ok =
        Hermes.Client.Base.add_root(
          client,
          "file:///home/user/project",
          "Duplicate Project"
        )

      roots = Hermes.Client.Base.list_roots(client)
      assert length(roots) == 1
      assert hd(roots).name == "My Project"
    end
  end

  describe "server requests" do
    setup :initialized_client

    test "server can request roots list", %{client: client} do
      :ok =
        Hermes.Client.Base.add_root(
          client,
          "file:///home/user/project1",
          "Project 1"
        )

      :ok =
        Hermes.Client.Base.add_root(
          client,
          "file:///home/user/project2",
          "Project 2"
        )

      request_id = "server_req_123"

      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["jsonrpc"] == "2.0"
        assert decoded["id"] == request_id
        assert Map.has_key?(decoded, "result")

        roots = decoded["result"]["roots"]
        assert is_list(roots)
        assert length(roots) == 2

        uris = Enum.map(roots, & &1["uri"])
        assert "file:///home/user/project1" in uris
        assert "file:///home/user/project2" in uris

        :ok
      end)

      assert {:ok, encoded} =
               Message.encode_request(%{"method" => "roots/list"}, request_id)

      GenServer.cast(client, {:response, encoded})

      Process.sleep(50)
    end
  end

  describe "sampling" do
    setup :initialized_client

    @tag client_capabilities: %{"sampling" => %{}}
    test "register_sampling_callback sets the callback", %{client: client} do
      callback = fn _params ->
        {:ok, %{role: "assistant", content: %{type: "text", text: "Hello"}}}
      end

      :ok = Hermes.Client.Base.register_sampling_callback(client, callback)

      state = :sys.get_state(client)
      assert is_function(state.sampling_callback, 1)
    end

    @tag client_capabilities: %{"sampling" => %{}}
    test "unregister_sampling_callback removes the callback", %{client: client} do
      callback = fn _params ->
        {:ok, %{role: "assistant", content: %{type: "text", text: "Hello"}}}
      end

      assert :ok = Hermes.Client.Base.register_sampling_callback(client, callback)
      assert :ok = Hermes.Client.Base.unregister_sampling_callback(client)

      state = :sys.get_state(client)
      assert is_nil(state.sampling_callback)
    end

    @tag client_capabilities: %{"sampling" => %{}}
    test "handles sampling/createMessage request from server", %{client: client} do
      test_pid = self()

      # Register a sampling callback
      :ok =
        Hermes.Client.Base.register_sampling_callback(client, fn params ->
          send(test_pid, {:sampling_called, params})

          {:ok,
           %{
             "role" => "assistant",
             "content" => %{"type" => "text", "text" => "Generated response"},
             "model" => "test-model",
             "stopReason" => "endTurn"
           }}
        end)

      request_id = "server_sampling_req_123"

      params = %{
        "messages" => [
          %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}
        ],
        "maxTokens" => 100,
        "modelPreferences" => %{}
      }

      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["jsonrpc"] == "2.0"
        assert decoded["id"] == request_id
        assert Map.has_key?(decoded, "result")

        result = decoded["result"]
        assert result["role"] == "assistant"
        assert result["content"]["type"] == "text"
        assert result["content"]["text"] == "Generated response"
        assert result["model"] == "test-model"

        :ok
      end)

      assert {:ok, encoded} =
               Message.encode_request(
                 %{"method" => "sampling/createMessage", "params" => params},
                 request_id
               )

      GenServer.cast(client, {:response, encoded})
      Process.sleep(100)
      assert_receive {:sampling_called, ^params}
    end

    @tag client_capabilities: %{"sampling" => %{}}
    test "handles sampling error when no callback registered", %{client: client} do
      request_id = "server_sampling_req_456"

      params = %{
        "messages" => [
          %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}
        ],
        "modelPreferences" => %{}
      }

      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["jsonrpc"] == "2.0"
        assert decoded["id"] == request_id
        assert Map.has_key?(decoded, "error")

        error = decoded["error"]
        assert error["code"] == -1
        assert error["message"] =~ "No sampling callback registered"

        :ok
      end)

      assert {:ok, encoded} =
               Message.encode_request(
                 %{"method" => "sampling/createMessage", "params" => params},
                 request_id
               )

      GenServer.cast(client, {:response, encoded})

      Process.sleep(100)
    end

    @tag client_capabilities: %{"sampling" => %{}}
    test "handles sampling callback error", %{client: client} do
      test_pid = self()

      # Register a callback that returns an error
      :ok =
        Hermes.Client.Base.register_sampling_callback(client, fn params ->
          send(test_pid, {:sampling_called, params})
          {:error, "Model unavailable"}
        end)

      request_id = "server_sampling_req_789"
      params = %{"messages" => [], "modelPreferences" => %{}}

      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["jsonrpc"] == "2.0"
        assert decoded["id"] == request_id
        assert Map.has_key?(decoded, "error")

        error = decoded["error"]
        assert error["message"] == "Model unavailable"

        :ok
      end)

      assert {:ok, encoded} =
               Message.encode_request(
                 %{"method" => "sampling/createMessage", "params" => params},
                 request_id
               )

      GenServer.cast(client, {:response, encoded})
      Process.sleep(100)

      assert_receive {:sampling_called, ^params}
    end

    @tag client_capabilities: %{"sampling" => %{}}
    test "handles sampling callback exception", %{client: client} do
      test_pid = self()

      # Register a callback that raises an exception
      :ok =
        Hermes.Client.Base.register_sampling_callback(client, fn params ->
          send(test_pid, {:sampling_called, params})
          raise "Something went wrong!"
        end)

      request_id = "server_sampling_req_999"
      params = %{"messages" => [], "modelPreferences" => %{}}

      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["jsonrpc"] == "2.0"
        assert decoded["id"] == request_id
        assert Map.has_key?(decoded, "error")

        error = decoded["error"]
        assert error["message"] =~ "Sampling callback error"
        assert error["message"] =~ "Something went wrong!"

        :ok
      end)

      assert {:ok, encoded} =
               Message.encode_request(
                 %{"method" => "sampling/createMessage", "params" => params},
                 request_id
               )

      GenServer.cast(client, {:response, encoded})
      Process.sleep(100)

      assert_receive {:sampling_called, ^params}
    end
  end

  describe "automatic roots notification" do
    setup :initialized_client

    @tag client_capabilities: %{"roots" => %{"listChanged" => true}}
    test "sends notification when adding a root", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["jsonrpc"] == "2.0"
        assert decoded["method"] == "notifications/roots/list_changed"
        assert is_map(decoded["params"])
        :ok
      end)

      assert :ok =
               Hermes.Client.Base.add_root(client, "file:///test/root", "Test Root")

      _ = :sys.get_state(client)

      Process.sleep(50)
    end

    @tag client_capabilities: %{"roots" => %{"listChanged" => true}}
    test "sends notification when removing a root", %{client: client} do
      assert :ok =
               Hermes.Client.Base.add_root(client, "file:///test/root", "Test Root")

      Process.sleep(50)

      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["jsonrpc"] == "2.0"
        assert decoded["method"] == "notifications/roots/list_changed"
        assert is_map(decoded["params"])
        :ok
      end)

      assert :ok = Hermes.Client.Base.remove_root(client, "file:///test/root")
      _ = :sys.get_state(client)

      Process.sleep(50)
    end

    @tag client_capabilities: %{"roots" => %{"listChanged" => true}}
    test "sends notification when clearing roots", %{client: client} do
      assert :ok =
               Hermes.Client.Base.add_root(
                 client,
                 "file:///test/root1",
                 "Test Root 1"
               )

      assert :ok =
               Hermes.Client.Base.add_root(
                 client,
                 "file:///test/root2",
                 "Test Root 2"
               )

      Process.sleep(50)

      expect(Hermes.MockTransport, :send_message, fn _, message, _opts ->
        decoded = JSON.decode!(message)
        assert decoded["jsonrpc"] == "2.0"
        assert decoded["method"] == "notifications/roots/list_changed"
        assert is_map(decoded["params"])
        :ok
      end)

      assert :ok = Hermes.Client.Base.clear_roots(client)

      _ = :sys.get_state(client)
      Process.sleep(50)
    end

    @tag client_capabilities: %{"roots" => %{"listChanged" => false}}
    test "doesn't send notification when doesn't support listChanged", %{
      client: client
    } do
      assert :ok =
               Hermes.Client.Base.add_root(client, "file:///test/root", "Test Root")

      _ = :sys.get_state(client)
    end
  end

  describe "tool output schema validation caching" do
    setup :initialized_client

    test "handles tools with complex outputSchema", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, _, _opts -> :ok end)

      task = Task.async(fn -> Hermes.Client.Base.list_tools(client) end)
      Process.sleep(50)

      request_id = get_request_id(client, "tools/list")

      tools = [
        %{
          "name" => "complex_tool",
          "outputSchema" => %{
            "type" => "object",
            "properties" => %{
              "items" => %{
                "type" => "array",
                "items" => %{
                  "type" => "object",
                  "properties" => %{
                    "id" => %{"type" => "integer"},
                    "name" => %{"type" => "string"},
                    "tags" => %{
                      "type" => "array",
                      "items" => %{"type" => "string"}
                    }
                  },
                  "required" => ["id", "name"]
                }
              },
              "metadata" => %{
                "type" => "object",
                "properties" => %{
                  "count" => %{"type" => "integer"},
                  "hasMore" => %{"type" => "boolean"}
                }
              }
            },
            "required" => ["items"]
          }
        }
      ]

      response = tools_list_response(request_id, tools)
      send_response(client, response)
      assert {:ok, _} = Task.await(task)
    end
  end
end
