defmodule Hermes.ClientTest do
  use ExUnit.Case, async: false

  import Mox

  alias Hermes.Client.Operation
  alias Hermes.Client.State
  alias Hermes.MCP.Error
  alias Hermes.MCP.ID
  alias Hermes.MCP.Message
  alias Hermes.MCP.Response

  @moduletag capture_log: true

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Mox.stub_with(Hermes.MockTransport, Hermes.MockTransportImpl)

    :ok
  end

  # Helper function to get request_id from state
  defp get_request_id(client, expected_method) do
    state = :sys.get_state(client)
    pending_requests = State.list_pending_requests(state)

    Enum.find_value(pending_requests, nil, fn
      %{method: ^expected_method, id: id} -> id
      _ -> nil
    end)
  end

  describe "start_link/1" do
    test "starts the client with proper initialization" do
      expect(Hermes.MockTransport, :send_message, fn _, message ->
        assert String.contains?(message, "initialize")
        assert String.contains?(message, "protocolVersion")
        assert String.contains?(message, "capabilities")
        assert String.contains?(message, "clientInfo")
        :ok
      end)

      client =
        start_supervised!(
          {Hermes.Client,
           transport: [layer: Hermes.MockTransport, name: Hermes.MockTransportImpl],
           client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)

      # trigger init handshake
      initialize_client(client)

      assert Process.alive?(client)
    end
  end

  describe "request methods" do
    setup do
      expect(Hermes.MockTransport, :send_message, 2, fn _, _message -> :ok end)

      client =
        start_supervised!(
          {Hermes.Client,
           transport: [layer: Hermes.MockTransport, name: Hermes.MockTransportImpl],
           client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)

      initialize_client(client)

      assert request_id = get_request_id(client, "initialize")

      init_response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "capabilities" => %{"resources" => %{}, "tools" => %{}, "prompts" => %{}},
          "serverInfo" => %{"name" => "TestServer", "version" => "1.0.0"},
          "protocolVersion" => "2024-11-05"
        }
      }

      send_response(client, init_response)
      Process.sleep(50)

      %{client: client}
    end

    test "ping sends correct request", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "ping"
        assert decoded["params"] == %{}
        assert decoded["jsonrpc"] == "2.0"
        assert is_binary(decoded["id"])
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.ping(client) end)

      Process.sleep(50)

      assert request_id = get_request_id(client, "ping")

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{}
      }

      send_response(client, response)

      assert :pong = Task.await(task)
    end

    test "list_resources sends correct request", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/list"
        assert decoded["params"] == %{}
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.list_resources(client) end)

      Process.sleep(50)

      assert request_id = get_request_id(client, "resources/list")

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "resources" => [%{"name" => "test", "uri" => "test://uri"}],
          "nextCursor" => nil
        }
      }

      send_response(client, response)

      expected_result = %{
        "resources" => [%{"name" => "test", "uri" => "test://uri"}],
        "nextCursor" => nil
      }

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result == expected_result
      assert response.is_error == false
    end

    test "list_resources with cursor", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/list"
        assert decoded["params"] == %{"cursor" => "next-page"}
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.list_resources(client, cursor: "next-page") end)

      Process.sleep(50)

      assert request_id = get_request_id(client, "resources/list")

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "resources" => [%{"name" => "test2", "uri" => "test://uri2"}],
          "nextCursor" => nil
        }
      }

      send_response(client, response)

      expected_result = %{
        "resources" => [%{"name" => "test2", "uri" => "test://uri2"}],
        "nextCursor" => nil
      }

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result == expected_result
      assert response.is_error == false
    end

    test "read_resource sends correct request", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/read"
        assert decoded["params"] == %{"uri" => "test://uri"}
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.read_resource(client, "test://uri") end)

      Process.sleep(50)

      assert request_id = get_request_id(client, "resources/read")

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "contents" => [%{"text" => "resource content", "uri" => "test://uri"}]
        }
      }

      send_response(client, response)

      expected_result = %{
        "contents" => [%{"text" => "resource content", "uri" => "test://uri"}]
      }

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result == expected_result
      assert response.is_error == false
    end

    test "list_prompts sends correct request", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "prompts/list"
        assert decoded["params"] == %{}
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.list_prompts(client) end)

      Process.sleep(50)

      assert request_id = get_request_id(client, "prompts/list")

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "prompts" => [%{"name" => "test_prompt"}],
          "nextCursor" => nil
        }
      }

      send_response(client, response)

      expected_result = %{
        "prompts" => [%{"name" => "test_prompt"}],
        "nextCursor" => nil
      }

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result == expected_result
      assert response.is_error == false
    end

    test "get_prompt sends correct request", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message ->
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
          Hermes.Client.get_prompt(client, "test_prompt", %{"arg1" => "value1"})
        end)

      Process.sleep(50)

      assert request_id = get_request_id(client, "prompts/get")

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "messages" => [%{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}]
        }
      }

      send_response(client, response)

      expected_result = %{
        "messages" => [%{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}]
      }

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result == expected_result
      assert response.is_error == false
    end

    test "list_tools sends correct request", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "tools/list"
        assert decoded["params"] == %{}
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.list_tools(client) end)

      Process.sleep(50)

      assert request_id = get_request_id(client, "tools/list")

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "tools" => [%{"name" => "test_tool"}],
          "nextCursor" => nil
        }
      }

      send_response(client, response)

      expected_result = %{
        "tools" => [%{"name" => "test_tool"}],
        "nextCursor" => nil
      }

      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result == expected_result
      assert response.is_error == false
    end

    test "call_tool times out with short genserver_timeout", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "tools/call"
        assert decoded["params"] == %{"name" => "test_tool"}
        Process.sleep(200) # Simulate slow response
        :ok
      end)

      Process.flag(:trap_exit, true)
      {pid, ref} = spawn_monitor(fn ->
        Hermes.Client.call_tool(client, "test_tool", nil, genserver_timeout: 100)
      end)

      # Wait for the process to die from timeout
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 300
    end

    test "call_tool succeeds with sufficient genserver_timeout", %{client: client} do
      # We need the request_id *before* the transport mock sleeps
      test_pid = self()

      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "tools/call"
        assert decoded["params"] == %{"name" => "test_tool"}
        send(test_pid, {:request_id, decoded["id"]})
        # Return immediately, don't block the GenServer
        :ok
      end)

      task = Task.async(fn ->
        Hermes.Client.call_tool(client, "test_tool", nil, genserver_timeout: 7_000)
      end)

      # Wait for the request_id to be sent from the mock
      request_id =
        receive do
          {:request_id, req_id} -> req_id
        after
          1000 -> flunk("Did not receive request_id within 1 second")
        end

      # Sleep to simulate delay before sending response
      # This should NOT cause a timeout since genserver_timeout is 7000ms
      Process.sleep(6000)

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{"status" => "success"}
      }

      send_response(client, response)

      assert {:ok, response} = Task.await(task, 8000)
      assert %Response{} = response
      assert response.result == %{"status" => "success"}
    end

    test "handles domain error responses as {:ok, response}", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "tools/call"
        assert decoded["params"] == %{"name" => "test_tool", "arguments" => %{"arg1" => "value1"}}
        :ok
      end)

      task =
        Task.async(fn -> Hermes.Client.call_tool(client, "test_tool", %{"arg1" => "value1"}) end)

      Process.sleep(50)

      assert request_id = get_request_id(client, "tools/call")

      # Response with isError: true but still a valid domain response
      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "content" => [%{"type" => "text", "text" => "Tool execution failed: invalid argument"}],
          "isError" => true
        }
      }

      send_response(client, response)

      expected_result = %{
        "content" => [%{"type" => "text", "text" => "Tool execution failed: invalid argument"}],
        "isError" => true
      }

      # Should return {:ok, response} even though isError is true
      assert {:ok, response} = Task.await(task)
      assert %Response{} = response
      assert response.result == expected_result
      assert response.is_error == true
    end
  end

  describe "non support request methods" do
    setup do
      expect(Hermes.MockTransport, :send_message, 2, fn _, _message -> :ok end)

      client =
        start_supervised!(
          {Hermes.Client,
           transport: [layer: Hermes.MockTransport, name: Hermes.MockTransportImpl],
           client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)

      initialize_client(client)

      assert request_id = get_request_id(client, "initialize")

      init_response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "capabilities" => %{"prompts" => %{}},
          "serverInfo" => %{"name" => "TestServer", "version" => "1.0.0"},
          "protocolVersion" => "2024-11-05"
        }
      }

      send_response(client, init_response)

      Process.sleep(50)

      %{client: client}
    end

    test "ping sends correct request since it is always supported", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "ping"
        assert decoded["params"] == %{}
        assert decoded["jsonrpc"] == "2.0"
        assert is_binary(decoded["id"])
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.ping(client) end)

      Process.sleep(50)

      assert request_id = get_request_id(client, "ping")

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{}
      }

      send_response(client, response)

      assert :pong = Task.await(task)
    end

    test "tools/list fails since this capability isn't supported", %{client: client} do
      task = Task.async(fn -> Hermes.Client.list_tools(client) end)

      assert {:error, %Error{reason: :method_not_found, data: %{method: "tools/list"}}} =
               Task.await(task)
    end
  end

  describe "error handling" do
    setup do
      expect(Hermes.MockTransport, :send_message, 2, fn _, _message -> :ok end)

      client =
        start_supervised!(
          {Hermes.Client,
           transport: [layer: Hermes.MockTransport, name: Hermes.MockTransportImpl],
           client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)

      initialize_client(client)

      assert request_id = get_request_id(client, "initialize")

      init_response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "capabilities" => %{"resources" => %{}, "tools" => %{}},
          "serverInfo" => %{"name" => "TestServer", "version" => "1.0.0"},
          "protocolVersion" => "2024-11-05"
        }
      }

      send_response(client, init_response)

      %{client: client}
    end

    test "handles error response", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "ping"
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.ping(client) end)

      Process.sleep(50)

      assert request_id = get_request_id(client, "ping")

      error_response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "error" => %{
          "code" => -32_601,
          "message" => "Method not found"
        }
      }

      send_error(client, error_response)

      {:error, error} = Task.await(task)
      assert error.code == -32_601
      assert error.reason == :method_not_found
      assert error.data[:original_message] == "Method not found"
    end

    test "handles transport error", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, _message ->
        {:error, :connection_closed}
      end)

      assert {:error,
              %Error{
                reason: :send_failure,
                data: %{type: :transport, original_reason: :connection_closed}
              }} = Hermes.Client.ping(client)
    end
  end

  describe "capability management" do
    test "merge_capabilities correctly merges capabilities" do
      expect(Hermes.MockTransport, :send_message, fn _, _message -> :ok end)

      client =
        start_supervised!(
          {Hermes.Client,
           transport: [layer: Hermes.MockTransport, name: Hermes.MockTransportImpl],
           client_info: %{"name" => "TestClient", "version" => "1.0.0"},
           capabilities: %{"roots" => %{}}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)

      initialize_client(client)

      new_capabilities = %{"sampling" => %{}}

      updated = Hermes.Client.merge_capabilities(client, new_capabilities)

      assert updated == %{"roots" => %{}, "sampling" => %{}}

      nested_capabilities = %{"roots" => %{"listChanged" => true}}

      final = Hermes.Client.merge_capabilities(client, nested_capabilities)

      assert final == %{"sampling" => %{}, "roots" => %{"listChanged" => true}}
    end
  end

  describe "server information" do
    setup do
      expect(Hermes.MockTransport, :send_message, 2, fn _, _message -> :ok end)

      client =
        start_supervised!(
          {Hermes.Client,
           transport: [layer: Hermes.MockTransport, name: Hermes.MockTransportImpl],
           client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)

      initialize_client(client)

      assert request_id = get_request_id(client, "initialize")

      init_response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "capabilities" => %{"resources" => %{"subscribe" => true}, "tools" => %{}},
          "serverInfo" => %{"name" => "TestServer", "version" => "1.0.0"},
          "protocolVersion" => "2024-11-05"
        }
      }

      send_response(client, init_response)

      Process.sleep(500)

      %{client: client}
    end

    test "get_server_capabilities returns server capabilities", %{client: client} do
      capabilities = Hermes.Client.get_server_capabilities(client)

      assert capabilities == %{
               "resources" => %{"subscribe" => true},
               "tools" => %{}
             }
    end

    test "get_server_info returns server info", %{client: client} do
      server_info = Hermes.Client.get_server_info(client)

      assert server_info == %{
               "name" => "TestServer",
               "version" => "1.0.0"
             }
    end
  end

  describe "progress tracking" do
    setup do
      expect(Hermes.MockTransport, :send_message, 2, fn _, _message -> :ok end)

      client =
        start_supervised!(
          {Hermes.Client,
           transport: [layer: Hermes.MockTransport, name: Hermes.MockTransportImpl],
           client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)

      initialize_client(client)

      assert request_id = get_request_id(client, "initialize")

      init_response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "capabilities" => %{"resources" => %{}, "tools" => %{}, "prompts" => %{}},
          "serverInfo" => %{"name" => "TestServer", "version" => "1.0.0"},
          "protocolVersion" => "2024-11-05"
        }
      }

      send_response(client, init_response)

      Process.sleep(50)

      %{client: client}
    end

    test "registers and calls progress callback when notification is received", %{client: client} do
      # Variables for progress tracking
      test_pid = self()
      progress_token = "test_progress_token"
      progress_value = 50
      total_value = 100

      # Register a callback
      :ok =
        Hermes.Client.register_progress_callback(client, progress_token, fn token, progress, total ->
          send(test_pid, {:progress_callback, token, progress, total})
        end)

      # Simulate receiving a progress notification
      progress_notification = %{
        "method" => "notifications/progress",
        "params" => %{
          "progressToken" => progress_token,
          "progress" => progress_value,
          "total" => total_value
        }
      }

      send_notification(client, progress_notification)

      # Verify callback was triggered with correct parameters
      assert_receive {:progress_callback, ^progress_token, ^progress_value, ^total_value}, 1000
    end

    test "unregisters progress callback", %{client: client} do
      # Variables for progress tracking
      test_pid = self()
      progress_token = "unregister_test_token"

      # Register callback
      :ok =
        Hermes.Client.register_progress_callback(client, progress_token, fn _, _, _ ->
          send(test_pid, :should_not_be_called)
        end)

      # Unregister callback
      :ok = Hermes.Client.unregister_progress_callback(client, progress_token)

      # Simulate receiving a progress notification
      progress_notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/progress",
        "params" => %{
          "progressToken" => progress_token,
          "progress" => 75,
          "total" => 100
        }
      }

      send_notification(client, progress_notification)

      # Verify callback was NOT triggered
      refute_receive :should_not_be_called, 500
    end

    test "request with progress token includes it in params", %{client: client} do
      progress_token = "request_token_test"

      # Set expectation for the message
      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/list"
        assert get_in(decoded, ["params", "_meta", "progressToken"]) == progress_token
        :ok
      end)

      # Make the request with progress token
      task =
        Task.async(fn ->
          Hermes.Client.list_resources(client, progress: [token: progress_token])
        end)

      Process.sleep(50)

      # Simulate a response to complete the request
      assert request_id = get_request_id(client, "resources/list")

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "resources" => [],
          "nextCursor" => nil
        }
      }

      send_response(client, response)

      # Ensure the task completes
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
    setup do
      expect(Hermes.MockTransport, :send_message, 2, fn _, _message -> :ok end)

      client =
        start_supervised!(
          {Hermes.Client,
           transport: [layer: Hermes.MockTransport, name: Hermes.MockTransportImpl],
           client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)

      # Initialize the client
      initialize_client(client)

      assert request_id = get_request_id(client, "initialize")

      init_response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "capabilities" => %{"resources" => %{}, "tools" => %{}, "logging" => %{}},
          "serverInfo" => %{"name" => "TestServer", "version" => "1.0.0"},
          "protocolVersion" => "2024-11-05"
        }
      }

      send_response(client, init_response)

      Process.sleep(50)

      %{client: client}
    end

    test "set_log_level sends the correct request", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "logging/setLevel"
        assert decoded["params"]["level"] == "info"
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.set_log_level(client, "info") end)

      Process.sleep(50)

      assert request_id = get_request_id(client, "logging/setLevel")

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{}
      }

      send_response(client, response)

      assert {:ok, %{}} = Task.await(task)
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

      # Register a callback
      :ok =
        Hermes.Client.register_log_callback(client, fn level, data, logger ->
          send(test_pid, {:log_callback, level, data, logger})
        end)

      # Create a log notification
      log_notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/message",
        "params" => %{
          "level" => "error",
          "data" => "Test error message",
          "logger" => "test-logger"
        }
      }

      send_notification(client, log_notification)

      # Verify the callback was triggered
      assert_receive {:log_callback, "error", "Test error message", "test-logger"}, 1000
    end
  end

  describe "notification handling" do
    test "sends initialized notification after init" do
      Hermes.MockTransport
      # the handle_continue
      |> expect(:send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "initialize"
        assert decoded["jsonrpc"] == "2.0"
        :ok
      end)
      # the send_notification
      |> expect(:send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "notifications/initialized"
        :ok
      end)

      client =
        start_supervised!(
          {Hermes.Client,
           transport: [layer: Hermes.MockTransport, name: Hermes.MockTransportImpl],
           client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)

      initialize_client(client)

      assert request_id = get_request_id(client, "initialize")

      init_response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "capabilities" => %{},
          "serverInfo" => %{"name" => "TestServer", "version" => "1.0.0"},
          "protocolVersion" => "2024-11-05"
        }
      }

      send_response(client, init_response)

      :sys.get_state(client)
    end
  end

  describe "cancellation" do
    setup do
      expect(Hermes.MockTransport, :send_message, 2, fn _, _message -> :ok end)

      client =
        start_supervised!(
          {Hermes.Client,
           transport: [layer: Hermes.MockTransport, name: Hermes.MockTransportImpl],
           client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)

      initialize_client(client)

      assert request_id = get_request_id(client, "initialize")

      init_response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "capabilities" => %{"resources" => %{}, "tools" => %{}},
          "serverInfo" => %{"name" => "TestServer", "version" => "1.0.0"},
          "protocolVersion" => "2024-11-05"
        }
      }

      send_response(client, init_response)

      Process.sleep(50)

      %{client: client}
    end

    test "handles cancelled notification from server", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "tools/call"
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.call_tool(client, "long_running_tool") end)

      Process.sleep(50)

      request_id = get_request_id(client, "tools/call")
      assert request_id != nil

      cancelled_notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/cancelled",
        "params" => %{
          "requestId" => request_id,
          "reason" => "server timeout"
        }
      }

      send_notification(client, cancelled_notification)

      assert {:error, error} = Task.await(task)
      assert error.reason == :request_cancelled
      assert error.data[:reason] == "server timeout"

      state = :sys.get_state(client)
      assert state.pending_requests[request_id] == nil
    end

    test "client can cancel a request", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/list"
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.list_resources(client) end)

      Process.sleep(50)

      request_id = get_request_id(client, "resources/list")
      assert request_id != nil

      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "notifications/cancelled"
        assert decoded["params"]["requestId"] == request_id
        assert decoded["params"]["reason"] == "test cancellation"
        :ok
      end)

      assert :ok = Hermes.Client.cancel_request(client, request_id, "test cancellation")

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
      expect(Hermes.MockTransport, :send_message, 2, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] in ["resources/list", "tools/list"]
        :ok
      end)

      # Start both requests
      task1 = Task.async(fn -> Hermes.Client.list_resources(client) end)
      task2 = Task.async(fn -> Hermes.Client.list_tools(client) end)

      Process.sleep(50)

      state = :sys.get_state(client)
      pending_count = map_size(state.pending_requests)
      assert pending_count == 2

      expect(Hermes.MockTransport, :send_message, 2, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "notifications/cancelled"
        assert decoded["params"]["reason"] == "batch cancellation"
        :ok
      end)

      {:ok, cancelled_requests} = Hermes.Client.cancel_all_requests(client, "batch cancellation")
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

      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/list"
        :ok
      end)

      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "notifications/cancelled"
        assert decoded["params"]["reason"] == "timeout"
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.list_resources(client, timeout: test_timeout) end)

      Process.sleep(test_timeout * 2)

      assert {:error, error} = Task.await(task)
      assert error.reason == :request_timeout

      state = :sys.get_state(client)
      assert map_size(state.pending_requests) == 0
    end

    test "client.close sends cancellation for pending requests", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/list"
        :ok
      end)

      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "notifications/cancelled"
        assert decoded["params"]["reason"] == "client closed"
        :ok
      end)

      expect(Hermes.MockTransport, :shutdown, fn _ -> :ok end)

      Process.flag(:trap_exit, true)
      %{pid: pid} = Task.async(fn -> Hermes.Client.list_resources(client) end)
      Process.sleep(50)

      assert get_request_id(client, "resources/list")

      Hermes.Client.close(client)

      Process.sleep(50)
      refute Process.alive?(client)

      operation = Operation.new(%{method: "resources/list"})

      assert_receive {:EXIT, ^pid, {:normal, {GenServer, :call, [_, {:operation, ^operation}, _]}}}
    end
  end

  defp initialize_client(client) do
    GenServer.cast(client, :initialize)
    # we need to force the initialization finish to proceed on tests
    # _ = :sys.get_state(client)
  end

  defp send_response(client, response) do
    assert {:ok, encoded} = Message.encode_response(response, response["id"])
    GenServer.cast(client, {:response, encoded})
  end

  defp send_notification(client, notification) do
    assert {:ok, encoded} = Message.encode_notification(notification)
    GenServer.cast(client, {:response, encoded})
  end

  defp send_error(client, error) do
    assert {:ok, encoded} = Message.encode_error(error, error["id"])
    GenServer.cast(client, {:response, encoded})
  end
end
