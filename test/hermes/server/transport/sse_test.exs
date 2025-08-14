defmodule Hermes.Server.Transport.SSETest do
  use Hermes.MCP.Case, async: false

  import ExUnit.CaptureLog

  alias Hermes.Server.Transport.SSE

  setup :with_default_registry

  describe "start_link/1" do
    test "starts with valid options" do
      server = :"test_server_#{System.unique_integer([:positive])}"
      name = :"test_transport_#{System.unique_integer([:positive])}"

      assert {:ok, pid} = SSE.start_link(server: server, name: name)
      assert Process.alive?(pid)
    end

    test "starts with optional base_url and post_path" do
      server = :"test_server_#{System.unique_integer([:positive])}"
      name = :"test_transport_#{System.unique_integer([:positive])}"

      assert {:ok, pid} =
               SSE.start_link(
                 server: server,
                 name: name,
                 base_url: "http://localhost:8080",
                 post_path: "/custom/messages"
               )

      assert Process.alive?(pid)
    end

    test "requires server option" do
      assert_raise Peri.InvalidSchema, fn ->
        SSE.start_link(name: :test)
      end
    end

    test "requires name option" do
      assert_raise Peri.InvalidSchema, fn ->
        SSE.start_link(server: StubServer)
      end
    end
  end

  describe "with running transport" do
    setup do
      registry = Hermes.Server.Registry
      name = registry.transport(StubServer, :sse)

      {:ok, transport} =
        start_supervised({SSE, server: StubServer, name: name, registry: registry})

      %{transport: transport, server: StubServer}
    end

    test "registers and unregisters SSE handlers", %{transport: transport} do
      session_id = "test-session-123"
      handler_pid = self()

      assert :ok = SSE.register_sse_handler(transport, session_id)
      assert ^handler_pid = SSE.get_sse_handler(transport, session_id)
      assert :ok = SSE.unregister_sse_handler(transport, session_id)
      refute SSE.get_sse_handler(transport, session_id)
    end

    test "handle_message processes notifications", %{transport: transport} do
      session_id = "test-session-456"

      notification =
        build_notification("notifications/message", %{
          "level" => "info",
          "data" => "test"
        })

      # Should return nil for notifications and send them to server
      assert {:ok, nil} =
               SSE.handle_message(transport, session_id, notification, %{})
    end

    test "routes messages to specific sessions", %{transport: transport} do
      session_id = "test-session-789"

      assert :ok = SSE.register_sse_handler(transport, session_id)

      message = "test message"
      assert :ok = SSE.route_to_session(transport, session_id, message)

      assert_receive {:sse_message, ^message}

      # Clean up to avoid logs after test ends
      capture_log(fn ->
        SSE.unregister_sse_handler(transport, session_id)
        Process.sleep(10)
      end)
    end

    test "route_to_session fails when no handler exists", %{transport: transport} do
      session_id = "nonexistent-session"
      message = "test message"

      assert {:error, :no_sse_handler} =
               SSE.route_to_session(transport, session_id, message)
    end

    test "broadcasts messages to all handlers", %{transport: transport} do
      session1 = "session-1"
      session2 = "session-2"

      # Register two handlers
      assert :ok = SSE.register_sse_handler(transport, session1)

      # Second handler in a different process
      test_pid = self()

      spawn(fn ->
        SSE.register_sse_handler(transport, session2)
        send(test_pid, :registered)

        receive do
          {:sse_message, msg} -> send(test_pid, {:handler2_received, msg})
        end
      end)

      assert_receive :registered, 1000

      message = "broadcast message"
      assert :ok = SSE.send_message(transport, message, [])

      # Both handlers should receive the message
      assert_receive {:sse_message, ^message}
      assert_receive {:handler2_received, ^message}

      # Clean up to avoid logs after test ends
      capture_log(fn ->
        SSE.unregister_sse_handler(transport, session1)
        SSE.unregister_sse_handler(transport, session2)
        Process.sleep(10)
      end)
    end

    test "cleans up handlers when they crash", %{transport: transport} do
      session_id = "test-session-crash"
      test_pid = self()

      capture_log(fn ->
        handler_pid =
          spawn(fn ->
            SSE.register_sse_handler(transport, session_id)
            send(test_pid, :registered)

            receive do
              :crash -> exit(:boom)
            end
          end)

        assert_receive :registered, 1000

        handler = SSE.get_sse_handler(transport, session_id)
        assert is_pid(handler)

        send(handler_pid, :crash)
        Process.sleep(100)

        refute SSE.get_sse_handler(transport, session_id)
      end)
    end

    test "get_endpoint_url returns correct URL", %{transport: transport} do
      assert "/messages" = SSE.get_endpoint_url(transport)
    end

    test "get_endpoint_url with custom base_url and post_path" do
      registry = Hermes.Server.Registry
      name = :custom_sse_transport

      {:ok, transport} =
        start_supervised(
          {SSE,
           server: StubServer,
           name: name,
           base_url: "http://localhost:8080",
           post_path: "/api/messages",
           registry: registry},
          id: :custom_sse
        )

      assert "http://localhost:8080/api/messages" = SSE.get_endpoint_url(transport)
    end

    test "shutdown/1 gracefully shuts down", %{transport: transport} do
      session_id = "shutdown-test"

      # Register a handler
      assert :ok = SSE.register_sse_handler(transport, session_id)

      assert Process.alive?(transport)
      assert :ok = SSE.shutdown(transport)

      # Should send close message to handler
      assert_receive :close_sse

      Process.sleep(100)
      refute Process.alive?(transport)
    end
  end

  describe "supported_protocol_versions/0" do
    test "supports 2024-11-05 protocol version" do
      assert ["2024-11-05"] = SSE.supported_protocol_versions()
    end
  end
end
