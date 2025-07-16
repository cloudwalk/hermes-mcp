defmodule Hermes.Server.BaseTest do
  use Hermes.MCP.Case, async: false

  alias Hermes.MCP.Message
  alias Hermes.Server.Base
  alias Hermes.Server.Frame
  alias Hermes.Server.Session

  require Message

  @moduletag capture_log: true

  describe "start_link/1" do
    test "starts a server with valid options" do
      transport = start_supervised!(StubTransport)

      assert {:ok, pid} =
               Base.start_link(
                 module: StubServer,
                 name: :named_server,
                 transport: [layer: StubTransport, name: transport]
               )

      assert Process.alive?(pid)
    end

    test "starts a named server" do
      transport = start_supervised!({StubTransport, []}, id: :named_transport)

      assert {:ok, _pid} =
               Base.start_link(
                 module: StubServer,
                 name: :named_server,
                 transport: [layer: StubTransport, name: transport]
               )

      assert pid = Process.whereis(:named_server)
      assert Process.alive?(pid)
    end
  end

  describe "handle_call/3 for messages" do
    setup :initialized_server

    @tag skip: true
    test "handles errors", %{server: server} do
      error = build_error(-32_000, "got wrong", 1)
      assert {:ok, _} = GenServer.call(server, {:request, error, "123", %{}})
    end

    test "rejects requests when not initialized", %{server: server} do
      request = build_request("tools/list", 123)

      assert {:ok, _} =
               GenServer.call(server, {:request, request, "not_initialized", %{}})
    end

    test "accept ping requests when not initialized", %{
      server: server,
      session_id: session_id
    } do
      request = build_request("ping", 123)
      assert {:ok, _} = GenServer.call(server, {:request, request, session_id, %{}})
    end
  end

  describe "handle_cast/2 for notifications" do
    setup :initialized_server

    test "handles notifications", %{server: server, session_id: session_id} do
      notification =
        build_notification("notifications/cancelled", %{"requestId" => 1})

      assert :ok =
               GenServer.cast(server, {:notification, notification, session_id, %{}})
    end

    test "handles initialize notification", %{server: server, session_id: session_id} do
      notification = build_notification("notifications/initialized", %{})

      assert :ok =
               GenServer.cast(server, {:notification, notification, session_id, %{}})
    end
  end

  describe "send_notification/3" do
    setup :initialized_server

    test "sends notification to transport", ctx do
      frame = Frame.put_private(%Frame{}, ctx)
      assert :ok = Hermes.Server.send_log_message(frame, :info, "hello")
    end
  end

  describe "session expiration" do
    setup do
      start_supervised!(Hermes.Server.Registry)

      start_supervised!({Session.Supervisor, server: StubServer, registry: Hermes.Server.Registry})

      :ok
    end

    test "session expires after idle timeout" do
      transport = start_supervised!(StubTransport)

      server =
        start_supervised!({Base,
         [
           module: StubServer,
           name: :expiry_test_server,
           transport: [layer: StubTransport, name: transport],
           # 100ms for testing
           session_idle_timeout: 100
         ]})

      session_id = "test_session_#{System.unique_integer()}"

      init_msg =
        init_request("2025-03-26", %{"name" => "TestClient", "version" => "1.0.0"})

      assert {:ok, _} = GenServer.call(server, {:request, init_msg, session_id, %{}})

      init_notification = build_notification("notifications/initialized", %{})

      assert :ok =
               GenServer.cast(
                 server,
                 {:notification, init_notification, session_id, %{}}
               )

      session_name = Hermes.Server.Registry.server_session(StubServer, session_id)
      assert Session.get(session_name)

      Process.sleep(150)

      # After expiration, the session should no longer be accessible
      # The session process has been terminated by the supervisor
      assert catch_exit(Session.get(session_name))
    end

    test "session timer resets on activity" do
      transport = start_supervised!(StubTransport)

      server =
        start_supervised!(
          {Base,
           [
             module: StubServer,
             name: :reset_test_server,
             transport: [layer: StubTransport, name: transport],
             session_idle_timeout: 200
           ]}
        )

      session_id = "reset_session_#{System.unique_integer()}"

      init_msg =
        init_request("2025-03-26", %{"name" => "TestClient", "version" => "1.0.0"})

      assert {:ok, _} = GenServer.call(server, {:request, init_msg, session_id, %{}})

      init_notification = build_notification("notifications/initialized", %{})

      assert :ok =
               GenServer.cast(
                 server,
                 {:notification, init_notification, session_id, %{}}
               )

      session_name = Hermes.Server.Registry.server_session(StubServer, session_id)

      for _ <- 1..3 do
        Process.sleep(100)
        ping = build_request("ping", %{}, System.unique_integer())
        assert {:ok, _} = GenServer.call(server, {:request, ping, session_id, %{}})
        assert Session.get(session_name)
      end

      Process.sleep(250)

      # After expiration, the session should no longer be accessible
      # The session process has been terminated by the supervisor
      assert catch_exit(Session.get(session_name))
    end

    test "notifications reset expiry timer" do
      transport = start_supervised!(StubTransport)

      server =
        start_supervised!(
          {Base,
           [
             module: StubServer,
             name: :notification_reset_server,
             transport: [layer: StubTransport, name: transport],
             session_idle_timeout: 200
           ]}
        )

      session_id = "notif_session_#{System.unique_integer()}"

      init_msg =
        init_request("2025-03-26", %{"name" => "TestClient", "version" => "1.0.0"})

      assert {:ok, _} = GenServer.call(server, {:request, init_msg, session_id, %{}})

      init_notification = build_notification("notifications/initialized", %{})

      assert :ok =
               GenServer.cast(
                 server,
                 {:notification, init_notification, session_id, %{}}
               )

      session_name = Hermes.Server.Registry.server_session(StubServer, session_id)

      for _ <- 1..3 do
        Process.sleep(100)

        notification =
          build_notification("notifications/message", %{
            "level" => "info",
            "data" => "test"
          })

        assert :ok =
                 GenServer.cast(
                   server,
                   {:notification, notification, session_id, %{}}
                 )

        assert Session.get(session_name)
      end

      Process.sleep(250)

      # After expiration, the session should no longer be accessible
      # The session process has been terminated by the supervisor
      assert catch_exit(Session.get(session_name))
    end
  end

  describe "sampling requests" do
    setup context do
      context
      |> Map.put(:client_capabilities, %{"sampling" => %{}})
      |> initialized_server()
      |> then(fn ctx ->
        frame = Frame.put_private(%Frame{}, ctx)
        Map.put(ctx, :frame, frame)
      end)
    end

    test "server can send sampling request to client", %{
      server: server,
      transport: transport,
      session_id: session_id,
      frame: frame
    } do
      :ok = StubTransport.set_test_pid(transport, self())

      messages = [
        %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}
      ]

      :ok =
        Hermes.Server.send_sampling_request(frame, messages,
          system_prompt: "You are a helpful assistant",
          max_tokens: 100,
          metadata: %{test: true}
        )

      Process.sleep(10)

      assert_receive {:send_message, request_data}
      assert {:ok, [decoded]} = Message.decode(request_data)

      assert Message.is_request(decoded)
      assert decoded["method"] == "sampling/createMessage"
      assert decoded["params"]["messages"] == messages
      assert decoded["params"]["systemPrompt"] == "You are a helpful assistant"
      assert decoded["params"]["maxTokens"] == 100

      request_id = decoded["id"]

      response = %{
        "id" => request_id,
        "result" => %{
          "role" => "assistant",
          "content" => %{"type" => "text", "text" => "Hello! How can I help you?"},
          "model" => "test-model",
          "stopReason" => "endTurn"
        }
      }

      :ok = GenServer.cast(server, {:response, response, session_id, %{}})

      Process.sleep(10)

      state = :sys.get_state(server)
      assert state.frame.assigns.last_sampling_response == response["result"]
      assert state.frame.assigns.last_sampling_request_id == request_id
    end

    test "server handles sampling request timeout", %{
      server: server,
      transport: transport,
      frame: frame
    } do
      :ok = StubTransport.set_test_pid(transport, self())

      messages = [
        %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}
      ]

      :ok = Hermes.Server.send_sampling_request(frame, messages)

      Process.sleep(10)

      assert_receive {:send_message, _request_data}

      state = :sys.get_state(server)
      assert map_size(state.server_requests) == 1
    end

    test "server handles sampling error response", %{
      server: server,
      transport: transport,
      session_id: session_id,
      frame: frame
    } do
      :ok = StubTransport.set_test_pid(transport, self())

      messages = [
        %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}
      ]

      :ok = Hermes.Server.send_sampling_request(frame, messages)

      Process.sleep(10)

      assert_receive {:send_message, request_data}
      assert {:ok, [decoded]} = Message.decode(request_data)
      request_id = decoded["id"]

      error_response = %{
        "id" => request_id,
        "error" => %{
          "code" => -32_600,
          "message" => "Client doesn't support sampling"
        }
      }

      :ok =
        GenServer.cast(server, {:response, error_response, session_id, %{}})

      Process.sleep(10)

      state = :sys.get_state(server)
      assert map_size(state.server_requests) == 0
    end
  end
end
