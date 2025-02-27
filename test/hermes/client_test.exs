defmodule Hermes.ClientTest do
  use ExUnit.Case, async: false

  import Mox

  @moduletag capture_log: true

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Mox.stub_with(Hermes.MockTransport, Hermes.MockTransportImpl)

    :ok
  end

  describe "start_link/1" do
    test "starts the client with proper initialization" do
      expect(Hermes.MockTransport, :send_message, fn message ->
        assert String.contains?(message, "initialize")
        assert String.contains?(message, "protocolVersion")
        assert String.contains?(message, "capabilities")
        assert String.contains?(message, "clientInfo")
        :ok
      end)

      client =
        start_supervised!(
          {Hermes.Client,
           transport: Hermes.MockTransport,
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
      expect(Hermes.MockTransport, :send_message, 2, fn _message -> :ok end)

      client =
        start_supervised!(
          {Hermes.Client,
           transport: Hermes.MockTransport,
           client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)

      Process.send(client, :initialize, [:noconnect])
      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_pid, "initialize"}}] = state.pending_requests |> Map.to_list()

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

      Process.sleep(50)

      %{client: client}
    end

    test "ping sends correct request", %{client: client} do
      expect(Hermes.MockTransport, :send_message, fn message ->
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
      [{request_id, {_from, "ping"}}] = state.pending_requests |> Map.to_list()

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
      expect(Hermes.MockTransport, :send_message, fn message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/list"
        assert decoded["params"] == %{}
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.list_resources(client) end)

      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_from, "resources/list"}}] = state.pending_requests |> Map.to_list()

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
      expect(Hermes.MockTransport, :send_message, fn message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/list"
        assert decoded["params"] == %{"cursor" => "next-page"}
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.list_resources(client, cursor: "next-page") end)

      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_from, "resources/list"}}] = state.pending_requests |> Map.to_list()

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
      expect(Hermes.MockTransport, :send_message, fn message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "resources/read"
        assert decoded["params"] == %{"uri" => "test://uri"}
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.read_resource(client, "test://uri") end)

      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_from, "resources/read"}}] = state.pending_requests |> Map.to_list()

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
      expect(Hermes.MockTransport, :send_message, fn message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "prompts/list"
        assert decoded["params"] == %{}
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.list_prompts(client) end)

      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_from, "prompts/list"}}] = state.pending_requests |> Map.to_list()

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
      expect(Hermes.MockTransport, :send_message, fn message ->
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
      [{request_id, {_from, "prompts/get"}}] = state.pending_requests |> Map.to_list()

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
      expect(Hermes.MockTransport, :send_message, fn message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "tools/list"
        assert decoded["params"] == %{}
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.list_tools(client) end)

      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_from, "tools/list"}}] = state.pending_requests |> Map.to_list()

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
      expect(Hermes.MockTransport, :send_message, fn message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "tools/call"
        assert decoded["params"] == %{"name" => "test_tool", "arguments" => %{"arg1" => "value1"}}
        :ok
      end)

      task =
        Task.async(fn -> Hermes.Client.call_tool(client, "test_tool", %{"arg1" => "value1"}) end)

      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_from, "tools/call"}}] = state.pending_requests |> Map.to_list()

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

  describe "error handling" do
    setup do
      expect(Hermes.MockTransport, :send_message, 2, fn _message -> :ok end)

      client =
        start_supervised!(
          {Hermes.Client,
           transport: Hermes.MockTransport,
           client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)

      Process.send(client, :initialize, [:noconnect])
      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_pid, "initialize"}}] = state.pending_requests |> Map.to_list()

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
      expect(Hermes.MockTransport, :send_message, fn message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "ping"
        :ok
      end)

      task = Task.async(fn -> Hermes.Client.ping(client) end)

      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_from, "ping"}}] = state.pending_requests |> Map.to_list()

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
      expect(Hermes.MockTransport, :send_message, fn _message ->
        {:error, :connection_closed}
      end)

      assert {:error, {:transport_error, :connection_closed}} = Hermes.Client.ping(client)
    end
  end

  describe "capability management" do
    test "merge_capabilities correctly merges capabilities" do
      expect(Hermes.MockTransport, :send_message, fn _message -> :ok end)

      client =
        start_supervised!(
          {Hermes.Client,
           transport: Hermes.MockTransport,
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
      expect(Hermes.MockTransport, :send_message, 2, fn _message -> :ok end)

      client =
        start_supervised!(
          {Hermes.Client,
           transport: Hermes.MockTransport,
           client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)

      Process.send(client, :initialize, [:noconnect])
      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_pid, "initialize"}}] = state.pending_requests |> Map.to_list()

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

  describe "notification handling" do
    test "sends initialized notification after init" do
      Hermes.MockTransport
      # the handle_continue
      |> expect(:send_message, fn message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "initialize"
        assert decoded["jsonrpc"] == "2.0"
        :ok
      end)
      # the send_notification
      |> expect(:send_message, fn message ->
        decoded = JSON.decode!(message)
        assert decoded["method"] == "notifications/initialized"
        :ok
      end)

      client =
        start_supervised!(
          {Hermes.Client,
           transport: Hermes.MockTransport,
           client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
          restart: :temporary
        )

      allow(Hermes.MockTransport, self(), client)

      Process.send(client, :initialize, [:noconnect])
      Process.sleep(50)

      state = :sys.get_state(client)
      [{request_id, {_pid, "initialize"}}] = state.pending_requests |> Map.to_list()

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
