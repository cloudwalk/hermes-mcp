defmodule Hermes.Server.BaseTest do
  use MCPTest.Case

  alias Hermes.MCP.Message
  alias Hermes.Server.Base

  require Message

  @moduletag capture_log: true

  describe "start_link/1" do
    test "starts a server with valid options" do
      assert {:ok, pid} = Base.start_link(module: TestServer, transport: [layer: MCPTest.MockTransport])
      assert Process.alive?(pid)
    end

    test "starts a named server" do
      assert {:ok, _pid} =
               Base.start_link(module: TestServer, name: :named_server, transport: [layer: MCPTest.MockTransport])

      assert pid = Process.whereis(:named_server)
      assert Process.alive?(pid)
    end
  end

  describe "handle_call/3 for messages" do
    test "handles initialization request" do
      ctx = server_with_mock_transport()
      server = ctx.server

      request =
        init_request(%{
          "protocolVersion" => "2025-03-26",
          "capabilities" => %{"roots" => %{}},
          "clientInfo" => %{
            "name" => "Test Client",
            "version" => "1.0.0"
          }
        })

      {:ok, encoded} = Message.encode_request(request, 1)
      {:ok, response} = GenServer.call(server, {:message, encoded})
      {:ok, [decoded]} = Message.decode(response)

      assert_mcp_response(decoded, %{
        "protocolVersion" => "2025-03-26",
        "serverInfo" => %{"name" => "Test Server", "version" => "1.0.0"},
        "capabilities" => %{"tools" => %{"listChanged" => true}}
      })
    end

    @tag skip: true
    @tag server: true
    test "handles errors", %{server: server} do
      error = %{
        "error" => %{
          "data" => %{},
          "message" => "got wrong",
          "code" => -32_000
        }
      }

      assert {:ok, encoded} = Message.encode_error(error, 1)
      assert_raise CaseClauseError, fn -> GenServer.call(server, {:message, encoded}) end
    end

    test "rejects requests when not initialized" do
      ctx = server_with_mock_transport()
      server = ctx.server

      request = tools_list_request()
      {:ok, encoded} = Message.encode_request(request, 1)
      {:ok, response} = GenServer.call(server, {:message, encoded})
      {:ok, [decoded]} = Message.decode(response)

      assert_mcp_error(decoded, -32_600)
    end

    @tag skip: "TODO: Server implementation should allow ping when not initialized per MCP spec"
    test "accept ping requests when not initialized" do
      ctx = server_with_mock_transport()
      server = ctx.server

      request = ping_request()
      {:ok, encoded} = Message.encode_request(request, 1)
      {:ok, response} = GenServer.call(server, {:message, encoded})
      {:ok, [decoded]} = Message.decode(response)

      assert_mcp_response(decoded, %{})
    end
  end

  describe "handle_call/2 for notifications" do
    @tag server: true
    test "handles notifications", %{server: server} do
      notification = build_notification("notifications/cancelled", %{"requestId" => 1})
      {:ok, encoded} = Message.encode_notification(notification)
      {:ok, nil} = GenServer.call(server, {:message, encoded})
    end

    test "handles initialize notification" do
      # Use uninitialized server, then initialize it
      ctx = server_with_mock_transport()
      server = ctx.server

      notification = build_notification("notifications/initialized", %{})
      {:ok, encoded} = Message.encode_notification(notification)
      {:ok, nil} = GenServer.call(server, {:message, encoded})

      request = tools_list_request()
      {:ok, encoded} = Message.encode_request(request, 1)
      {:ok, response} = GenServer.call(server, {:message, encoded})
      {:ok, [decoded]} = Message.decode(response)

      assert_mcp_response(decoded, %{"tools" => []})
    end
  end

  describe "send_notification/3" do
    @tag server: true
    test "sends notification to transport", %{server: server} do
      params = %{"logger" => "database", "level" => "error", "data" => %{}}
      assert :ok = Base.send_notification(server, "notifications/message", params)
      messages = MCPTest.MockTransport.get_messages(:mock_server_transport)
      assert length(messages) == 1
    end
  end
end
