defmodule Hermes.Server.Transport.StreamableHTTPTest do
  use Hermes.MCP.Case, async: false

  import ExUnit.CaptureLog

  alias Hermes.Server.Transport.StreamableHTTP

  setup :with_default_registry

  describe "start_link/1" do
    test "starts with valid options" do
      server = Hermes.Server.Registry.server(StubServer)
      name = Hermes.Server.Registry.transport(StubServer, :streamable_http)
      sup = Hermes.Server.Registry.task_supervisor(StubServer)

      assert {:ok, pid} =
               StreamableHTTP.start_link(server: server, name: name, task_supervisor: sup)

      assert Process.alive?(pid)

      assert Hermes.Server.Registry.whereis_transport(StubServer, :streamable_http) ==
               pid
    end

    test "requires server option" do
      assert_raise Peri.InvalidSchema, fn ->
        StreamableHTTP.start_link(name: :test)
      end
    end
  end

  describe "with running transport" do
    setup do
      registry = Hermes.Server.Registry
      name = registry.transport(StubServer, :streamable_http)
      sup = registry.task_supervisor(StubServer)
      start_supervised!({Task.Supervisor, name: sup})

      {:ok, transport} =
        start_supervised({StreamableHTTP, server: StubServer, name: name, registry: registry, task_supervisor: sup})

      %{transport: transport, server: StubServer}
    end

    test "registers and unregisters SSE handlers", %{transport: transport} do
      session_id = "test-session-123"
      handler_pid = self()

      assert :ok = StreamableHTTP.register_sse_handler(transport, session_id)
      assert ^handler_pid = StreamableHTTP.get_sse_handler(transport, session_id)
      assert :ok = StreamableHTTP.unregister_sse_handler(transport, session_id)
      refute StreamableHTTP.get_sse_handler(transport, session_id)
    end

    test "handle_message_for_sse fails when server is not in registry", %{
      transport: transport
    } do
      session_id = "test-session-456"

      assert :ok = StreamableHTTP.register_sse_handler(transport, session_id)
      message = build_request("ping", %{})

      StreamableHTTP.handle_message_for_sse(transport, session_id, message, %{})

      # Clean up to avoid logs after test ends
      capture_log(fn ->
        StreamableHTTP.unregister_sse_handler(transport, session_id)
        Process.sleep(10)
      end)
    end

    test "routes messages to sessions", %{transport: transport} do
      session_id = "test-session-789"

      assert :ok = StreamableHTTP.register_sse_handler(transport, session_id)

      message = "test message"
      assert :ok = StreamableHTTP.route_to_session(transport, session_id, message)

      assert_receive {:sse_message, ^message}

      # Clean up to avoid logs after test ends
      capture_log(fn ->
        StreamableHTTP.unregister_sse_handler(transport, session_id)
        Process.sleep(10)
      end)
    end

    test "cleans up handlers when they crash", %{transport: transport} do
      session_id = "test-session-crash"
      test_pid = self()

      capture_log(fn ->
        handler_pid =
          spawn(fn ->
            StreamableHTTP.register_sse_handler(transport, session_id)
            send(test_pid, :registered)

            receive do
              :crash -> exit(:boom)
            end
          end)

        assert_receive :registered, 1000

        handler = StreamableHTTP.get_sse_handler(transport, session_id)
        assert is_pid(handler)

        send(handler_pid, :crash)
        Process.sleep(100)

        refute StreamableHTTP.get_sse_handler(transport, session_id)
      end)
    end

    test "send_message/2 works", %{transport: transport} do
      message = "test message"
      assert :ok = StreamableHTTP.send_message(transport, message, [])
    end

    test "shutdown/1 gracefully shuts down", %{transport: transport} do
      assert Process.alive?(transport)
      assert :ok = StreamableHTTP.shutdown(transport)
      Process.sleep(100)
      refute Process.alive?(transport)
    end
  end

  describe "supported_protocol_versions/0" do
    test "returns supported versions" do
      versions = StreamableHTTP.supported_protocol_versions()
      assert is_list(versions)
      assert "2025-03-26" in versions
    end
  end
end
