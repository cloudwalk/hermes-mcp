defmodule Hermes.Server.BaseTest do
  use ExUnit.Case, async: true

  alias Hermes.Server.Base
  alias Hermes.Server.MockTransport

  @moduletag capture_log: true

  setup do
    start_supervised!(MockTransport)

    server =
      start_supervised!(
        {Base, module: TestServer, name: :test_server, transport: [layer: MockTransport, name: :mock_server_transport]}
      )

    MockTransport.clear_messages()

    %{server: server}
  end

  describe "start_link/1" do
    test "starts a server with valid options" do
      assert {:ok, pid} = Base.start_link(module: TestServer, transport: [layer: MockTransport])
      assert Process.alive?(pid)
    end

    test "starts a named server" do
      assert {:ok, _pid} = Base.start_link(module: TestServer, name: :named_server, transport: [layer: MockTransport])
      assert pid = Process.whereis(:named_server)
      assert Process.alive?(pid)
    end
  end

  describe "handle_call/3 for messages" do
    test "handles initialization request", %{server: server} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => "1",
        "method" => "initialize",
        "params" => %{
          "protocolVersion" => "2025-03-26",
          "clientInfo" => %{
            "name" => "Test Client",
            "version" => "1.0.0"
          }
        }
      }

      assert {:ok, response} = GenServer.call(server, {:message, message})
      assert response["protocolVersion"] == "2025-03-26"
      assert response["serverInfo"]["name"] == "Test Server"
      assert response["capabilities"]["test_capability"]
    end

    test "handles error request", %{server: server} do
      initialize_server(server)

      message = %{
        "jsonrpc" => "2.0",
        "id" => "2",
        "method" => "error"
      }

      assert {:error, error} = GenServer.call(server, {:message, message})
      assert error.code
      assert error.data.message == "Test error"
    end

    test "rejects requests when not initialized", %{server: server} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => "1",
        "method" => "test"
      }

      assert {:error, error} = GenServer.call(server, {:message, message})
      assert error.code == -32_600
    end
  end

  describe "handle_cast/2 for notifications" do
    test "handles notifications", %{server: server} do
      initialize_server(server)

      notification = %{
        "jsonrpc" => "2.0",
        "method" => "test_notification"
      }

      assert :ok = GenServer.cast(server, {:notification, notification})
      state = :sys.get_state(server)
      assert state.custom_state.notification_received
    end

    test "handles initialize notification", %{server: server} do
      notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/initialized"
      }

      assert :ok = GenServer.cast(server, {:notification, notification})

      message = %{
        "jsonrpc" => "2.0",
        "id" => "1",
        "method" => "test"
      }

      assert {:ok, response} = GenServer.call(server, {:message, message})
      assert response["result"] == "test_success"
    end
  end

  describe "send_notification/3" do
    test "sends notification to transport", %{server: server} do
      initialize_server(server)

      params = %{"logger" => "database", "level" => "error", "data" => %{}}
      assert :ok = Base.send_notification(server, "notifications/message", params)
      messages = MockTransport.get_messages()
      assert length(messages) == 1
    end
  end

  defp initialize_server(server) do
    message = %{
      "jsonrpc" => "2.0",
      "id" => "1",
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => "2025-03-26",
        "clientInfo" => %{
          "name" => "Test Client",
          "version" => "1.0.0"
        }
      }
    }

    assert {:ok, _} = GenServer.call(server, {:message, message})

    notification = %{
      "jsonrpc" => "2.0",
      "method" => "notifications/initialized"
    }

    assert :ok = GenServer.cast(server, {:notification, notification})
    state = :sys.get_state(server)
    assert state.initialized
  end
end
