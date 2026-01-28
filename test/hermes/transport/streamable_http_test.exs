defmodule Hermes.Transport.StreamableHTTPTest do
  use ExUnit.Case, async: false

  alias Hermes.MCP.Message
  alias Hermes.Transport.StreamableHTTP

  @moduletag capture_log: true
  @test_http_opts [max_reconnections: 0]

  setup do
    bypass = Bypass.open()
    Process.group_leader(self(), self())

    {:ok, bypass: bypass}
  end

  describe "start_link/1" do
    test "successfully starts with valid options", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"

      {:ok, stub_client} = StubClient.start_link()

      {:ok, transport} =
        StreamableHTTP.start_link(
          client: stub_client,
          base_url: server_url,
          mcp_path: "/mcp",
          transport_opts: @test_http_opts
        )

      Process.sleep(100)

      assert Process.alive?(transport)

      state = :sys.get_state(transport)
      assert state.mcp_url.path == "/mcp"
      assert state.session_id == nil

      StreamableHTTP.shutdown(transport)
      StubClient.clear_messages()
    end

    test "uses default mcp_path when not specified", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"
      {:ok, stub_client} = StubClient.start_link()

      {:ok, transport} =
        StreamableHTTP.start_link(
          client: stub_client,
          base_url: server_url,
          transport_opts: @test_http_opts
        )

      Process.sleep(100)

      state = :sys.get_state(transport)
      assert state.mcp_url.path == "/"

      StreamableHTTP.shutdown(transport)
      StubClient.clear_messages()
    end
  end

  describe "send_message/2" do
    test "sends HTTP POST request with JSON response", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"
      {:ok, stub_client} = StubClient.start_link()

      Bypass.expect(bypass, "POST", "/mcp", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert body =~ "ping"

        conn = Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        Plug.Conn.resp(conn, 200, ~s|{"jsonrpc":"2.0","id":"1","result":{}}|)
      end)

      {:ok, transport} =
        StreamableHTTP.start_link(
          client: stub_client,
          base_url: server_url,
          mcp_path: "/mcp",
          transport_opts: @test_http_opts
        )

      Process.sleep(100)

      {:ok, ping_message} =
        Message.encode_request(%{"method" => "ping", "params" => %{}}, "1")

      assert :ok = StreamableHTTP.send_message(transport, ping_message)

      Process.sleep(100)

      messages = StubClient.get_messages()
      assert length(messages) > 0
      assert List.first(messages) =~ "result"

      StreamableHTTP.shutdown(transport)
      StubClient.clear_messages()
    end

    test "handles 202 Accepted response", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"
      {:ok, stub_client} = StubClient.start_link()

      Bypass.expect(bypass, "POST", "/mcp", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ "initialized"

        Plug.Conn.resp(conn, 202, "")
      end)

      {:ok, transport} =
        StreamableHTTP.start_link(
          client: stub_client,
          base_url: server_url,
          mcp_path: "/mcp",
          transport_opts: @test_http_opts
        )

      Process.sleep(100)

      notification = ~s|{"jsonrpc":"2.0","method":"notifications/initialized"}|
      assert :ok = StreamableHTTP.send_message(transport, notification)

      Process.sleep(100)

      StreamableHTTP.shutdown(transport)
      StubClient.clear_messages()
    end

    test "handles SSE response", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"
      {:ok, stub_client} = StubClient.start_link()

      Bypass.expect(bypass, "POST", "/mcp", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ "ping"

        conn = Plug.Conn.put_resp_header(conn, "content-type", "text/event-stream")
        sse_data = ~s(data: {"jsonrpc":"2.0","id":"1","result":{}}\n\n)
        Plug.Conn.resp(conn, 200, sse_data)
      end)

      {:ok, transport} =
        StreamableHTTP.start_link(
          client: stub_client,
          base_url: server_url,
          mcp_path: "/mcp",
          transport_opts: @test_http_opts
        )

      Process.sleep(100)

      {:ok, ping_message} =
        Message.encode_request(%{"method" => "ping", "params" => %{}}, "1")

      assert :ok = StreamableHTTP.send_message(transport, ping_message)

      Process.sleep(200)

      messages = StubClient.get_messages()
      assert length(messages) > 0

      StreamableHTTP.shutdown(transport)
      StubClient.clear_messages()
    end

    test "handles HTTP error responses", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"
      {:ok, stub_client} = StubClient.start_link()

      Bypass.expect(bypass, "POST", "/mcp", fn conn ->
        Plug.Conn.resp(conn, 500, "Internal Server Error")
      end)

      {:ok, transport} =
        StreamableHTTP.start_link(
          client: stub_client,
          base_url: server_url,
          mcp_path: "/mcp",
          transport_opts: @test_http_opts
        )

      Process.sleep(100)

      assert {:error, {:http_error, 500, "Internal Server Error"}} =
               StreamableHTTP.send_message(transport, "test message")

      StreamableHTTP.shutdown(transport)
      StubClient.clear_messages()
    end

    test "handles unsupported content type", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"
      {:ok, stub_client} = StubClient.start_link()

      Bypass.expect(bypass, "POST", "/mcp", fn conn ->
        conn = Plug.Conn.put_resp_header(conn, "content-type", "text/html")
        Plug.Conn.resp(conn, 200, "<html>Not JSON or SSE</html>")
      end)

      {:ok, transport} =
        StreamableHTTP.start_link(
          client: stub_client,
          base_url: server_url,
          mcp_path: "/mcp",
          transport_opts: @test_http_opts
        )

      Process.sleep(100)

      assert {:error, {:unsupported_content_type, "text/html"}} =
               StreamableHTTP.send_message(transport, "test message")

      StreamableHTTP.shutdown(transport)
      StubClient.clear_messages()
    end
  end

  describe "session management" do
    test "handles session ID from response headers", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"
      {:ok, stub_client} = StubClient.start_link()
      session_id = "test-session-123"

      Bypass.expect_once(bypass, "POST", "/mcp", fn conn ->
        conn =
          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.put_resp_header("mcp-session-id", session_id)

        Plug.Conn.resp(conn, 200, ~s|{"jsonrpc":"2.0","id":"1","result":{}}|)
      end)

      Bypass.expect(bypass, "DELETE", "/mcp", fn conn ->
        assert [^session_id] = Plug.Conn.get_req_header(conn, "mcp-session-id")
        Plug.Conn.resp(conn, 200, "")
      end)

      {:ok, transport} =
        StreamableHTTP.start_link(
          client: stub_client,
          base_url: server_url,
          mcp_path: "/mcp",
          transport_opts: @test_http_opts
        )

      Process.sleep(100)

      {:ok, ping_message} =
        Message.encode_request(%{"method" => "ping", "params" => %{}}, "1")

      assert :ok = StreamableHTTP.send_message(transport, ping_message)

      Process.sleep(100)

      state = :sys.get_state(transport)
      assert state.session_id == session_id

      StreamableHTTP.shutdown(transport)
      StubClient.clear_messages()
    end

    test "includes session ID in subsequent requests", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"
      {:ok, stub_client} = StubClient.start_link()
      session_id = "test-session-456"

      Bypass.stub(bypass, "POST", "/mcp", fn conn ->
        session_headers = Plug.Conn.get_req_header(conn, "mcp-session-id")

        case session_headers do
          [] ->
            conn =
              conn
              |> Plug.Conn.put_resp_header("content-type", "application/json")
              |> Plug.Conn.put_resp_header("mcp-session-id", session_id)

            Plug.Conn.resp(conn, 200, ~s|{"jsonrpc":"2.0","id":"1","result":{}}|)

          [^session_id] ->
            conn =
              Plug.Conn.put_resp_header(conn, "content-type", "application/json")

            Plug.Conn.resp(conn, 200, ~s|{"jsonrpc":"2.0","id":"2","result":{}}|)
        end
      end)

      Bypass.stub(bypass, "DELETE", "/mcp", fn conn ->
        assert [^session_id] = Plug.Conn.get_req_header(conn, "mcp-session-id")
        Plug.Conn.resp(conn, 200, "")
      end)

      {:ok, transport} =
        StreamableHTTP.start_link(
          client: stub_client,
          base_url: server_url,
          mcp_path: "/mcp",
          transport_opts: @test_http_opts
        )

      Process.sleep(100)

      {:ok, first_message} =
        Message.encode_request(%{"method" => "ping", "params" => %{}}, "1")

      assert :ok = StreamableHTTP.send_message(transport, first_message)

      Process.sleep(100)

      {:ok, second_message} =
        Message.encode_request(%{"method" => "ping", "params" => %{}}, "2")

      assert :ok = StreamableHTTP.send_message(transport, second_message)

      Process.sleep(100)

      StreamableHTTP.shutdown(transport)
      StubClient.clear_messages()
    end
  end

  describe "headers and options" do
    test "passes custom headers to requests", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"
      {:ok, stub_client} = StubClient.start_link()

      Bypass.expect(bypass, "POST", "/mcp", fn conn ->
        assert "auth-token" ==
                 conn |> Plug.Conn.get_req_header("authorization") |> List.first()

        assert "application/json, text/event-stream" ==
                 conn |> Plug.Conn.get_req_header("accept") |> List.first()

        conn = Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        Plug.Conn.resp(conn, 200, ~s|{"jsonrpc":"2.0","id":"1","result":{}}|)
      end)

      {:ok, transport} =
        StreamableHTTP.start_link(
          client: stub_client,
          base_url: server_url,
          mcp_path: "/mcp",
          headers: %{
            "authorization" => "auth-token"
          },
          transport_opts: @test_http_opts
        )

      Process.sleep(100)

      {:ok, ping_message} =
        Message.encode_request(%{"method" => "ping", "params" => %{}}, "1")

      assert :ok = StreamableHTTP.send_message(transport, ping_message)

      Process.sleep(100)

      StreamableHTTP.shutdown(transport)
      StubClient.clear_messages()
    end

    test "handles custom mcp_path", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"
      custom_path = "/api/v1/mcp"
      {:ok, stub_client} = StubClient.start_link()

      Bypass.expect(bypass, "POST", "/api/v1/mcp", fn conn ->
        conn = Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        Plug.Conn.resp(conn, 200, ~s|{"jsonrpc":"2.0","id":"1","result":{}}|)
      end)

      {:ok, transport} =
        StreamableHTTP.start_link(
          client: stub_client,
          base_url: server_url,
          mcp_path: custom_path,
          transport_opts: @test_http_opts
        )

      Process.sleep(100)

      state = :sys.get_state(transport)
      assert state.mcp_url.path == custom_path

      {:ok, ping_message} =
        Message.encode_request(%{"method" => "ping", "params" => %{}}, "1")

      assert :ok = StreamableHTTP.send_message(transport, ping_message)

      Process.sleep(100)

      StreamableHTTP.shutdown(transport)
      StubClient.clear_messages()
    end

    test "sends per-request headers via opts parameter", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"
      {:ok, stub_client} = StubClient.start_link()

      Bypass.expect(bypass, "POST", "/mcp", fn conn ->
        # Verify transport-level header is present
        assert "Bearer base-token" ==
                 conn |> Plug.Conn.get_req_header("authorization") |> List.first()

        # Verify per-request header is present
        assert "request-123" ==
                 conn |> Plug.Conn.get_req_header("x-request-id") |> List.first()

        # Verify per-request header overrides transport-level header
        assert "request-specific" ==
                 conn |> Plug.Conn.get_req_header("x-client-version") |> List.first()

        conn = Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        Plug.Conn.resp(conn, 200, ~s|{"jsonrpc":"2.0","id":"1","result":{}}|)
      end)

      {:ok, transport} =
        StreamableHTTP.start_link(
          client: stub_client,
          base_url: server_url,
          mcp_path: "/mcp",
          headers: %{
            "authorization" => "Bearer base-token",
            "x-client-version" => "1.0.0"
          },
          transport_opts: @test_http_opts
        )

      Process.sleep(100)

      {:ok, ping_message} =
        Message.encode_request(%{"method" => "ping", "params" => %{}}, "1")

      # Test new opts-based header functionality
      per_request_headers = %{
        "x-request-id" => "request-123",
        # This should override transport header
        "x-client-version" => "request-specific"
      }

      assert :ok = StreamableHTTP.send_message(transport, ping_message, headers: per_request_headers)

      Process.sleep(100)

      StreamableHTTP.shutdown(transport)
      StubClient.clear_messages()
    end
  end

  describe "error handling" do
    test "handles network connection failures", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"
      {:ok, stub_client} = StubClient.start_link()

      Bypass.down(bypass)

      {:ok, transport} =
        StreamableHTTP.start_link(
          client: stub_client,
          base_url: server_url,
          mcp_path: "/mcp",
          transport_opts: @test_http_opts
        )

      Process.sleep(100)

      assert {:error, _reason} =
               StreamableHTTP.send_message(transport, "test message")

      StreamableHTTP.shutdown(transport)
      StubClient.clear_messages()
    end
  end

  describe "shutdown" do
    test "gracefully shuts down transport", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"
      {:ok, stub_client} = StubClient.start_link()

      {:ok, transport} =
        StreamableHTTP.start_link(
          client: stub_client,
          base_url: server_url,
          mcp_path: "/mcp",
          transport_opts: @test_http_opts
        )

      Process.sleep(100)

      assert Process.alive?(transport)

      StreamableHTTP.shutdown(transport)

      Process.sleep(100)

      refute Process.alive?(transport)

      StubClient.clear_messages()
    end
  end
end
