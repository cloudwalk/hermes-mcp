defmodule Hermes.Transport.SSETest do
  use ExUnit.Case, async: false

  alias Hermes.MCP.Message
  alias Hermes.Transport.SSE

  @moduletag capture_log: true
  @test_http_opts [max_reconnections: 0]

  setup do
    bypass = Bypass.open()
    Process.group_leader(self(), self())

    {:ok, bypass: bypass}
  end

  describe "start_link/1" do
    test "successfully establishes SSE connection", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"

      # Start a stub client to avoid interference with other tests
      {:ok, stub_client} = StubClient.start_link()

      # Let the SSE connection establish and send an endpoint event
      Bypass.expect(bypass, "GET", "/sse", fn conn ->
        conn = Plug.Conn.put_resp_header(conn, "content-type", "text/event-stream")
        conn = Plug.Conn.send_chunked(conn, 200)

        {:ok, conn} =
          Plug.Conn.chunk(conn, """
          event: endpoint
          data: /messages/123

          """)

        conn
      end)

      # Start the transport manually instead of using start_supervised!
      # This prevents the test framework from killing it abruptly
      {:ok, transport} =
        SSE.start_link(
          client: stub_client,
          server: %{
            base_url: server_url,
            sse_path: "/sse"
          },
          transport_opts: @test_http_opts
        )

      # Give time for the SSE connection to establish and process the event
      Process.sleep(200)

      # force client to initialize
      _ = :sys.get_state(stub_client)
      state = :sys.get_state(transport)
      assert state.message_url != nil
      assert String.ends_with?(to_string(state.message_url), "/messages/123")

      # Clean up
      StubClient.clear_messages()
      # Shut down gracefully
      SSE.shutdown(transport)
      # Allow time for shutdown
      Process.sleep(50)
    end
  end

  describe "send_message/2" do
    test "sends message to endpoint after receiving endpoint event", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"

      # Start a stub client
      {:ok, stub_client} = StubClient.start_link()

      # Set up SSE connection
      Bypass.expect(bypass, "GET", "/sse", fn conn ->
        conn = Plug.Conn.put_resp_header(conn, "content-type", "text/event-stream")
        conn = Plug.Conn.send_chunked(conn, 200)

        {:ok, conn} =
          Plug.Conn.chunk(conn, """
          event: endpoint
          data: /messages/123

          """)

        conn
      end)

      # Set up POST endpoint that will receive messages
      Bypass.expect(bypass, "POST", "/messages/123", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        # Verify we got a message
        assert body =~ "ping"

        # Return a proper response
        conn = Plug.Conn.put_resp_header(conn, "content-type", "application/json")

        # For a ping request, just send back a simple response
        Plug.Conn.resp(conn, 200, ~s|{"jsonrpc":"2.0","id":"1","result":"pong"}|)
      end)

      # Start the transport with our stub client
      {:ok, transport} =
        SSE.start_link(
          client: stub_client,
          server: %{
            base_url: server_url,
            sse_path: "/sse"
          },
          transport_opts: @test_http_opts
        )

      # Give time for the SSE connection to establish
      Process.sleep(200)

      # Verify the transport has received the endpoint
      transport_state = :sys.get_state(transport)
      assert transport_state.message_url != nil
      assert String.ends_with?(to_string(transport_state.message_url), "/messages/123")

      # Send a ping message through the transport
      {:ok, ping_message} = Message.encode_request(%{"method" => "ping", "params" => %{}}, "1")
      assert :ok = SSE.send_message(transport, ping_message)

      # Give time for the response to come back
      Process.sleep(100)

      # Clean up
      StubClient.clear_messages()
      SSE.shutdown(transport)
    end

    test "fails to send message when no endpoint is available", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"

      # Start a stub client for this test
      {:ok, stub_client} = StubClient.start_link()

      # Set up the SSE connection but don't send an endpoint event
      Bypass.expect(bypass, "GET", "/sse", fn conn ->
        conn = Plug.Conn.put_resp_header(conn, "content-type", "text/event-stream")
        Plug.Conn.send_chunked(conn, 200)
      end)

      # Start the SSE transport
      {:ok, transport} =
        SSE.start_link(
          client: stub_client,
          server: %{
            base_url: server_url,
            sse_path: "/sse"
          },
          transport_opts: @test_http_opts
        )

      # Wait for transport to start
      Process.sleep(100)

      # Try to send a message without having an endpoint
      assert {:error, :not_connected} = SSE.send_message(transport, "test message")

      # Clean up
      SSE.shutdown(transport)
      StubClient.clear_messages()
    end

    test "handles HTTP error responses", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"

      # Start a stub client for this test to avoid client termination affecting transport
      {:ok, stub_client} = StubClient.start_link()

      # Set up the SSE connection
      Bypass.expect(bypass, "GET", "/sse", fn conn ->
        conn = Plug.Conn.put_resp_header(conn, "content-type", "text/event-stream")
        conn = Plug.Conn.send_chunked(conn, 200)

        # Send an endpoint event
        {:ok, conn} =
          Plug.Conn.chunk(conn, """
          event: endpoint
          data: /messages/123

          """)

        conn
      end)

      # Set up the POST endpoint to return an error
      Bypass.expect(bypass, "POST", "/messages/123", fn conn ->
        Plug.Conn.resp(conn, 500, "Internal Server Error")
      end)

      # Start the SSE transport
      {:ok, transport} =
        SSE.start_link(
          client: stub_client,
          server: %{
            base_url: server_url,
            sse_path: "/sse"
          },
          transport_opts: @test_http_opts
        )

      # Give the SSE connection time to establish
      Process.sleep(200)

      # Verify the transport has received the endpoint
      transport_state = :sys.get_state(transport)
      assert transport_state.message_url != nil

      # Send a message and check for error response
      assert {:error, {:http_error, 500, "Internal Server Error"}} =
               SSE.send_message(transport, "test message")

      # Clean up
      SSE.shutdown(transport)
      StubClient.clear_messages()
    end
  end

  describe "handling SSE events" do
    test "processes message events correctly", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"
      test_message = "test message data"
      {:ok, stub_client} = StubClient.start_link()

      Bypass.expect(bypass, "GET", "/sse", fn conn ->
        conn = Plug.Conn.put_resp_header(conn, "content-type", "text/event-stream")
        conn = Plug.Conn.send_chunked(conn, 200)

        {:ok, conn} =
          Plug.Conn.chunk(conn, """
          event: endpoint
          data: /messages/123

          """)

        Process.sleep(50)

        {:ok, conn} =
          Plug.Conn.chunk(conn, """
          event: message
          data: #{test_message}

          """)

        conn
      end)

      {:ok, transport} =
        SSE.start_link(
          client: stub_client,
          server: %{
            base_url: server_url,
            sse_path: "/sse"
          },
          transport_opts: @test_http_opts
        )

      Process.sleep(300)

      transport_state = :sys.get_state(transport)
      assert transport_state.message_url != nil

      messages = StubClient.get_messages()
      assert test_message in messages

      StubClient.clear_messages()
      SSE.shutdown(transport)
    end

    test "processes ping events correctly", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"
      ping_message = ~s({"jsonrpc":"2.0","method":"ping","id":"ping-123"})
      {:ok, stub_client} = StubClient.start_link()

      Bypass.expect(bypass, "GET", "/sse", fn conn ->
        conn = Plug.Conn.put_resp_header(conn, "content-type", "text/event-stream")
        conn = Plug.Conn.send_chunked(conn, 200)

        {:ok, conn} =
          Plug.Conn.chunk(conn, """
          event: endpoint
          data: /messages/123

          """)

        Process.sleep(100)

        assert {:ok, conn} =
                 Plug.Conn.chunk(conn, """
                 event: ping
                 data: #{ping_message}

                 """)

        Process.sleep(300)
        conn
      end)

      assert {:ok, transport} =
               SSE.start_link(
                 client: stub_client,
                 server: %{
                   base_url: server_url,
                   sse_path: "/sse"
                 },
                 transport_opts: @test_http_opts
               )

      Process.sleep(500)

      messages = StubClient.get_messages()
      assert ping_message in messages

      StubClient.clear_messages()
      SSE.shutdown(transport)
    end

    test "processes reconnect events gracefully", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"
      {:ok, stub_client} = StubClient.start_link()

      connection_agent = start_supervised!({Agent, fn -> %{reconnect_sent: false} end})

      Bypass.expect(bypass, "GET", "/sse", fn conn ->
        conn = Plug.Conn.put_resp_header(conn, "content-type", "text/event-stream")
        conn = Plug.Conn.send_chunked(conn, 200)

        {:ok, conn} =
          Plug.Conn.chunk(conn, """
          event: endpoint
          data: /messages/123

          """)

        reconnect_sent = Agent.get(connection_agent, fn state -> state.reconnect_sent end)

        if reconnect_sent do
          Process.sleep(100)
          conn
        else
          Process.sleep(50)

          {:ok, conn} =
            Plug.Conn.chunk(conn, """
            event: reconnect
            data: {"reason":"timeout prevention"}

            """)

          Agent.update(connection_agent, fn state -> %{state | reconnect_sent: true} end)
          Plug.Conn.halt(conn)
        end
      end)

      assert {:ok, transport} =
               SSE.start_link(
                 client: stub_client,
                 server: %{
                   base_url: server_url,
                   sse_path: "/sse"
                 },
                 transport_opts: @test_http_opts
               )

      Process.sleep(300)

      StubClient.clear_messages()
      SSE.shutdown(transport)
    end

    test "handles server disconnection", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"

      # Start a stub client
      {:ok, stub_client} = StubClient.start_link()

      # Set up the SSE connection - bypass is needed but we don't assert
      # any specific behavior since we're testing disconnection
      Bypass.expect(bypass, fn conn ->
        Plug.Conn.resp(conn, 200, "")
      end)

      # Start the SSE transport with 0 reconnection attempts
      {:ok, transport} =
        SSE.start_link(
          client: stub_client,
          server: %{
            base_url: server_url,
            sse_path: "/sse"
          },
          transport_opts: [max_reconnections: 0]
        )

      # Allow time for the initial connection attempt
      Process.sleep(100)

      # Directly call shutdown on the transport to trigger clean termination
      SSE.shutdown(transport)

      # Give it a moment to shut down
      Process.sleep(100)

      # Verify the process is no longer alive
      refute Process.alive?(transport)

      # Clean up
      StubClient.clear_messages()
    end
  end

  describe "handling headers and options" do
    test "passes custom headers to requests", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"
      {:ok, stub_client} = StubClient.start_link()

      Bypass.expect(bypass, "GET", "/sse", fn conn ->
        assert "auth-token" == conn |> Plug.Conn.get_req_header("authorization") |> List.first()
        conn = Plug.Conn.put_resp_header(conn, "content-type", "text/event-stream")
        conn = Plug.Conn.send_chunked(conn, 200)
        {:ok, conn} = Plug.Conn.chunk(conn, "event: endpoint\ndata: /messages/123\n\n")
        conn
      end)

      Bypass.expect(bypass, "POST", "/messages/123", fn conn ->
        assert "application/json" == conn |> Plug.Conn.get_req_header("accept") |> List.first()
        assert "auth-token" == conn |> Plug.Conn.get_req_header("authorization") |> List.first()
        Plug.Conn.resp(conn, 200, "")
      end)

      {:ok, transport} =
        SSE.start_link(
          client: stub_client,
          server: %{
            base_url: server_url,
            sse_path: "/sse"
          },
          headers: %{
            "accept" => "application/json",
            "authorization" => "auth-token"
          },
          transport_opts: @test_http_opts
        )

      Process.sleep(200)

      transport_state = :sys.get_state(transport)
      assert transport_state.message_url != nil
      assert :ok = SSE.send_message(transport, "test message")

      SSE.shutdown(transport)
      StubClient.clear_messages()
    end
  end

  describe "handling endpoint URLs" do
    test "properly handles relative endpoint URLs", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}/mcp"
      {:ok, stub_client} = StubClient.start_link()

      Bypass.expect(bypass, "GET", "/mcp/sse", fn conn ->
        conn = Plug.Conn.put_resp_header(conn, "content-type", "text/event-stream")
        conn = Plug.Conn.send_chunked(conn, 200)
        {:ok, conn} = Plug.Conn.chunk(conn, "event: endpoint\ndata: /messages/123\n\n")
        conn
      end)

      Bypass.expect(bypass, "POST", "/mcp/messages/123", fn conn ->
        Plug.Conn.resp(conn, 200, "")
      end)

      {:ok, transport} =
        SSE.start_link(
          client: stub_client,
          server: %{
            base_url: server_url,
            sse_path: "/sse"
          },
          transport_opts: @test_http_opts
        )

      Process.sleep(200)

      transport_state = :sys.get_state(transport)
      assert transport_state.message_url == "#{server_url}/messages/123"
      assert :ok = SSE.send_message(transport, "test message")

      SSE.shutdown(transport)
      StubClient.clear_messages()
    end

    test "properly handles absolute endpoint URLs", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}/mcp"
      absolute_endpoint = "http://api.example.com/messages/session-123"
      {:ok, stub_client} = StubClient.start_link()

      Bypass.expect(bypass, "GET", "/mcp/sse", fn conn ->
        conn = Plug.Conn.put_resp_header(conn, "content-type", "text/event-stream")
        conn = Plug.Conn.send_chunked(conn, 200)
        {:ok, conn} = Plug.Conn.chunk(conn, "event: endpoint\ndata: #{absolute_endpoint}\n\n")
        conn
      end)

      {:ok, transport} =
        SSE.start_link(
          client: stub_client,
          server: %{
            base_url: server_url,
            sse_path: "/sse"
          },
          transport_opts: @test_http_opts
        )

      Process.sleep(200)

      transport_state = :sys.get_state(transport)
      assert transport_state.message_url == absolute_endpoint

      SSE.shutdown(transport)
      StubClient.clear_messages()
    end

    test "handles path duplication from MCP servers", %{bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}/mcp"
      duplicate_path = "/mcp/messages/123"
      {:ok, stub_client} = StubClient.start_link()

      Bypass.expect(bypass, "GET", "/mcp/sse", fn conn ->
        conn = Plug.Conn.put_resp_header(conn, "content-type", "text/event-stream")
        conn = Plug.Conn.send_chunked(conn, 200)
        {:ok, conn} = Plug.Conn.chunk(conn, "event: endpoint\ndata: #{duplicate_path}\n\n")
        conn
      end)

      Bypass.expect(bypass, "POST", "/mcp/messages/123", fn conn ->
        Plug.Conn.resp(conn, 200, "")
      end)

      {:ok, transport} =
        SSE.start_link(
          client: stub_client,
          server: %{
            base_url: server_url,
            sse_path: "/sse"
          },
          transport_opts: @test_http_opts
        )

      Process.sleep(200)

      transport_state = :sys.get_state(transport)
      assert transport_state.message_url == "#{server_url}/messages/123"
      assert not String.contains?(transport_state.message_url, "/mcp/mcp/")
      assert :ok = SSE.send_message(transport, "test message")

      SSE.shutdown(transport)
      StubClient.clear_messages()
    end
  end
end
