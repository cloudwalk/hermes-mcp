defmodule Hermes.Server.Transport.StreamableHTTP.PlugTest do
  use Hermes.MCP.Case, async: false

  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  alias Hermes.MCP.Message
  alias Hermes.Server.Transport.StreamableHTTP
  alias Hermes.Server.Transport.StreamableHTTP.Plug, as: StreamableHTTPPlug

  setup :with_default_registry

  describe "init/1" do
    test "requires server option" do
      assert_raise KeyError, fn ->
        StreamableHTTPPlug.init([])
      end
    end

    test "initializes with valid options", %{registry: registry} do
      opts = StreamableHTTPPlug.init(server: StubServer)

      assert %{
               transport: transport,
               session_header: "mcp-session-id",
               timeout: 30_000
             } = opts

      assert transport == registry.transport(StubServer, :streamable_http)
    end

    test "accepts custom session header", %{registry: registry} do
      opts =
        StreamableHTTPPlug.init(
          server: StubServer,
          session_header: "x-custom-session"
        )

      assert %{
               transport: transport,
               session_header: "x-custom-session",
               timeout: 30_000
             } = opts

      assert transport == registry.transport(StubServer, :streamable_http)
    end

    test "uses custom registry when provided" do
      start_supervised!(MockCustomRegistry)
      assert Process.whereis(MockCustomRegistry)

      opts =
        StreamableHTTPPlug.init(
          server: StubServer,
          mode: :streamable_http,
          registry: MockCustomRegistry
        )

      expected_transport = MockCustomRegistry.transport(StubServer, :streamable_http)

      assert opts.transport == expected_transport
    end
  end

  describe "GET endpoint" do
    setup %{registry: registry} do
      name = registry.transport(StubServer, :streamable_http)
      sup = registry.task_supervisor(StubServer)

      {:ok, transport} =
        start_supervised({StreamableHTTP, server: StubServer, name: name, registry: registry, task_supervisor: sup})

      opts = StreamableHTTPPlug.init(server: StubServer)

      %{opts: opts, transport: transport}
    end

    test "GET request establishes SSE connection", %{transport: transport} do
      conn =
        :get
        |> conn("/")
        |> put_req_header("accept", "text/event-stream")

      assert conn.method == "GET"
      assert get_req_header(conn, "accept") == ["text/event-stream"]

      session_id = "test-session-123"
      assert :ok = StreamableHTTP.register_sse_handler(transport, session_id)

      # Note: We don't actually call the plug here because it would
      # establish a persistent connection and hang the test

      # Clean up to avoid logs after test ends
      capture_log(fn ->
        StreamableHTTP.unregister_sse_handler(transport, session_id)
        Process.sleep(10)
      end)
    end

    test "GET request without SSE accept header returns error", %{opts: opts} do
      conn =
        :get
        |> conn("/")
        |> StreamableHTTPPlug.call(opts)

      assert conn.status == 406
      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["error"]["message"] == "Invalid Request"
    end
  end

  describe "POST endpoint" do
    setup %{registry: registry} do
      # Start the session supervisor
      {:ok, _session_sup} =
        start_supervised({
          Hermes.Server.Session.Supervisor,
          server: StubServer, registry: registry
        })

      # Start a stub transport for the server
      stub_transport =
        start_supervised!({StubTransport, name: registry.transport(StubServer, :stub)})

      # Start the Base server with stub transport
      {:ok, _server} =
        start_supervised({
          Hermes.Server.Base,
          module: StubServer,
          name: registry.server(StubServer),
          transport: [layer: StubTransport, name: stub_transport],
          registry: registry
        })

      # Now start the StreamableHTTP transport
      name = registry.transport(StubServer, :streamable_http)
      sup = registry.task_supervisor(StubServer)
      start_supervised!({Task.Supervisor, name: sup})

      {:ok, transport} =
        start_supervised({StreamableHTTP, server: StubServer, name: name, registry: registry, task_supervisor: sup})

      opts = StreamableHTTPPlug.init(server: StubServer)

      %{opts: opts, transport: transport}
    end

    test "POST request with notification returns 202", %{opts: opts} do
      # Notifications have no JSON-RPC response id to preserve. With no
      # session header, Streamable HTTP keeps the prior best-effort behavior
      # and accepts the notification instead of fabricating an error response.
      notification =
        build_notification("notifications/message", %{
          "level" => "info",
          "data" => "test"
        })

      {:ok, body} = Message.encode_notification(notification)

      conn =
        :post
        |> conn("/", body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> StreamableHTTPPlug.call(opts)

      assert conn.status == 202
      assert conn.resp_body == "{}"
    end

    test "POST non-initialize request without session header returns 400", %{opts: opts} do
      # Spec: a server that requires a session id SHOULD answer a
      # non-initialize request lacking Mcp-Session-Id with HTTP 400.
      # (Previously this fabricated an id and returned 200 — the bug.)
      request = build_request("ping", %{})
      {:ok, body} = Message.encode_request(request, 1)

      conn =
        :post
        |> conn("/", body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> StreamableHTTPPlug.call(opts)

      assert conn.status == 400
      {:ok, response} = Jason.decode(conn.resp_body)
      assert response["id"] == 1
      assert response["error"]["message"] =~ "Invalid"
    end

    test "POST request with invalid JSON returns error", %{opts: opts} do
      conn =
        :post
        |> conn("/", "invalid json")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> StreamableHTTPPlug.call(opts)

      assert conn.status == 400
      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["error"]["code"] == -32_700
    end

    # ENA-9175 proof matrix (a): unknown / never-initialized session id
    # on a real request → transport-level HTTP 404, immediately. Per the
    # MCP Streamable HTTP spec only a 404 status obligates the client to
    # re-`initialize`; a JSON-RPC error inside HTTP 2xx does not. Must be
    # fast — no 500ms init-wait park.
    test "POST request with unknown session id returns 404 fast", %{opts: opts} do
      request = build_request("tools/list", %{})
      {:ok, body} = Message.encode_request(request, 1)

      {elapsed_us, conn} =
        :timer.tc(fn ->
          :post
          |> conn("/", body)
          |> put_req_header("content-type", "application/json")
          |> put_req_header("accept", "application/json, text/event-stream")
          |> put_req_header("mcp-session-id", "bogus-never-initialized")
          |> StreamableHTTPPlug.call(opts)
        end)

      assert conn.status == 404
      {:ok, response} = Jason.decode(conn.resp_body)
      assert is_map(response["error"])

      assert elapsed_us < 200_000,
             "expected immediate 404, took #{elapsed_us}µs (init-wait window is 500ms — must not park)"
    end

    # ENA-9175 proof matrix (d): initialize is unaffected — it MUST work
    # with no session header and the server mints + returns a fresh id.
    test "POST initialize with no session header succeeds and issues an id", %{opts: opts} do
      init_request =
        build_request("initialize", %{
          "protocolVersion" => "2025-03-26",
          "clientInfo" => %{"name" => "test", "version" => "1.0.0"}
        })

      {:ok, body} = Message.encode_request(init_request, 1)

      conn =
        :post
        |> conn("/", body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> StreamableHTTPPlug.call(opts)

      assert conn.status == 200
      assert [session_id] = get_resp_header(conn, "mcp-session-id")
      assert is_binary(session_id) and session_id != ""
    end
  end

  describe "DELETE endpoint" do
    setup %{registry: registry} do
      name = registry.transport(StubServer, :streamable_http)
      sup = registry.task_supervisor(StubServer)

      {:ok, transport} =
        start_supervised({StreamableHTTP, server: StubServer, name: name, registry: registry, task_supervisor: sup})

      opts = StreamableHTTPPlug.init(server: StubServer)

      %{opts: opts, transport: transport}
    end

    test "DELETE request with session ID returns success", %{opts: opts} do
      conn =
        :delete
        |> conn("/")
        |> put_req_header("mcp-session-id", "test-session")
        |> StreamableHTTPPlug.call(opts)

      assert conn.status == 200
      assert conn.resp_body == "{}"
    end

    test "DELETE request without session ID returns error", %{opts: opts} do
      conn =
        :delete
        |> conn("/")
        |> StreamableHTTPPlug.call(opts)

      assert conn.status == 400
      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["error"]["message"] == "Internal error"
    end
  end

  describe "unsupported methods" do
    setup %{registry: registry} do
      name = registry.transport(StubServer, :streamable_http)
      sup = registry.task_supervisor(StubServer)

      {:ok, _transport} =
        start_supervised({StreamableHTTP, server: StubServer, name: name, registry: registry, task_supervisor: sup})

      opts = StreamableHTTPPlug.init(server: StubServer)

      %{opts: opts}
    end

    test "non-supported method returns 405", %{opts: opts} do
      conn =
        :put
        |> conn("/", "")
        |> StreamableHTTPPlug.call(opts)

      assert conn.status == 405
      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["error"]["message"] == "Method not found"
    end
  end

  describe "session handling" do
    setup %{registry: registry} do
      # Start the session supervisor
      {:ok, _session_sup} =
        start_supervised({
          Hermes.Server.Session.Supervisor,
          server: StubServer, registry: registry
        })

      # Start a stub transport for the server
      stub_transport =
        start_supervised!({StubTransport, name: registry.transport(StubServer, :stub)})

      # Start the Base server with stub transport
      {:ok, _server} =
        start_supervised({
          Hermes.Server.Base,
          module: StubServer,
          name: registry.server(StubServer),
          transport: [layer: StubTransport, name: stub_transport],
          registry: registry
        })

      # Now start the StreamableHTTP transport
      name = registry.transport(StubServer, :streamable_http)
      sup = registry.task_supervisor(StubServer)
      start_supervised!({Task.Supervisor, name: sup})

      {:ok, transport} =
        start_supervised({StreamableHTTP, server: StubServer, name: name, registry: registry, task_supervisor: sup})

      opts = StreamableHTTPPlug.init(server: StubServer)

      %{opts: opts, transport: transport}
    end

    test "extracts session ID from header", %{opts: opts} do
      notification =
        build_notification("notifications/message", %{
          "level" => "info",
          "data" => "test"
        })

      {:ok, body} = Message.encode_notification(notification)

      conn =
        :post
        |> conn("/", body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> put_req_header("mcp-session-id", "header-session-123")
        |> StreamableHTTPPlug.call(opts)

      assert conn.status == 202
    end

    test "generates session ID if not provided", %{opts: opts} do
      notification =
        build_notification("notifications/message", %{
          "level" => "info",
          "data" => "test"
        })

      {:ok, body} = Message.encode_notification(notification)

      conn =
        :post
        |> conn("/", body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> StreamableHTTPPlug.call(opts)

      assert conn.status == 202
    end

    test "initialize request generates new session ID", %{opts: opts} do
      init_request =
        build_request("initialize", %{
          "protocolVersion" => "2025-03-26",
          "clientInfo" => %{"name" => "test", "version" => "1.0.0"}
        })

      {:ok, body} = Message.encode_request(init_request, 1)

      conn =
        :post
        |> conn("/", body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> put_req_header("mcp-session-id", "should-be-ignored")
        |> StreamableHTTPPlug.call(opts)

      assert conn.status == 200
    end
  end
end
