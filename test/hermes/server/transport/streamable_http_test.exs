defmodule Hermes.Server.Transport.StreamableHTTPTest do
  use MCPTest.Case, async: true

  alias Hermes.Server.Registry
  alias Hermes.Server.Transport.StreamableHTTP

  setup do
    start_supervised!({TestServer, transport: {:streamable_http, []}})

    %{
      transport: Registry.whereis_transport(TestServer, :streamable_http),
      server: Registry.whereis_server(TestServer),
      server_module: TestServer
    }
  end

  describe "StreamableHTTP transport" do
    test "is properly registered", %{transport: transport} do
      assert is_pid(transport)
      assert Process.alive?(transport)
    end

    test "has correct process info", %{transport: transport} do
      info = Process.info(transport)
      assert info[:status] in [:waiting, :running]
    end
  end

  describe "register_sse_handler/2" do
    test "registers SSE handler for session", %{transport: transport} do
      session_id = "test-session-#{System.unique_integer([:positive])}"
      assert :ok = StreamableHTTP.register_sse_handler(transport, session_id)
      assert self() == StreamableHTTP.get_sse_handler(transport, session_id)
    end

    test "allows multiple sessions to register", %{transport: transport} do
      session1 = "session-1-#{System.unique_integer([:positive])}"
      session2 = "session-2-#{System.unique_integer([:positive])}"

      pid1 =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      pid2 =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      :ok = GenServer.call(transport, {:register_sse_handler, session1, pid1})
      :ok = GenServer.call(transport, {:register_sse_handler, session2, pid2})

      assert pid1 == StreamableHTTP.get_sse_handler(transport, session1)
      assert pid2 == StreamableHTTP.get_sse_handler(transport, session2)

      send(pid1, :stop)
      send(pid2, :stop)
    end

    test "updates monitor when re-registering same session", %{transport: transport} do
      session_id = "test-session-#{System.unique_integer([:positive])}"

      pid1 =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      :ok = GenServer.call(transport, {:register_sse_handler, session_id, pid1})

      pid2 =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      :ok = GenServer.call(transport, {:register_sse_handler, session_id, pid2})

      assert pid2 == StreamableHTTP.get_sse_handler(transport, session_id)

      send(pid1, :stop)
      send(pid2, :stop)
    end
  end

  describe "unregister_sse_handler/2" do
    test "unregisters SSE handler", %{transport: transport} do
      session_id = "test-session-#{System.unique_integer([:positive])}"
      StreamableHTTP.register_sse_handler(transport, session_id)
      assert self() == StreamableHTTP.get_sse_handler(transport, session_id)

      StreamableHTTP.unregister_sse_handler(transport, session_id)
      assert nil == StreamableHTTP.get_sse_handler(transport, session_id)
    end

    test "handles unregistering non-existent session gracefully", %{transport: transport} do
      StreamableHTTP.unregister_sse_handler(transport, "non-existent")
    end
  end

  describe "handle_message/3" do
    test "forwards request to server and returns response", %{transport: transport} do
      session_id = "test-session-#{System.unique_integer([:positive])}"

      assert :ok = initialize_session(transport, session_id)

      request = ping_request()
      assert {:ok, response} = StreamableHTTP.handle_message(transport, session_id, request)
      assert is_binary(response)
      assert response =~ "\"result\":{}"
      assert response =~ ~s("jsonrpc":"2.0")
    end

    test "handles notifications (returns nil)", %{transport: transport} do
      session_id = "test-session-#{System.unique_integer([:positive])}"

      notification = %{
        "method" => "notifications/initialized"
      }

      assert {:ok, nil} = StreamableHTTP.handle_message(transport, session_id, notification)
    end

    test "propagates server errors", %{transport: transport} do
      session_id = "test-session-#{System.unique_integer([:positive])}"

      assert :ok = initialize_session(transport, session_id)

      request = %{
        "method" => "unknown_method",
        "params" => %{}
      }

      assert {:ok, response} = StreamableHTTP.handle_message(transport, session_id, request)
      assert response =~ "\"error\""
      assert response =~ "method_not_found"
    end

    test "handles tools/list request", %{transport: transport} do
      session_id = "test-session-#{System.unique_integer([:positive])}"

      assert :ok = initialize_session(transport, session_id)

      request = tools_list_request()
      assert {:ok, response} = StreamableHTTP.handle_message(transport, session_id, request)
      assert response =~ "\"tools\":[]"
    end
  end

  describe "handle_message_for_sse/3" do
    test "returns {:sse, response} when SSE handler exists", %{transport: transport} do
      session_id = "test-session-#{System.unique_integer([:positive])}"

      assert :ok = initialize_session(transport, session_id)

      StreamableHTTP.register_sse_handler(transport, session_id)

      request = ping_request()
      assert {:sse, response} = StreamableHTTP.handle_message_for_sse(transport, session_id, request)
      assert response =~ "\"result\":{}"
    end

    test "returns {:ok, response} when no SSE handler", %{transport: transport} do
      session_id = "test-session-#{System.unique_integer([:positive])}"

      assert :ok = initialize_session(transport, session_id)

      request = ping_request()
      assert {:ok, response} = StreamableHTTP.handle_message_for_sse(transport, session_id, request)
      assert response =~ "\"result\":{}"
    end
  end

  describe "route_to_session/3" do
    test "routes message to specific session", %{transport: transport} do
      session_id = "test-session-#{System.unique_integer([:positive])}"
      StreamableHTTP.register_sse_handler(transport, session_id)

      message = "test message"
      assert :ok = StreamableHTTP.route_to_session(transport, session_id, message)

      assert_receive {:sse_message, ^message}
    end

    test "returns error when no SSE handler", %{transport: transport} do
      session_id = "non-existent"
      message = "test message"

      assert {:error, :no_sse_handler} = StreamableHTTP.route_to_session(transport, session_id, message)
    end
  end

  describe "send_message/2" do
    test "broadcasts to all SSE handlers", %{transport: transport} do
      collector = self()

      sessions = setup_broadcast_sessions(transport, 3, collector)

      message = "broadcast message"
      assert :ok = StreamableHTTP.send_message(transport, message)

      for {_session_id, pid} <- sessions do
        assert_receive {:received, ^pid, ^message}, 1000
      end

      cleanup_sessions(sessions)
    end

    test "succeeds with no active handlers", %{transport: transport} do
      message = "test message"
      assert :ok = StreamableHTTP.send_message(transport, message)
    end
  end

  describe "SSE handler monitoring" do
    test "removes handler when process dies", %{transport: transport} do
      session_id = "test-session-#{System.unique_integer([:positive])}"

      pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      :ok = GenServer.call(transport, {:register_sse_handler, session_id, pid})
      assert pid == StreamableHTTP.get_sse_handler(transport, session_id)

      Process.exit(pid, :kill)
      Process.sleep(50)

      refute StreamableHTTP.get_sse_handler(transport, session_id)
    end

    test "cleanup works with multiple handlers", %{transport: transport} do
      pids =
        for i <- 1..3 do
          session_id = "session-#{i}-#{System.unique_integer([:positive])}"

          pid =
            spawn(fn ->
              receive do
                :stop -> :ok
              end
            end)

          :ok = GenServer.call(transport, {:register_sse_handler, session_id, pid})
          {session_id, pid}
        end

      {session_to_kill, pid_to_kill} = Enum.at(pids, 1)
      Process.exit(pid_to_kill, :kill)
      Process.sleep(50)

      for {session_id, pid} <- pids do
        if session_id == session_to_kill do
          refute StreamableHTTP.get_sse_handler(transport, session_id)
        else
          assert pid == StreamableHTTP.get_sse_handler(transport, session_id)
          send(pid, :stop)
        end
      end
    end
  end

  describe "shutdown/1" do
    test "sends close message to all SSE handlers", %{transport: transport} do
      session_id = "test-session-#{System.unique_integer([:positive])}"
      StreamableHTTP.register_sse_handler(transport, session_id)

      ref = Process.monitor(transport)

      StreamableHTTP.shutdown(transport)

      assert_receive :close_sse
      assert_receive {:DOWN, ^ref, :process, _, :normal}
    end

    test "stops the transport process", %{transport: transport} do
      ref = Process.monitor(transport)
      StreamableHTTP.shutdown(transport)

      assert_receive {:DOWN, ^ref, :process, _, :normal}
    end
  end

  describe "supported_protocol_versions/0" do
    test "returns expected protocol versions" do
      versions = StreamableHTTP.supported_protocol_versions()
      assert "2024-11-05" in versions
      assert "2025-03-26" in versions
    end
  end

  describe "integration with MCP protocol" do
    test "full message flow with proper encoding/decoding", %{transport: transport} do
      session_id = "test-session-#{System.unique_integer([:positive])}"

      init_request = init_request()
      {:ok, init_response} = StreamableHTTP.handle_message(transport, session_id, init_request)
      assert init_response =~ ~s("protocolVersion":"2025-03-26")
      assert init_response =~ "\"serverInfo\""
      assert init_response =~ ~s("name":"Test Server")
      assert init_response =~ ~s("version":"1.0.0")

      notification = initialized_notification()
      assert {:ok, nil} = StreamableHTTP.handle_message(transport, session_id, notification)

      tools_request = tools_list_request()
      {:ok, tools_response} = StreamableHTTP.handle_message(transport, session_id, tools_request)
      assert tools_response =~ "\"tools\":[]"

      StreamableHTTP.register_sse_handler(transport, session_id)
      assert {:sse, sse_response} = StreamableHTTP.handle_message_for_sse(transport, session_id, tools_request)
      assert sse_response =~ "\"tools\":[]"
    end

    test "handles concurrent sessions", %{transport: transport} do
      sessions =
        for i <- 1..5 do
          session_id = "session-#{i}-#{System.unique_integer([:positive])}"

          task =
            Task.async(fn ->
              :ok = initialize_session(transport, session_id)

              request = ping_request()
              {:ok, response} = StreamableHTTP.handle_message(transport, session_id, request)
              {session_id, response}
            end)

          {session_id, task}
        end

      results =
        for {session_id, task} <- sessions do
          {^session_id, response} = Task.await(task)
          assert response =~ "\"result\":{}"
          session_id
        end

      assert length(results) == 5
    end
  end
end
