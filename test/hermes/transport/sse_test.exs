defmodule Hermes.Transport.SSETest do
  use ExUnit.Case, async: false

  alias Hermes.Transport.SSE
  alias Hermes.Message

  @moduletag capture_log: true

  setup do
    client =
      start_supervised!(
        {Hermes.Client,
         name: :sse_test,
         transport: SSE,
         client_info: %{"name" => "Hermes.Transport.SSETest", "version" => "1.0.0"}}
      )

    bypass = Bypass.open()

    {:ok, client: client, bypass: bypass}
  end

  describe "start_link/1" do
    test "successfully establishes SSE connection", %{client: client, bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"

      Bypass.expect_once(bypass, "GET", "/sse", fn conn ->
        conn = Plug.Conn.put_resp_header(conn, "content-type", "text/event-stream")
        conn = Plug.Conn.send_chunked(conn, 200)

        {:ok, conn} =
          Plug.Conn.chunk(conn, """
          event: endpoint
          data: /messages/123

          """)

        conn
      end)

      Bypass.expect_once(bypass, "POST", "/messages/123", fn conn ->
        Plug.Conn.resp(conn, 200, "")
      end)

      transport =
        start_supervised!(
          {SSE,
           client: client,
           server: %{
             base_url: server_url,
             sse_path: "/sse"
           }}
        )

      Process.sleep(100)

      SSE.shutdown(transport)
    end
  end

  describe "send_message/2" do
    test "sends message to endpoint after receiving endpoint event", %{
      client: client,
      bypass: bypass
    } do
      server_url = "http://localhost:#{bypass.port}"

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

      Bypass.expect(bypass, "POST", "/messages/123", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ ~s|"method":"initialize"|
        assert {:ok, [req]} = Message.decode(body)
        assert req["method"] == "initialize"

        result = %{
          "result" => %{
            "capabilities" => %{"resources" => %{}, "tools" => %{}, "prompts" => %{}},
            "serverInfo" => %{"name" => "TestServer", "version" => "1.0.0"},
            "protocolVersion" => "2024-11-05"
          }
        }

        assert {:ok, resp} = Message.encode_response(result, req["id"])

        conn = Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        Plug.Conn.resp(conn, 200, resp)
      end)

      transport =
        start_supervised!(
          {SSE,
           client: client,
           server: %{
             base_url: server_url,
             sse_path: "/sse"
           }}
        )

      Process.sleep(300)

      assert :pong = Hermes.Client.ping(client)

      SSE.shutdown(transport)
    end

    test "fails to send message when no endpoint is available", %{client: client, bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"

      # Set up the SSE connection but don't send an endpoint event
      Bypass.expect(bypass, "GET", "/sse", fn conn ->
        conn = Plug.Conn.put_resp_header(conn, "content-type", "text/event-stream")
        conn = Plug.Conn.send_chunked(conn, 200)

        # Keep the connection open
        Process.sleep(5000)
        conn
      end)

      # Start the SSE transport
      {:ok, transport} =
        SSE.start_link(
          client: client,
          server: %{
            base_url: server_url,
            sse_path: "/sse"
          }
        )

      # Try to send a message without having an endpoint
      assert {:error, :not_connected} = SSE.send_message(transport, "test message")

      # Clean up
      SSE.shutdown(transport)
    end

    test "handles HTTP error responses", %{client: client, bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"

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

        # Keep the connection open
        Process.sleep(5000)
        conn
      end)

      # Set up the POST endpoint to return an error
      Bypass.expect(bypass, "POST", "/messages/123", fn conn ->
        Plug.Conn.resp(conn, 500, "Internal Server Error")
      end)

      # Start the SSE transport
      {:ok, transport} =
        SSE.start_link(
          client: client,
          server: %{
            base_url: server_url,
            sse_path: "/sse"
          }
        )

      # Wait for the endpoint event
      assert_receive {:endpoint, "/messages/123"}, 1000

      # Send a message and check for error response
      assert {:error, {:http_error, 500, "Internal Server Error"}} =
               SSE.send_message(transport, "test message")

      # Clean up
      SSE.shutdown(transport)
    end
  end

  describe "handling SSE events" do
    test "processes message events correctly", %{client: client, bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"

      # Create a JSON-RPC message to send
      {:ok, json_message} = Message.encode_request(%{"method" => "ping"}, "1")

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

        # Send a message event
        {:ok, conn} =
          Plug.Conn.chunk(conn, """
          event: message
          data: #{json_message}

          """)

        # Keep the connection open
        Process.sleep(5000)
        conn
      end)

      # Start the SSE transport
      {:ok, transport} =
        SSE.start_link(
          client: client,
          server: %{
            base_url: server_url,
            sse_path: "/sse"
          }
        )

      # Wait for the message to be forwarded to the client
      assert_receive {:message, ^json_message}, 1000

      # Clean up
      SSE.shutdown(transport)
    end

    test "handles server disconnection", %{client: client, bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"

      # Start the SSE transport
      {:ok, transport} =
        SSE.start_link(
          client: client,
          server: %{
            base_url: server_url,
            sse_path: "/sse"
          }
        )

      # Ensure the transport process is linked
      ref = Process.monitor(transport)

      # Trigger a server disconnection
      Bypass.down(bypass)

      # The transport should terminate due to the connection error
      assert_receive {:DOWN, ^ref, :process, ^transport, _}, 5000
    end
  end

  describe "handling headers and options" do
    test "passes custom headers to requests", %{client: client, bypass: bypass} do
      server_url = "http://localhost:#{bypass.port}"

      # Set up the SSE connection
      Bypass.expect(bypass, "GET", "/sse", fn conn ->
        # Verify that custom headers are passed
        assert "application/json" == Plug.Conn.get_req_header(conn, "accept") |> List.first()
        assert "auth-token" == Plug.Conn.get_req_header(conn, "authorization") |> List.first()

        conn = Plug.Conn.put_resp_header(conn, "content-type", "text/event-stream")
        conn = Plug.Conn.send_chunked(conn, 200)

        # Send an endpoint event
        {:ok, conn} =
          Plug.Conn.chunk(conn, """
          event: endpoint
          data: /messages/123

          """)

        # Keep the connection open
        Process.sleep(5000)
        conn
      end)

      # Set up the POST endpoint
      Bypass.expect(bypass, "POST", "/messages/123", fn conn ->
        # Verify that custom headers are passed to POST as well
        assert "application/json" == Plug.Conn.get_req_header(conn, "accept") |> List.first()
        assert "auth-token" == Plug.Conn.get_req_header(conn, "authorization") |> List.first()

        Plug.Conn.resp(conn, 200, "")
      end)

      # Start the SSE transport with custom headers
      {:ok, transport} =
        SSE.start_link(
          client: client,
          server: %{
            base_url: server_url,
            sse_path: "/sse"
          },
          headers: %{
            "accept" => "application/json",
            "authorization" => "auth-token"
          }
        )

      # Wait for the endpoint event
      assert_receive {:endpoint, "/messages/123"}, 1000

      # Send a message
      assert :ok = SSE.send_message(transport, "test message")

      # Clean up
      SSE.shutdown(transport)
    end
  end
end
