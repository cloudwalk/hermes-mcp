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
      assert {:ok, _} = GenServer.call(server, {:request, error, "123", %{}})
    end

    test "rejects requests when not initialized", %{server: server} do
      request = build_request("tools/list", 123)
      assert {:ok, _} = GenServer.call(server, {:request, request, "not_initialized", %{}})
    end

    test "accept ping requests when not initialized", %{server: server, session_id: session_id} do
      request = build_request("ping", 123)
      assert {:ok, _} = GenServer.call(server, {:request, request, session_id, %{}})
    end
  end

  describe "handle_cast/2 for notifications" do
    setup :initialized_server

    test "handles notifications", %{server: server, session_id: session_id} do
      notification = build_notification("notifications/cancelled", %{"requestId" => 1})
      assert :ok = GenServer.cast(server, {:notification, notification, session_id, %{}})
    end

    test "handles initialize notification", %{server: server, session_id: session_id} do
      notification = build_notification("notifications/initialized", %{})
      assert :ok = GenServer.cast(server, {:notification, notification, session_id, %{}})
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

  describe "batch request handling" do
    setup :initialized_server

    test "processes batch with multiple requests", %{server: server, session_id: session_id} do
      batch = [
        build_request("ping", %{}, 1),
        build_request("tools/list", %{}, 2)
      ]

      assert {:batch, responses} = GenServer.call(server, {:batch_request, batch, session_id, %{}})
      assert length(responses) == 2

      ids = Enum.map(responses, & &1["id"])
      assert 1 in ids
      assert 2 in ids

      ping_response = Enum.find(responses, &(&1["id"] == 1))
      assert ping_response["result"] == %{}

      tools_response = Enum.find(responses, &(&1["id"] == 2))
      assert tools_response["result"]["tools"]
    end

    test "returns error for empty batch", %{server: server, session_id: session_id} do
      assert {:error, error} = GenServer.call(server, {:batch_request, [], session_id, %{}})
      assert error.reason == :invalid_request
      assert error.data.message == "Batch cannot be empty"
    end

    test "returns error when initialize is in batch", %{server: server, session_id: session_id} do
      batch = [
        init_request("2025-03-26", %{"name" => "TestClient", "version" => "1.0.0"}),
        build_request("ping", %{}, 2)
      ]

      assert {:error, error} = GenServer.call(server, {:batch_request, batch, session_id, %{}})
      assert error.reason == :invalid_request
      assert error.data.message == "Initialize request cannot be part of a batch"
    end

    test "handles mixed requests and notifications", %{server: server, session_id: session_id} do
      batch = [
        build_request("ping", %{}, 1),
        build_notification("notifications/message", %{"level" => "info", "data" => "test"}),
        build_request("tools/list", %{}, 2)
      ]

      assert {:batch, responses} = GenServer.call(server, {:batch_request, batch, session_id, %{}})
      assert length(responses) == 2
      assert Enum.all?(responses, &Map.has_key?(&1, "id"))
    end

    test "handles batch with all notifications", %{server: server, session_id: session_id} do
      batch = [
        build_notification("notifications/message", %{"level" => "info", "data" => "test1"}),
        build_notification("notifications/message", %{"level" => "debug", "data" => "test2"})
      ]

      assert {:batch, responses} = GenServer.call(server, {:batch_request, batch, session_id, %{}})
      assert responses == []
    end

    test "handles errors in individual batch requests", %{server: server, session_id: session_id} do
      batch = [
        build_request("ping", %{}, 1),
        build_request("unknown/method", %{}, 2),
        build_request("tools/list", %{}, 3)
      ]

      assert {:batch, responses} = GenServer.call(server, {:batch_request, batch, session_id, %{}})
      assert length(responses) == 3

      error_response = Enum.find(responses, &(&1["id"] == 2))
      assert error_response["error"]["code"] == -32_601
    end

    test "maintains response order matching request order", %{server: server, session_id: session_id} do
      batch = [
        build_request("tools/list", %{}, "first"),
        build_request("ping", %{}, "second"),
        build_request("prompts/list", %{}, "third")
      ]

      assert {:batch, responses} = GenServer.call(server, {:batch_request, batch, session_id, %{}})

      assert [
               %{"id" => "first"},
               %{"id" => "second"},
               %{"id" => "third"}
             ] = responses
    end

    test "handles batch requests in non-initialized session", %{server: server} do
      batch = [
        build_request("tools/list", %{}, 1),
        build_request("prompts/list", %{}, 2)
      ]

      assert {:batch, responses} = GenServer.call(server, {:batch_request, batch, "new_session", %{}})
      assert length(responses) == 2

      assert Enum.all?(responses, &(&1["error"]["code"] == -32_600))
    end
  end
end
