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

    # Regression: streamable HTTP clients (mcp-remote, the TS SDK) fire
    # `notifications/initialized` and the first real request as back-to-back
    # HTTP POSTs without serializing them. The cast carrying the notification
    # can land in the GenServer's mailbox AFTER the request call. Previously
    # that produced a spurious "Server not initialized" error and a broken
    # MCP connection ("This connector has no tools available" in Claude
    # Desktop). The fix defers non-init requests on uninitialized sessions
    # and retries until init lands or a 500ms timeout elapses.
    test "defers requests until session is initialized then processes them", %{server: server} do
      session_id = "race_test_#{System.unique_integer([:positive])}"

      # Open the session without sending notifications/initialized.
      init_request = build_request("initialize", "init_id_1")

      init_request =
        Map.put(init_request, "params", %{
          "protocolVersion" => "2025-03-26",
          "clientInfo" => %{"name" => "TestClient", "version" => "1.0.0"},
          "capabilities" => %{}
        })

      assert {:ok, _} = GenServer.call(server, {:request, init_request, session_id, %{}})

      test_pid = self()

      task =
        Task.async(fn ->
          send(test_pid, :request_sent)
          GenServer.call(server, {:request, build_request("tools/list", %{}, 42), session_id, %{}}, 2_000)
        end)

      assert_receive :request_sent, 500

      # Simulate the notification arriving just after — well within the 500ms wait window.
      Process.sleep(50)
      notification = build_notification("notifications/initialized", %{})
      assert :ok = GenServer.cast(server, {:notification, notification, session_id, %{}})

      assert {:ok, encoded} = Task.await(task, 2_000)
      assert encoded =~ ~s("tools")
      refute encoded =~ "Server not initialized"
    end

    # Regression for cloudwalk-review-agent findings on PR #257.
    #
    # Two invariants this exercises end-to-end:
    #
    # 1. ENCODING CONTRACT: the synchronous return value of
    #    handle_call({:request, ...}, ...) must be an encoded JSON
    #    binary suitable for `Plug.Conn.send_resp/3`, not an unencoded
    #    `{:ok, map}` tuple. An unencoded map would crash the StreamableHTTP
    #    plug at runtime.
    #
    # 2. NO-CRASH ON ATTACH FAILURE: any failure path returned by
    #    maybe_attach_session/3 (`:session_terminated` from a stale cached
    #    pid, `:noproc` from a supervisor under cluster pressure, etc.) must
    #    not crash the GenServer with `bad_return_value` or
    #    `CaseClauseError`. The unified `{:error, reason, state}` clause in
    #    handle_call/3 covers any reason — narrowing it would also need to
    #    change the @spec, so this is structurally protected.
    #
    # Setup: pre-install a sessions-map entry pointing at a dead pid.
    # The :dead branch in attach/5 drops the stale entry and recurses
    # into the second maybe_attach_session/3 clause, which then creates
    # a fresh session. The request is then deferred for the
    # `notifications/initialized` notification (which never arrives in this
    # test) and times out via `handle_retry_pending_request/6` — the same
    # code path that previously returned an unencoded `{:ok, map}` via
    # GenServer.reply and that this fix corrected to an encoded binary.
    test "replies with encoded JSON binary when session attach goes through the error path", %{server: server} do
      session_id = "dead_session_#{System.unique_integer([:positive])}"
      dead_pid = make_dead_pid()

      :sys.replace_state(server, fn state ->
        ref = Process.monitor(dead_pid)
        %{state | sessions: Map.put(state.sessions, session_id, {nil, dead_pid, ref})}
      end)

      request = build_request("tools/list", %{}, 99)

      assert {:ok, encoded} =
               GenServer.call(server, {:request, request, session_id, %{}}, 2_000)

      assert is_binary(encoded), "transport contract requires an encoded JSON binary, got: #{inspect(encoded)}"
      decoded = JSON.decode!(encoded)
      assert is_map(decoded["error"]), "expected a JSON-RPC error response, got: #{inspect(decoded)}"
      assert decoded["id"] == 99

      assert Process.alive?(server)
    end

    # Same race on the notification cast path. The cast must drop quietly
    # (no crash, no reply — notifications have no response).
    test "drops notification without crashing if session pid is dead", %{server: server} do
      session_id = "dead_session_cast_#{System.unique_integer([:positive])}"
      dead_pid = make_dead_pid()

      :sys.replace_state(server, fn state ->
        ref = Process.monitor(dead_pid)
        %{state | sessions: Map.put(state.sessions, session_id, {nil, dead_pid, ref})}
      end)

      notification = build_notification("notifications/progress", %{"progressToken" => "x", "progress" => 1})

      assert :ok = GenServer.cast(server, {:notification, notification, session_id, %{}})

      Process.sleep(20)
      assert Process.alive?(server)
    end

    defp make_dead_pid do
      p = spawn(fn -> :ok end)
      ref = Process.monitor(p)
      receive do
        {:DOWN, ^ref, :process, ^p, _} -> p
      after
        500 -> flunk("test helper: spawned process did not exit")
      end
    end

    test "deferred requests time out with not-initialized error if init never arrives", %{server: server} do
      session_id = "timeout_test_#{System.unique_integer([:positive])}"

      init_request = build_request("initialize", "init_id_2")

      init_request =
        Map.put(init_request, "params", %{
          "protocolVersion" => "2025-03-26",
          "clientInfo" => %{"name" => "TestClient", "version" => "1.0.0"},
          "capabilities" => %{}
        })

      assert {:ok, _} = GenServer.call(server, {:request, init_request, session_id, %{}})

      {:ok, encoded} =
        GenServer.call(server, {:request, build_request("tools/list", %{}, 43), session_id, %{}}, 2_000)

      assert encoded =~ "Server not initialized"
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

    test "recovers when cached session pid has died (cross-node race)" do
      transport = start_supervised!(StubTransport)

      server =
        start_supervised!(
          {Base,
           [
             module: StubServer,
             name: :stale_cache_server,
             transport: [layer: StubTransport, name: transport],
             session_idle_timeout: 60_000
           ]}
        )

      session_id = "stale_cache_#{System.unique_integer()}"

      # Establish + cache the session
      init_msg = init_request("2025-03-26", %{"name" => "TestClient", "version" => "1.0.0"})
      assert {:ok, _} = GenServer.call(server, {:request, init_msg, session_id, %{}})

      session_name = Hermes.Server.Registry.server_session(StubServer, session_id)
      original_pid = GenServer.whereis(session_name)
      assert is_pid(original_pid)

      # Simulate the production failure mode: in a cross-node scenario the
      # session pid lives on a remote node and that node dies (Horde
      # rebalance, Fly machine shutdown, idle expiry timer firing on
      # another node). Locally we still hold the stale pid in our sessions
      # map because the {:DOWN, ...} message from Erlang distribution
      # hasn't propagated yet. Inject this state directly: kill the session
      # but keep a dead pid in the cache so the next request hits
      # clause 1 of maybe_attach_session/3 with a dead pid.
      dead_pid =
        spawn(fn ->
          receive do
            :never -> :ok
          end
        end)

      Process.exit(dead_pid, :shutdown)
      ref = Process.monitor(dead_pid)
      assert_receive {:DOWN, ^ref, :process, ^dead_pid, _}, 1_000
      refute Process.alive?(dead_pid)

      :sys.replace_state(server, fn state ->
        sessions =
          Map.put(state.sessions, session_id, {session_name, dead_pid, make_ref()})

        %{state | sessions: sessions}
      end)

      # Subsequent request must NOT crash with :shutdown EXIT. Pre-fix,
      # maybe_attach_session/3 clause 1 called Session.get on the dead pid
      # and the call exited :shutdown / :noproc, propagating up through
      # the calling task and crashing the request. Post-fix, safe_session_get
      # catches the exit, demonitors + drops the stale entry, and falls
      # through to clause 2 to re-resolve via the registry.
      ping = build_request("ping", %{}, System.unique_integer())
      assert {:ok, _} = GenServer.call(server, {:request, ping, session_id, %{}}, 2_000)
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
