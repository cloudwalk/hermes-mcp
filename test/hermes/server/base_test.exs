defmodule Hermes.Server.BaseTest do
  use Hermes.MCP.Case, async: true

  alias Hermes.MCP.Message
  alias Hermes.Server.Base

  require Message

  @moduletag capture_log: true

  describe "start_link/1" do
    test "starts a server with valid options" do
      transport = start_supervised!(StubTransport)

      assert {:ok, pid} =
               Base.start_link(
                 module: StubServer,
                 name: :named_server,
                 init_arg: :ok,
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
                 init_arg: :ok,
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
      assert {:ok, _} = GenServer.call(server, {:request, error, "123"})
    end

    test "rejects requests when not initialized", %{server: server} do
      request = build_request("tools/list")
      assert {:ok, _} = GenServer.call(server, {:request, request, "not_initialized"})
    end

    test "accept ping requests when not initialized", %{server: server, session_id: session_id} do
      request = build_request("ping")
      assert {:ok, _} = GenServer.call(server, {:request, request, session_id})
    end
  end

  describe "handle_cast/2 for notifications" do
    setup :initialized_server

    test "handles notifications", %{server: server, session_id: session_id} do
      notification = build_notification("notifications/cancelled", %{"requestId" => 1})
      assert :ok = GenServer.cast(server, {:notification, notification, session_id})
    end

    test "handles initialize notification", %{server: server, session_id: session_id} do
      notification = build_notification("notifications/initialized", %{})
      assert :ok = GenServer.cast(server, {:notification, notification, session_id})
    end
  end

  describe "send_notification/3" do
    setup :initialized_server

    test "sends notification to transport", %{server: server} do
      params = %{"logger" => "database", "level" => "error", "data" => %{}}
      assert :ok = Base.send_notification(server, "notifications/message", params)
      # TODO(zoedsoupe): assert on StubTransport
    end
  end
end
