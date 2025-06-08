defmodule Hermes.Server.Transport.StreamableHTTPTest do
  use Hermes.MCP.Case, async: true

  alias Hermes.MCP.Message
  alias Hermes.Server.Transport.StreamableHTTP

  @moduletag capture_log: true

  describe "start_link/1" do
    test "starts with valid options" do
      server =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      name = :"test_streamable_http_#{System.unique_integer([:positive])}"

      assert {:ok, pid} = StreamableHTTP.start_link(server: server, name: name)
      assert Process.alive?(pid)
      assert Process.whereis(name) == pid
    end

    test "requires server option" do
      assert_raise Peri.InvalidSchema, fn ->
        StreamableHTTP.start_link(name: :test)
      end
    end

    test "requires name option" do
      server =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      assert_raise Peri.InvalidSchema, fn ->
        StreamableHTTP.start_link(server: server)
      end
    end
  end

  describe "with running transport" do
    setup do
      server =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      name = :"test_transport_#{System.unique_integer([:positive])}"
      {:ok, transport} = start_supervised({StreamableHTTP, server: server, name: name})

      %{transport: transport, server: server}
    end

    test "registers and unregisters SSE handlers", %{transport: transport} do
      session_id = "test-session-123"
      handler_pid = self()

      # Register handler
      assert :ok = StreamableHTTP.register_sse_handler(transport, session_id, handler_pid)

      # Get handler
      assert {:ok, ^handler_pid} = StreamableHTTP.get_sse_handler(transport, session_id)

      # Unregister handler
      assert :ok = StreamableHTTP.unregister_sse_handler(transport, session_id)

      # Handler should be gone
      assert {:error, :not_found} = StreamableHTTP.get_sse_handler(transport, session_id)
    end

    test "handles messages for SSE sessions", %{transport: transport} do
      session_id = "test-session-456"
      handler_pid = self()

      # Register handler
      assert :ok = StreamableHTTP.register_sse_handler(transport, session_id, handler_pid)

      # Send a message
      message = ~s|{"jsonrpc":"2.0","method":"ping","params":{},"id":"1"}|
      assert {:ok, response} = StreamableHTTP.handle_message_for_sse(transport, session_id, message)

      # Should receive the response through SSE
      assert_receive {:sse_data, ^response}
    end

    test "routes messages to sessions", %{transport: transport} do
      session_id = "test-session-789"
      handler_pid = self()

      # Register handler
      assert :ok = StreamableHTTP.register_sse_handler(transport, session_id, handler_pid)

      # Route a message
      message = "test message"
      assert :ok = StreamableHTTP.route_to_session(transport, session_id, message)

      # Should receive the message
      assert_receive {:sse_data, ^message}
    end

    test "cleans up handlers when they crash", %{transport: transport} do
      session_id = "test-session-crash"

      # Spawn a handler that will crash
      handler_pid =
        spawn(fn ->
          receive do
            :crash -> exit(:boom)
          end
        end)

      # Register handler
      assert :ok = StreamableHTTP.register_sse_handler(transport, session_id, handler_pid)

      # Verify it's registered
      assert {:ok, ^handler_pid} = StreamableHTTP.get_sse_handler(transport, session_id)

      # Crash the handler
      send(handler_pid, :crash)
      Process.sleep(50)

      # Handler should be automatically removed
      assert {:error, :not_found} = StreamableHTTP.get_sse_handler(transport, session_id)
    end

    test "send_message/2 works", %{transport: transport} do
      message = "test message"
      assert :ok = StreamableHTTP.send_message(transport, message)
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
