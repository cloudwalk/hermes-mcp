defmodule Hermes.Server.BaseTest do
  use ExUnit.Case, async: true

  alias Hermes.MCP.Message
  alias Hermes.Server.Base
  alias Hermes.Server.MockTransport

  require Message

  @moduletag capture_log: true

  setup do
    start_supervised!({MockTransport, name: :mock_server_transport})

    server =
      start_supervised!(
        {Base, module: TestServer, name: :test_server, transport: [layer: MockTransport, name: :mock_server_transport]}
      )

    MockTransport.clear_messages()

    %{server: server}
  end

  defmacrop assert_response(server, request, pattern) do
    quote do
      assert {:ok, message} = Message.encode_request(unquote(request), 1)
      assert {:ok, response} = GenServer.call(unquote(server), {:message, message})
      assert {:ok, [response]} = Message.decode(response)
      assert Message.is_response(response)
      assert unquote(pattern) = response
    end
  end

  defmacrop assert_notification(server, notification) do
    quote do
      assert {:ok, message} = Message.encode_notification(unquote(notification))
      assert {:ok, nil} = GenServer.call(unquote(server), {:message, message})
    end
  end

  defmacrop assert_error(server, request, pattern) do
    quote do
      assert {:ok, message} = Message.encode_request(unquote(request), 1)
      assert {:ok, response} = GenServer.call(unquote(server), {:message, message})
      assert {:ok, [error]} = Message.decode(response)
      assert Message.is_error(error)
      assert %{"error" => unquote(pattern)} = error
    end
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
        "method" => "initialize",
        "params" => %{
          "protocolVersion" => "2025-03-26",
          "capabilities" => %{"roots" => %{}},
          "clientInfo" => %{
            "name" => "Test Client",
            "version" => "1.0.0"
          }
        }
      }

      assert_response server, message, %{
        "id" => 1,
        "jsonrpc" => "2.0",
        "result" => %{
          "protocolVersion" => "2025-03-26",
          "serverInfo" => %{"name" => "Test Server", "version" => "1.0.0"},
          "capabilities" => %{"tools" => %{"listChanged" => true}}
        }
      }
    end

    @tag skip: true
    test "handles errors", %{server: server} do
      initialize_server(server)

      error = %{
        "error" => %{
          "data" => %{},
          "message" => "got wrong",
          "code" => -32_000
        }
      }

      # TODO(zoedsoupe): properly handle errors
      assert {:ok, encoded} = Message.encode_error(error, 1)
      assert_raise CaseClauseError, fn -> GenServer.call(server, {:message, encoded}) end
    end

    test "rejects requests when not initialized", %{server: server} do
      message = %{"method" => "tools/list", "params" => %{}}
      assert_error server, message, %{"code" => -32_600}
    end

    test "accept ping requests when not initialized", %{server: server} do
      message = %{"method" => "ping", "params" => %{}}

      assert {:ok, message} = Message.encode_request(message, 1)
      assert {:ok, _} = GenServer.call(server, {:message, message})
    end
  end

  describe "handle_call/2 for notifications" do
    test "handles notifications", %{server: server} do
      initialize_server(server)

      notification = %{"method" => "notifications/cancelled", "params" => %{"requestId" => 1}}

      assert_notification server, notification
    end

    test "handles initialize notification", %{server: server} do
      notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/initialized"
      }

      assert_notification server, notification

      message = %{"method" => "tools/list", "params" => %{}}
      assert_response server, message, %{"result" => "test_success"}
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
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => "2025-03-26",
        "capabilities" => %{"roots" => %{}},
        "clientInfo" => %{
          "name" => "Test Client",
          "version" => "1.0.0"
        }
      }
    }

    assert_response server, message, %{
      "id" => 1,
      "jsonrpc" => "2.0",
      "result" => %{
        "protocolVersion" => "2025-03-26",
        "serverInfo" => %{"name" => "Test Server", "version" => "1.0.0"},
        "capabilities" => %{"tools" => %{"listChanged" => true}}
      }
    }

    notification = %{"method" => "notifications/initialized", "params" => %{}}
    assert_notification server, notification

    state = :sys.get_state(server)
    assert state.initialized
  end
end
