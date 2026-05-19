defmodule Hermes.Server.BaseTest do
  use Hermes.MCP.Case, async: false

  alias Hermes.MCP.Message
  alias Hermes.Server.Base
  alias Hermes.Server.Frame
  alias Hermes.Server.Session
  alias Hermes.Server.Session.Supervisor, as: SessionSupervisor

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

    # ENA-9175: a non-initialize request bearing a session id that was
    # never created (unknown / terminated / resumed-after-restart) MUST
    # be rejected immediately with `:session_not_found` so the transport
    # can answer HTTP 404 per the MCP Streamable HTTP spec — NOT silently
    # vivified into a fresh uninitialized session that parks 500ms and
    # then returns "Server not initialized" inside an HTTP 2xx (which a
    # spec-correct client never treats as a re-initialize signal).
    test "rejects an unknown session id immediately with :session_not_found", %{server: server} do
      request = build_request("tools/list", 123)
      ctx = %{transport: :streamable_http}

      {elapsed_us, reply} =
        :timer.tc(fn ->
          GenServer.call(server, {:request, request, "not_initialized", ctx})
        end)

      assert reply == {:error, :session_not_found}

      assert elapsed_us < 200_000,
             "expected immediate rejection, took #{elapsed_us}µs (init-wait window is #{500}ms — must not park)"
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

    # ENA-9175 keystone no-regression: the discriminator must distinguish
    # "unknown session" (→ :session_not_found / 404) from "session exists
    # but notifications/initialized hasn't landed yet" (PR #257 problem
    # #3 → MUST still defer, never 404). A session opened by `initialize`
    # is in state.sessions, so a follow-up request is `known?` → it takes
    # the unchanged defer path, not the new short-circuit.
    test "a session opened by initialize is deferred, never :session_not_found", %{server: server} do
      session_id = "keystone_#{System.unique_integer([:positive])}"

      init_request =
        "initialize"
        |> build_request("init_keystone")
        |> Map.put("params", %{
          "protocolVersion" => "2025-03-26",
          "clientInfo" => %{"name" => "TestClient", "version" => "1.0.0"},
          "capabilities" => %{}
        })

      ctx = %{transport: :streamable_http}
      assert {:ok, _} = GenServer.call(server, {:request, init_request, session_id, ctx})

      test_pid = self()

      task =
        Task.async(fn ->
          send(test_pid, :sent)
          GenServer.call(server, {:request, build_request("tools/list", %{}, 7), session_id, ctx}, 2_000)
        end)

      assert_receive :sent, 500
      Process.sleep(50)
      notification = build_notification("notifications/initialized", %{})
      assert :ok = GenServer.cast(server, {:notification, notification, session_id, %{}})

      # {:ok, encoded} (not {:error, :session_not_found}) proves the
      # known-but-uninitialized session was deferred, not 404'd.
      assert {:ok, encoded} = Task.await(task, 2_000)
      assert encoded =~ ~s("tools")
      refute encoded =~ "Server not initialized"
    end

    # Regression for cloudwalk-review-agent findings on PR #257, updated
    # for ENA-9175. The two PR #257 structural invariants still hold; the
    # ENA-9175 discriminator changes only WHAT is returned:
    #
    # 1. NO-CRASH ON ATTACH FAILURE: a dead/terminated session pid must
    #    not crash the GenServer with `bad_return_value` /`CaseClauseError`.
    #    Still asserted via `Process.alive?(server)`.
    #
    # 2. TRANSPORT-HANDLEABLE REPLY: the synchronous return must be a
    #    value the transport can turn into an HTTP response, never an
    #    unencoded `{:ok, map}` reaching `send_resp/3`. Under ENA-9175 a
    #    request whose session id has no live process is `:session_not_found`
    #    — `streamable_http.ex` `forward_request_to_server/6`'s
    #    `{:error, reason}` arm carries it to the plug, which encodes a
    #    JSON-RPC body + HTTP 404 (covered end-to-end by the plug test
    #    "POST request with unknown session id returns 404 fast").
    #
    # Setup: pre-install a sessions-map entry pointing at a dead pid.
    # `Process.monitor/1` on an already-dead pid (run inside the server
    # via `:sys.replace_state`) immediately queues `{:DOWN, …}` into the
    # server mailbox; it is processed before this request, pruning the
    # stale entry. The discriminator then correctly sees an unknown
    # session and short-circuits to `:session_not_found` instead of
    # silently vivifying a fresh uninitialized session that parks 500ms
    # and returns "Server not initialized" inside an HTTP 2xx (the bug).
    test "an attach-failed / dead session id replies :session_not_found without crashing", %{server: server} do
      session_id = "dead_session_#{System.unique_integer([:positive])}"
      dead_pid = make_dead_pid()

      :sys.replace_state(server, fn state ->
        ref = Process.monitor(dead_pid)
        %{state | sessions: Map.put(state.sessions, session_id, {nil, dead_pid, ref})}
      end)

      request = build_request("tools/list", %{}, 99)

      assert {:error, :session_not_found} =
               GenServer.call(server, {:request, request, session_id, %{transport: :streamable_http}}, 2_000)

      # PR #257 invariant: no bad_return_value / CaseClauseError crash.
      assert Process.alive?(server)
    end

    test "a stale cached Streamable HTTP session is not recreated before DOWN cleanup", %{server: server} do
      session_id = "stale_cached_#{System.unique_integer([:positive])}"
      dead_pid = make_dead_pid()

      :sys.replace_state(server, fn state ->
        %{state | sessions: Map.put(state.sessions, session_id, {nil, dead_pid, make_ref()})}
      end)

      request = build_request("tools/list", %{}, 100)

      assert {:error, :session_not_found} =
               GenServer.call(server, {:request, request, session_id, %{transport: :streamable_http}}, 2_000)

      refute Map.has_key?(:sys.get_state(server).sessions, session_id)
      assert :not_found == SessionSupervisor.whereis_session(Hermes.Server.Registry, StubServer, session_id)
      assert Process.alive?(server)
    end

    test "a live registry-resolvable Streamable HTTP session attaches without local cache", %{server: server} do
      session_id = "registry_live_#{System.unique_integer([:positive])}"

      init_request =
        "initialize"
        |> build_request("init_registry_live")
        |> Map.put("params", %{
          "protocolVersion" => "2025-03-26",
          "clientInfo" => %{"name" => "TestClient", "version" => "1.0.0"},
          "capabilities" => %{}
        })

      ctx = %{transport: :streamable_http}
      assert {:ok, _} = GenServer.call(server, {:request, init_request, session_id, ctx})
      notification = build_notification("notifications/initialized", %{})
      assert :ok = GenServer.cast(server, {:notification, notification, session_id, %{}})
      Process.sleep(50)

      {_, pid, ref} = :sys.get_state(server).sessions[session_id]

      :sys.replace_state(server, fn state ->
        Process.demonitor(ref, [:flush])
        %{state | sessions: Map.delete(state.sessions, session_id)}
      end)

      request = build_request("tools/list", %{}, 101)

      assert {:ok, encoded} =
               GenServer.call(server, {:request, request, session_id, ctx}, 2_000)

      assert encoded =~ ~s("tools")
      assert {_, ^pid, _} = :sys.get_state(server).sessions[session_id]
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

      start_supervised!({SessionSupervisor, server: StubServer, registry: Hermes.Server.Registry})

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
