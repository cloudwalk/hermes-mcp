defmodule Hermes.ClientTest do
  use ExUnit.Case, async: false

  import Mox

  alias Hermes.Message

  @moduletag capture_log: true

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Mox.stub_with(Hermes.MockTransport, Hermes.MockTransportImpl)

    :ok
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
      Process.send(client, :initialize, [:noconnect])
      Process.sleep(50)

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

      Process.send(client, :initialize, [:noconnect])
      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_pid, "initialize"}}] = Map.to_list(state.pending_requests)

      init_response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "capabilities" => %{"resources" => %{}, "tools" => %{}, "prompts" => %{}},
          "serverInfo" => %{"name" => "TestServer", "version" => "1.0.0"},
          "protocolVersion" => "2024-11-05"
        }
      }

      encoded_response = JSON.encode!(init_response)
      send(client, {:response, encoded_response})

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

      state = :sys.get_state(client)
      [{request_id, {_from, "ping"}}] = Map.to_list(state.pending_requests)

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{}
      }

      encoded_response = JSON.encode!(response)
      send(client, {:response, encoded_response})

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

      state = :sys.get_state(client)
      [{request_id, {_from, "resources/list"}}] = Map.to_list(state.pending_requests)

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "resources" => [%{"name" => "test", "uri" => "test://uri"}],
          "nextCursor" => nil
        }
      }

      encoded_response = JSON.encode!(response)
      send(client, {:response, encoded_response})

      expected_result = %{
        "resources" => [%{"name" => "test", "uri" => "test://uri"}],
        "nextCursor" => nil
      }

      assert {:ok, ^expected_result} = Task.await(task)
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

      state = :sys.get_state(client)
      [{request_id, {_from, "resources/list"}}] = Map.to_list(state.pending_requests)

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "resources" => [%{"name" => "test2", "uri" => "test://uri2"}],
          "nextCursor" => nil
        }
      }

      encoded_response = JSON.encode!(response)
      send(client, {:response, encoded_response})

      expected_result = %{
        "resources" => [%{"name" => "test2", "uri" => "test://uri2"}],
        "nextCursor" => nil
      }

      assert {:ok, ^expected_result} = Task.await(task)
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

      state = :sys.get_state(client)
      [{request_id, {_from, "resources/read"}}] = Map.to_list(state.pending_requests)

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "contents" => [%{"text" => "resource content", "uri" => "test://uri"}]
        }
      }

      encoded_response = JSON.encode!(response)
      send(client, {:response, encoded_response})

      expected_result = %{
        "contents" => [%{"text" => "resource content", "uri" => "test://uri"}]
      }

      assert {:ok, ^expected_result} = Task.await(task)
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

      state = :sys.get_state(client)
      [{request_id, {_from, "prompts/list"}}] = Map.to_list(state.pending_requests)

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "prompts" => [%{"name" => "test_prompt"}],
          "nextCursor" => nil
        }
      }

      encoded_response = JSON.encode!(response)
      send(client, {:response, encoded_response})

      expected_result = %{
        "prompts" => [%{"name" => "test_prompt"}],
        "nextCursor" => nil
      }

      assert {:ok, ^expected_result} = Task.await(task)
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

      state = :sys.get_state(client)
      [{request_id, {_from, "prompts/get"}}] = Map.to_list(state.pending_requests)

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "messages" => [%{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}]
        }
      }

      encoded_response = JSON.encode!(response)
      send(client, {:response, encoded_response})

      expected_result = %{
        "messages" => [%{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}]
      }

      assert {:ok, ^expected_result} = Task.await(task)
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

      state = :sys.get_state(client)
      [{request_id, {_from, "tools/list"}}] = Map.to_list(state.pending_requests)

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "tools" => [%{"name" => "test_tool"}],
          "nextCursor" => nil
        }
      }

      encoded_response = JSON.encode!(response)
      send(client, {:response, encoded_response})

      expected_result = %{
        "tools" => [%{"name" => "test_tool"}],
        "nextCursor" => nil
      }

      assert {:ok, ^expected_result} = Task.await(task)
    end

    test "call_tool sends correct request", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "tools/call"
        assert decoded["params"] == %{"name" => "test_tool", "arguments" => %{"arg1" => "value1"}}
        :ok
      end)

      task =
        Task.async(fn -> Hermes.Client.call_tool(client, "test_tool", %{"arg1" => "value1"}) end)

      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_from, "tools/call"}}] = Map.to_list(state.pending_requests)

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "content" => [%{"type" => "text", "text" => "Tool result"}],
          "isError" => false
        }
      }

      encoded_response = JSON.encode!(response)
      send(client, {:response, encoded_response})

      expected_result = %{
        "content" => [%{"type" => "text", "text" => "Tool result"}],
        "isError" => false
      }

      assert {:ok, ^expected_result} = Task.await(task)
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

      Process.send(client, :initialize, [:noconnect])
      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_pid, "initialize"}}] = Map.to_list(state.pending_requests)

      init_response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "capabilities" => %{"prompts" => %{}},
          "serverInfo" => %{"name" => "TestServer", "version" => "1.0.0"},
          "protocolVersion" => "2024-11-05"
        }
      }

      encoded_response = JSON.encode!(init_response)
      send(client, {:response, encoded_response})

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

      state = :sys.get_state(client)
      [{request_id, {_from, "ping"}}] = Map.to_list(state.pending_requests)

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{}
      }

      encoded_response = JSON.encode!(response)
      send(client, {:response, encoded_response})

      assert :pong = Task.await(task)
    end

    test "tools/list fails since this capability isn't supported", %{client: client} do
      task = Task.async(fn -> Hermes.Client.list_tools(client) end)

      assert {:error, {:capability_not_supported, "tools/list"}} = Task.await(task)
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

      Process.send(client, :initialize, [:noconnect])
      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_pid, "initialize"}}] = Map.to_list(state.pending_requests)

      init_response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "capabilities" => %{"resources" => %{}, "tools" => %{}},
          "serverInfo" => %{"name" => "TestServer", "version" => "1.0.0"},
          "protocolVersion" => "2024-11-05"
        }
      }

      encoded_response = JSON.encode!(init_response)
      send(client, {:response, encoded_response})

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

      state = :sys.get_state(client)
      [{request_id, {_from, "ping"}}] = Map.to_list(state.pending_requests)

      error_response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "error" => %{
          "code" => -32_601,
          "message" => "Method not found"
        }
      }

      encoded_response = JSON.encode!(error_response)
      send(client, {:response, encoded_response})

      expected_error = %{"code" => -32_601, "message" => "Method not found"}
      assert {:error, ^expected_error} = Task.await(task)
    end

    test "handles transport error", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn _, _message ->
        {:error, :connection_closed}
      end)

      assert {:error, {:transport_error, :connection_closed}} = Hermes.Client.ping(client)
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
           capabilities: %{"resources" => %{}}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)

      Process.send(client, :initialize, [:noconnect])
      Process.sleep(50)

      new_capabilities = %{"tools" => %{"listChanged" => true}}

      updated = Hermes.Client.merge_capabilities(client, new_capabilities)

      assert updated == %{"resources" => %{}, "tools" => %{"listChanged" => true}}

      nested_capabilities = %{"resources" => %{"subscribe" => true}}

      final = Hermes.Client.merge_capabilities(client, nested_capabilities)

      assert final == %{
               "resources" => %{"subscribe" => true},
               "tools" => %{"listChanged" => true}
             }
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

      Process.send(client, :initialize, [:noconnect])
      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_pid, "initialize"}}] = Map.to_list(state.pending_requests)

      init_response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "capabilities" => %{"resources" => %{"subscribe" => true}, "tools" => %{}},
          "serverInfo" => %{"name" => "TestServer", "version" => "1.0.0"},
          "protocolVersion" => "2024-11-05"
        }
      }

      encoded_response = JSON.encode!(init_response)
      send(client, {:response, encoded_response})

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

      Process.send(client, :initialize, [:noconnect])
      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_pid, "initialize"}}] = Map.to_list(state.pending_requests)

      init_response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "capabilities" => %{"resources" => %{}, "tools" => %{}, "prompts" => %{}},
          "serverInfo" => %{"name" => "TestServer", "version" => "1.0.0"},
          "protocolVersion" => "2024-11-05"
        }
      }

      encoded_response = JSON.encode!(init_response)
      send(client, {:response, encoded_response})

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

      assert {:ok, encoded_notification} = Message.encode_notification(progress_notification)
      send(client, {:response, encoded_notification})

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

      encoded_notification = JSON.encode!(progress_notification) <> "\n"
      send(client, {:response, encoded_notification})

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
      state = :sys.get_state(client)
      [{request_id, {_from, "resources/list"}}] = Map.to_list(state.pending_requests)

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "resources" => [],
          "nextCursor" => nil
        }
      }

      encoded_response = JSON.encode!(response)
      send(client, {:response, encoded_response})

      # Ensure the task completes
      assert {:ok, _} = Task.await(task)
    end

    test "generates unique progress tokens" do
      token1 = Hermes.Message.generate_progress_token()
      token2 = Hermes.Message.generate_progress_token()

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
      Process.send(client, :initialize, [:noconnect])
      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_pid, "initialize"}}] = Map.to_list(state.pending_requests)

      init_response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "capabilities" => %{"resources" => %{}, "tools" => %{}, "logging" => %{}},
          "serverInfo" => %{"name" => "TestServer", "version" => "1.0.0"},
          "protocolVersion" => "2024-11-05"
        }
      }

      encoded_response = JSON.encode!(init_response)
      send(client, {:response, encoded_response})

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

      state = :sys.get_state(client)
      [{request_id, {_from, "logging/setLevel"}}] = Map.to_list(state.pending_requests)

      response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{}
      }

      encoded_response = JSON.encode!(response)
      send(client, {:response, encoded_response})

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

      :ok = Hermes.Client.register_log_callback(client, callback)
      :ok = Hermes.Client.unregister_log_callback(client, callback)

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

      encoded_notification = JSON.encode!(log_notification) <> "\n"
      send(client, {:response, encoded_notification})

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

      Process.send(client, :initialize, [:noconnect])
      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_pid, "initialize"}}] = Map.to_list(state.pending_requests)

      init_response = %{
        "id" => request_id,
        "jsonrpc" => "2.0",
        "result" => %{
          "capabilities" => %{},
          "serverInfo" => %{"name" => "TestServer", "version" => "1.0.0"},
          "protocolVersion" => "2024-11-05"
        }
      }

      encoded_response = JSON.encode!(init_response)
      send(client, {:response, encoded_response})

      :sys.get_state(client)
    end
  end
end
