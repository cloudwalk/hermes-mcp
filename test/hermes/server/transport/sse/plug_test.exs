defmodule Hermes.Server.Transport.SSE.PlugTest do
  use Hermes.MCP.Case, async: false

  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  alias Hermes.MCP.Message
  alias Hermes.Server.Base
  alias Hermes.Server.Transport.SSE
  alias Hermes.Server.Transport.SSE.Plug, as: SSEPlug

  setup :with_default_registry

  describe "init/1" do
    test "requires server option" do
      assert_raise KeyError, fn ->
        SSEPlug.init(mode: :sse)
      end
    end

    test "requires mode option" do
      assert_raise KeyError, fn ->
        SSEPlug.init(server: StubServer)
      end
    end

    test "mode must be :sse or :post" do
      assert_raise ArgumentError, ~r/mode to be either :sse or :post/, fn ->
        SSEPlug.init(server: StubServer, mode: :invalid)
      end
    end

    test "initializes with valid options", %{registry: registry} do
      opts = SSEPlug.init(server: StubServer, mode: :sse, timeout: 5000)

      assert %{
               transport: transport,
               mode: :sse,
               timeout: 5000
             } = opts

      assert transport == registry.transport(StubServer, :sse)
    end

    test "uses custom registry when provided" do
      start_supervised!(MockCustomRegistry)
      assert Process.whereis(MockCustomRegistry)

      opts =
        SSEPlug.init(server: StubServer, mode: :sse, registry: MockCustomRegistry)

      expected_transport = MockCustomRegistry.transport(StubServer, :sse)

      assert opts.transport == expected_transport
    end
  end

  describe "SSE endpoint" do
    setup %{registry: registry} do
      name = registry.transport(StubServer, :sse)

      {:ok, transport} =
        start_supervised({SSE, server: StubServer, name: name, registry: registry})

      sse_opts = SSEPlug.init(server: StubServer, mode: :sse)
      %{sse_opts: sse_opts, transport: transport}
    end

    test "GET request establishes SSE connection", %{transport: transport} do
      conn =
        :get
        |> conn("/sse")
        |> put_req_header("accept", "text/event-stream")

      assert conn.method == "GET"
      assert get_req_header(conn, "accept") == ["text/event-stream"]

      session_id = "test-session-123"
      assert :ok = SSE.register_sse_handler(transport, session_id)

      endpoint_url = SSE.get_endpoint_url(transport)
      assert endpoint_url == "/messages"

      # Clean up to avoid logs after test ends
      capture_log(fn ->
        SSE.unregister_sse_handler(transport, session_id)
        Process.sleep(10)
      end)
    end

    test "GET request without SSE accept header returns error", %{sse_opts: sse_opts} do
      conn =
        :get
        |> conn("/sse")
        |> put_req_header("accept", "application/json")
        |> SSEPlug.call(sse_opts)

      assert conn.status == 406
      assert conn.resp_body =~ "Accept header must include text/event-stream"
    end

    test "non-GET request returns method not allowed", %{sse_opts: sse_opts} do
      conn =
        :post
        |> conn("/sse")
        |> SSEPlug.call(sse_opts)

      assert conn.status == 405
      assert conn.resp_body =~ "Method not allowed"
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
          Base,
          module: StubServer,
          name: registry.server(StubServer),
          transport: [layer: StubTransport, name: stub_transport],
          registry: registry
        })

      # Now start the SSE transport
      name = registry.transport(StubServer, :sse)

      {:ok, transport} =
        start_supervised({SSE, server: StubServer, name: name, registry: registry})

      post_opts = SSEPlug.init(server: StubServer, mode: :post)
      %{post_opts: post_opts, transport: transport, registry: registry}
    end

    test "POST request with valid JSON returns response", %{
      post_opts: post_opts,
      transport: transport
    } do
      session_id = "test-session"
      :ok = SSE.register_sse_handler(transport, session_id)

      request = build_request("ping", %{})
      {:ok, body} = Message.encode_request(request, 1)

      conn =
        :post
        |> conn("/messages", body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-session-id", session_id)
        |> SSEPlug.call(post_opts)

      assert conn.status == 202
      assert conn.resp_body == "{}"

      # Clean up to avoid logs after test ends
      capture_log(fn ->
        SSE.unregister_sse_handler(transport, session_id)
        Process.sleep(10)
      end)
    end

    test "POST request with notification returns 202", %{post_opts: post_opts} do
      notification =
        build_notification("notifications/message", %{
          "level" => "info",
          "data" => "test"
        })

      {:ok, body} = Message.encode_notification(notification)

      conn =
        :post
        |> conn("/messages", body)
        |> put_req_header("content-type", "application/json")
        |> SSEPlug.call(post_opts)

      assert conn.status == 202
      assert conn.resp_body == "{}"
    end

    test "POST request with invalid JSON returns error", %{post_opts: post_opts} do
      conn =
        :post
        |> conn("/messages", "invalid json")
        |> put_req_header("content-type", "application/json")
        |> SSEPlug.call(post_opts)

      assert conn.status == 400

      {:ok, [response]} = Message.decode(conn.resp_body)
      assert Message.is_error(response)
      assert response["error"]["code"] == -32_700
    end

    test "non-POST request returns method not allowed", %{post_opts: post_opts} do
      conn =
        :get
        |> conn("/messages")
        |> SSEPlug.call(post_opts)

      assert conn.status == 405
      assert conn.resp_body =~ "Method not allowed"
    end
  end

  describe "session ID extraction" do
    setup %{registry: registry} do
      name = registry.transport(StubServer, :sse)

      {:ok, transport} =
        start_supervised({SSE, server: StubServer, name: name, registry: registry})

      post_opts = SSEPlug.init(server: StubServer, mode: :post)
      %{post_opts: post_opts, transport: transport}
    end

    test "extracts session ID from header", %{post_opts: post_opts} do
      notification =
        build_notification("notifications/message", %{
          "level" => "info",
          "data" => "test"
        })

      {:ok, body} = Message.encode_notification(notification)

      conn =
        :post
        |> conn("/messages", body)
        |> put_req_header("x-session-id", "header-session-123")
        |> SSEPlug.call(post_opts)

      assert conn.status == 202
    end

    test "extracts session ID from query params", %{post_opts: post_opts} do
      notification =
        build_notification("notifications/message", %{
          "level" => "info",
          "data" => "test"
        })

      {:ok, body} = Message.encode_notification(notification)

      conn =
        :post
        |> conn("/messages?session_id=query-session-456", body)
        |> SSEPlug.call(post_opts)

      assert conn.status == 202
    end

    test "generates session ID if not provided", %{post_opts: post_opts} do
      notification =
        build_notification("notifications/message", %{
          "level" => "info",
          "data" => "test"
        })

      {:ok, body} = Message.encode_notification(notification)

      conn =
        :post
        |> conn("/messages", body)
        |> SSEPlug.call(post_opts)

      assert conn.status == 202
    end
  end
end
