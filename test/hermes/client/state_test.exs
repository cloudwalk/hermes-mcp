defmodule Hermes.Client.StateTest do
  use ExUnit.Case, async: true

  alias Hermes.Client.Operation
  alias Hermes.Client.Request
  alias Hermes.Client.State
  alias Hermes.MCP.Error

  describe "new/1" do
    test "creates a new state with the given options" do
      opts = %{
        client_info: %{"name" => "TestClient", "version" => "1.0.0"},
        capabilities: %{"resources" => %{}},
        protocol_version: "2024-11-05",
        transport: %{layer: :fake_transport, name: :fake_name}
      }

      state = State.new(opts)

      assert state.client_info == %{"name" => "TestClient", "version" => "1.0.0"}
      assert state.capabilities == %{"resources" => %{}}
      assert state.protocol_version == "2024-11-05"
      assert state.transport == %{layer: :fake_transport, name: :fake_name}
      assert state.pending_requests == %{}
      assert state.progress_callbacks == %{}
      assert state.log_callback == nil
    end
  end

  describe "add_request_from_operation/3" do
    test "adds a request to the state" do
      state = new_test_state()
      from = {self(), make_ref()}

      operation =
        Operation.new(%{
          method: "test_method"
        })

      {request_id, updated_state} =
        State.add_request_from_operation(state, operation, from)

      assert is_binary(request_id)
      assert Map.has_key?(updated_state.pending_requests, request_id)

      request = updated_state.pending_requests[request_id]

      assert %Request{} = request
      assert request.from == from
      assert request.method == "test_method"
      assert is_reference(request.timer_ref)
      assert is_integer(request.start_time)
    end
  end

  describe "get_request/2" do
    test "returns the request if it exists" do
      state = new_test_state()
      from = {self(), make_ref()}

      operation = Operation.new(%{method: "test_method"})

      {request_id, state} = State.add_request_from_operation(state, operation, from)

      result = State.get_request(state, request_id)

      assert %Request{} = result
      assert result.from == from
      assert result.method == "test_method"
    end

    test "returns nil if the request doesn't exist" do
      state = new_test_state()

      assert State.get_request(state, "nonexistent_id") == nil
    end
  end

  describe "remove_request/2" do
    test "removes a request and returns its info" do
      state = new_test_state()
      from = {self(), make_ref()}

      operation = Operation.new(%{method: "test_method"})

      {request_id, state} = State.add_request_from_operation(state, operation, from)

      {request, updated_state} = State.remove_request(state, request_id)

      assert %Request{} = request
      assert request.from == from
      assert request.method == "test_method"
      assert updated_state.pending_requests == %{}
    end

    test "returns nil if the request doesn't exist" do
      state = new_test_state()

      {result, updated_state} = State.remove_request(state, "nonexistent_id")

      assert result == nil
      assert updated_state == state
    end
  end

  describe "handle_request_timeout/2" do
    test "handles a request timeout" do
      state = new_test_state()
      from = {self(), make_ref()}

      operation = Operation.new(%{method: "test_method"})

      {request_id, state} = State.add_request_from_operation(state, operation, from)

      {request, updated_state} = State.handle_request_timeout(state, request_id)

      assert %Request{} = request
      assert request.from == from
      assert request.method == "test_method"
      assert updated_state.pending_requests == %{}
    end

    test "returns nil if the request doesn't exist" do
      state = new_test_state()

      {result, updated_state} = State.handle_request_timeout(state, "nonexistent_id")

      assert result == nil
      assert updated_state == state
    end
  end

  describe "progress callback management" do
    test "register_progress_callback/3 registers a callback" do
      state = new_test_state()
      token = "test_token"
      callback = fn _, _, _ -> :ok end

      updated_state = State.register_progress_callback(state, token, callback)

      assert Map.has_key?(updated_state.progress_callbacks, token)
      assert updated_state.progress_callbacks[token] == callback
    end

    test "get_progress_callback/2 returns the callback" do
      state = new_test_state()
      token = "test_token"
      callback = fn _, _, _ -> :ok end
      state = State.register_progress_callback(state, token, callback)

      result = State.get_progress_callback(state, token)

      assert result == callback
    end

    test "get_progress_callback/2 returns nil if no callback is registered" do
      state = new_test_state()

      assert State.get_progress_callback(state, "nonexistent_token") == nil
    end

    test "unregister_progress_callback/2 removes the callback" do
      state = new_test_state()
      token = "test_token"
      callback = fn _, _, _ -> :ok end
      state = State.register_progress_callback(state, token, callback)

      updated_state = State.unregister_progress_callback(state, token)

      assert not Map.has_key?(updated_state.progress_callbacks, token)
    end
  end

  describe "log callback management" do
    test "set_log_callback/2 sets the callback" do
      state = new_test_state()
      callback = fn _, _, _ -> :ok end

      updated_state = State.set_log_callback(state, callback)

      assert updated_state.log_callback == callback
    end

    test "clear_log_callback/1 clears the callback" do
      state = new_test_state()
      callback = fn _, _, _ -> :ok end
      state = State.set_log_callback(state, callback)

      updated_state = State.clear_log_callback(state)

      assert updated_state.log_callback == nil
    end

    test "get_log_callback/1 returns the callback" do
      state = new_test_state()
      callback = fn _, _, _ -> :ok end
      state = State.set_log_callback(state, callback)

      result = State.get_log_callback(state)

      assert result == callback
    end
  end

  describe "update_server_info/3" do
    test "updates server capabilities and info" do
      state = new_test_state()
      capabilities = %{"resources" => %{}, "tools" => %{}}
      server_info = %{"name" => "TestServer", "version" => "1.0.0"}

      updated_state = State.update_server_info(state, capabilities, server_info)

      assert updated_state.server_capabilities == capabilities
      assert updated_state.server_info == server_info
    end
  end

  describe "list_pending_requests/1" do
    test "returns a list of pending requests" do
      state = new_test_state()
      from = {self(), make_ref()}

      operation = Operation.new(%{method: "test_method"})

      {request_id, state} = State.add_request_from_operation(state, operation, from)

      requests = State.list_pending_requests(state)

      assert length(requests) == 1
      request = hd(requests)
      assert %Request{} = request
      assert request.id == request_id
      assert request.method == "test_method"
    end

    test "returns an empty list if there are no pending requests" do
      state = new_test_state()

      assert State.list_pending_requests(state) == []
    end
  end

  describe "server capabilities and info" do
    test "get_server_capabilities/1 returns the server capabilities" do
      state = new_test_state()
      capabilities = %{"resources" => %{}, "tools" => %{}}
      state = %{state | server_capabilities: capabilities}

      assert State.get_server_capabilities(state) == capabilities
    end

    test "get_server_info/1 returns the server info" do
      state = new_test_state()
      server_info = %{"name" => "TestServer", "version" => "1.0.0"}
      state = %{state | server_info: server_info}

      assert State.get_server_info(state) == server_info
    end
  end

  describe "merge_capabilities/2" do
    test "merges additional capabilities" do
      state = new_test_state()
      state = %{state | capabilities: %{"resources" => %{}}}

      updated_state =
        State.merge_capabilities(state, %{"tools" => %{"execute" => true}})

      assert updated_state.capabilities == %{
               "resources" => %{},
               "tools" => %{"execute" => true}
             }
    end

    test "deeply merges nested capabilities" do
      state = new_test_state()
      state = %{state | capabilities: %{"resources" => %{"list" => true}}}

      updated_state =
        State.merge_capabilities(state, %{"resources" => %{"read" => true}})

      assert updated_state.capabilities == %{
               "resources" => %{"list" => true, "read" => true}
             }
    end
  end

  describe "validate_capability/2" do
    test "returns :ok for ping method" do
      state = new_test_state()
      state = %{state | server_capabilities: %{}}

      assert State.validate_capability(state, "ping") == :ok
    end

    test "returns :ok for initialize method" do
      state = new_test_state()
      state = %{state | server_capabilities: %{}}

      assert State.validate_capability(state, "initialize") == :ok
    end

    test "returns :ok for supported capability" do
      state = new_test_state()
      state = %{state | server_capabilities: %{"resources" => %{}}}

      assert State.validate_capability(state, "resources/list") == :ok
    end

    test "returns error for unsupported capability" do
      state = new_test_state()
      state = %{state | server_capabilities: %{"resources" => %{}}}

      assert {:error, %Error{reason: :method_not_found, data: %{method: "tools/list"}}} =
               State.validate_capability(state, "tools/list")
    end

    test "returns error when server capabilities are not set" do
      state = new_test_state()

      assert {:error, %Error{reason: :internal_error}} =
               State.validate_capability(state, "resources/list")
    end
  end

  # Helper functions

  defp new_test_state do
    %State{
      client_info: %{"name" => "TestClient", "version" => "1.0.0"},
      capabilities: %{},
      protocol_version: "2024-11-05",
      transport: %{layer: :fake_transport, name: :fake_name}
    }
  end
end
