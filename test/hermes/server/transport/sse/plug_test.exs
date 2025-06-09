defmodule Hermes.Server.Transport.SSE.PlugTest do
  use Hermes.MCP.Case, async: true
  use Plug.Test

  alias Hermes.MCP.Error
  alias Hermes.MCP.Message
  alias Hermes.Server.Registry
  alias Hermes.Server.Transport.SSE
  alias Hermes.Server.Transport.SSE.Plug, as: SSEPlug

  @sse_opts SSEPlug.init(server: StubServer, mode: :sse)
  @post_opts SSEPlug.init(server: StubServer, mode: :post)

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

    test "initializes with valid options" do
      opts = SSEPlug.init(server: StubServer, mode: :sse, timeout: 5000)

      assert %{
               transport: transport,
               mode: :sse,
               timeout: 5000
             } = opts

      assert transport == Registry.transport(StubServer, :sse)
    end
  end

  describe "SSE endpoint" do
    setup do
      registry = Registry
      name = registry.transport(StubServer, :sse)
      {:ok, transport} = start_supervised({SSE, server: StubServer, name: name, registry: registry})

      %{transport: transport}
    end

    test "GET request establishes SSE connection", %{transport: _transport} do
      conn =
        :get
        |> conn("/sse")
        |> put_req_header("accept", "text/event-stream")
        |> SSEPlug.call(@sse_opts)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/event-stream"]
      assert get_resp_header(conn, "cache-control") == ["no-cache"]

      # Should have sent endpoint event
      assert conn.resp_body =~ "event: endpoint"
      assert conn.resp_body =~ "data: /messages"
    end

    test "GET request without SSE accept header returns error" do
      conn =
        :get
        |> conn("/sse")
        |> put_req_header("accept", "application/json")
        |> SSEPlug.call(@sse_opts)

      assert conn.status == 406
      assert conn.resp_body =~ "Accept header must include text/event-stream"
    end

    test "non-GET request returns method not allowed" do
      conn =
        :post
        |> conn("/sse")
        |> SSEPlug.call(@sse_opts)

      assert conn.status == 405
      assert conn.resp_body =~ "Method not allowed"
    end
  end

  describe "POST endpoint" do
    setup do
      registry = Registry
      name = registry.transport(StubServer, :sse)
      {:ok, transport} = start_supervised({SSE, server: StubServer, name: name, registry: registry})

      # Register a mock server
      server_name = registry.server(StubServer)
      {:ok, mock_server} = start_supervised({MockServer, name: server_name})

      %{transport: transport, mock_server: mock_server}
    end

    test "POST request with valid JSON returns response", %{mock_server: _} do
      request = build_request("test/method", %{"param" => "value"})
      {:ok, body} = Message.encode_request(request, 1)

      conn =
        :post
        |> conn("/messages", body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-session-id", "test-session")
        |> SSEPlug.call(@post_opts)

      assert conn.status == 200
      assert conn.resp_body =~ "result"
    end

    test "POST request with notification returns 202", %{mock_server: _} do
      notification = build_notification("test/notification", %{"data" => "test"})
      {:ok, body} = Message.encode_notification(notification)

      conn =
        :post
        |> conn("/messages", body)
        |> put_req_header("content-type", "application/json")
        |> SSEPlug.call(@post_opts)

      assert conn.status == 202
      assert conn.resp_body == "{}"
    end

    test "POST request with invalid JSON returns error" do
      conn =
        :post
        |> conn("/messages", "invalid json")
        |> put_req_header("content-type", "application/json")
        |> SSEPlug.call(@post_opts)

      assert conn.status == 400

      {:ok, [response]} = Message.decode(conn.resp_body)
      assert Message.is_error(response)
      assert response["error"]["code"] == Error.protocol_code(:parse_error)
    end

    test "non-POST request returns method not allowed" do
      conn =
        :get
        |> conn("/messages")
        |> SSEPlug.call(@post_opts)

      assert conn.status == 405
      assert conn.resp_body =~ "Method not allowed"
    end
  end

  describe "session ID extraction" do
    setup do
      registry = Registry
      name = registry.transport(StubServer, :sse)
      {:ok, transport} = start_supervised({SSE, server: StubServer, name: name, registry: registry})

      %{transport: transport}
    end

    test "extracts session ID from header" do
      notification = build_notification("test/notification", %{})
      {:ok, body} = Message.encode_notification(notification)

      conn =
        :post
        |> conn("/messages", body)
        |> put_req_header("x-session-id", "header-session-123")
        |> SSEPlug.call(@post_opts)

      assert conn.status == 202
    end

    test "extracts session ID from query params" do
      notification = build_notification("test/notification", %{})
      {:ok, body} = Message.encode_notification(notification)

      conn =
        :post
        |> conn("/messages?session_id=query-session-456", body)
        |> SSEPlug.call(@post_opts)

      assert conn.status == 202
    end

    test "generates session ID if not provided" do
      notification = build_notification("test/notification", %{})
      {:ok, body} = Message.encode_notification(notification)

      conn =
        :post
        |> conn("/messages", body)
        |> SSEPlug.call(@post_opts)

      assert conn.status == 202
    end
  end

  # Mock server for testing
  defmodule MockServer do
    @moduledoc false
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, :ok, opts)
    end

    def init(:ok) do
      {:ok, %{}}
    end

    def handle_call({:request, _message, _session_id}, _from, state) do
      response = Jason.encode!(%{result: %{data: "test response"}})
      {:reply, {:ok, response}, state}
    end

    def handle_cast({:notification, _message, _session_id}, state) do
      {:noreply, state}
    end
  end
end
