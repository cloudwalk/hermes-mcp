defmodule Hermes.Server.Transport.StreamableHTTPTest do
  use ExUnit.Case, async: true

  alias Hermes.MCP.Message
  alias Hermes.Server.Base
  alias Hermes.Server.Transport.StreamableHTTP
  alias Hermes.Server.Transport.StreamableHTTP.Supervisor, as: StreamableSupervisor

  @moduletag capture_log: true

  setup do
    server_name = :"test_server_#{System.unique_integer([:positive])}"
    transport_name = :"test_transport_#{System.unique_integer([:positive])}"
    registry_name = :"test_registry_#{System.unique_integer([:positive])}"

    server_opts = [
      module: TestServers.MinimalServer,
      init_arg: :ok,
      name: server_name,
      transport: [layer: StreamableHTTP, name: transport_name, registry: registry_name]
    ]

    server = start_supervised!({Base, server_opts})

    table_name = :"hermes_test_sessions_#{System.unique_integer([:positive])}"

    supervisor_opts = [
      server: server,
      transport_name: transport_name,
      registry_name: registry_name,
      table_name: table_name
    ]

    start_supervised!({StreamableSupervisor, supervisor_opts})

    transport = transport_name

    %{server: server, transport: transport, registry: registry_name}
  end

  describe "start_link/1" do
    test "starts with valid options" do
      server =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      registry_name = :"test_registry_#{System.unique_integer([:positive])}"
      transport_name = :"test_transport_#{System.unique_integer([:positive])}"

      table_name = :"hermes_test_sessions_#{System.unique_integer([:positive])}"
      start_supervised!({StreamableHTTP.SessionRegistry, [name: registry_name, table_name: table_name]})

      assert {:ok, pid} = StreamableHTTP.start_link(server: server, name: transport_name, registry: registry_name)
      assert Process.alive?(pid)
    end

    test "starts with named process" do
      server =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      registry_name = :"test_registry_#{System.unique_integer([:positive])}"
      name = :"test_streamable_http_#{System.unique_integer([:positive])}"

      table_name = :"hermes_test_sessions_#{System.unique_integer([:positive])}"
      start_supervised!({StreamableHTTP.SessionRegistry, [name: registry_name, table_name: table_name]})

      assert {:ok, _pid} = StreamableHTTP.start_link(server: server, name: name, registry: registry_name)
      assert pid = Process.whereis(name)
      assert Process.alive?(pid)
    end

    test "requires server option" do
      assert_raise Peri.InvalidSchema, fn ->
        StreamableHTTP.start_link([])
      end
    end
  end

  describe "create_session/1" do
    test "creates a new session", %{transport: transport, server: server} do
      assert {:ok, session_id} = StreamableHTTP.create_session(transport)
      assert is_binary(session_id)

      assert {:ok, session_info} = StreamableHTTP.lookup_session(transport, session_id)
      assert session_info.server == server
    end

    test "each session gets unique ID", %{transport: transport} do
      {:ok, session_id1} = StreamableHTTP.create_session(transport)
      {:ok, session_id2} = StreamableHTTP.create_session(transport)

      assert session_id1 != session_id2
    end
  end

  describe "handle_message/3" do
    test "forwards message to server and returns response", %{transport: transport} do
      {:ok, session_id} = StreamableHTTP.create_session(transport)

      {:ok, message} =
        Message.encode_request(
          %{
            "method" => "initialize",
            "params" => %{
              "protocolVersion" => "2025-03-26",
              "capabilities" => %{"tools" => %{}},
              "clientInfo" => %{"name" => "Test Client", "version" => "1.0.0"}
            }
          },
          1
        )

      assert {:ok, response_json} = StreamableHTTP.handle_message(transport, session_id, message)
      assert is_binary(response_json)

      assert {:ok, response} = Jason.decode(response_json)
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert is_map(response["result"])
    end

    test "records session activity", %{transport: transport} do
      {:ok, session_id} = StreamableHTTP.create_session(transport)

      {:ok, original_info} = StreamableHTTP.lookup_session(transport, session_id)

      Process.sleep(10)

      message =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "notifications/initialized"
        })

      StreamableHTTP.handle_message(transport, session_id, message)

      {:ok, updated_info} = StreamableHTTP.lookup_session(transport, session_id)
      assert DateTime.after?(updated_info.last_activity, original_info.last_activity)
    end

    test "returns error for non-existent session", %{transport: transport} do
      message = Jason.encode!(%{"jsonrpc" => "2.0", "method" => "ping"})

      assert {:error, :session_not_found} =
               StreamableHTTP.handle_message(transport, "non-existent", message)
    end

    test "handles server errors gracefully", %{transport: transport} do
      {:ok, session_id} = StreamableHTTP.create_session(transport)

      invalid_message = "invalid json"

      assert {:error, _reason} = StreamableHTTP.handle_message(transport, session_id, invalid_message)
    end
  end

  describe "set_sse_connection/3" do
    test "sets SSE connection for session", %{transport: transport} do
      {:ok, session_id} = StreamableHTTP.create_session(transport)

      sse_pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      assert :ok = StreamableHTTP.set_sse_connection(transport, session_id, sse_pid)

      {:ok, session_info} = StreamableHTTP.lookup_session(transport, session_id)
      assert session_info.sse_pid == sse_pid
    end

    test "monitors SSE process", %{transport: transport} do
      {:ok, session_id} = StreamableHTTP.create_session(transport)

      sse_pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      StreamableHTTP.set_sse_connection(transport, session_id, sse_pid)

      Process.exit(sse_pid, :kill)

      Process.sleep(50)

      assert {:error, :not_found} = StreamableHTTP.lookup_session(transport, session_id)
    end

    test "returns error for non-existent session", %{transport: transport} do
      sse_pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      assert {:error, :not_found} =
               StreamableHTTP.set_sse_connection(transport, "non-existent", sse_pid)
    end
  end

  describe "send_message/2" do
    test "returns error for no active session", %{transport: transport} do
      message = "test message"

      assert {:error, :no_active_session} = StreamableHTTP.send_message(transport, message)
    end
  end

  describe "shutdown/1" do
    test "gracefully shuts down transport", %{transport: transport} do
      {:ok, session_id} = StreamableHTTP.create_session(transport)

      assert {:ok, _} = StreamableHTTP.lookup_session(transport, session_id)

      assert :ok = StreamableHTTP.shutdown(transport)

      Process.sleep(50)

      assert {:error, :not_found} = StreamableHTTP.lookup_session(transport, session_id)
    end

    test "terminates all sessions on shutdown", %{transport: transport} do
      {:ok, session_id1} = StreamableHTTP.create_session(transport)
      {:ok, session_id2} = StreamableHTTP.create_session(transport)

      assert {:ok, _} = StreamableHTTP.lookup_session(transport, session_id1)
      assert {:ok, _} = StreamableHTTP.lookup_session(transport, session_id2)

      StreamableHTTP.shutdown(transport)

      Process.sleep(50)

      assert {:error, :not_found} = StreamableHTTP.lookup_session(transport, session_id1)
      assert {:error, :not_found} = StreamableHTTP.lookup_session(transport, session_id2)
    end
  end

  describe "integration with server" do
    test "full message flow works", %{transport: transport} do
      {:ok, session_id} = StreamableHTTP.create_session(transport)

      {:ok, init_message_encoded} =
        Message.encode_request(
          %{
            "method" => "initialize",
            "params" => %{
              "protocolVersion" => "2025-03-26",
              "capabilities" => %{"tools" => %{}},
              "clientInfo" => %{"name" => "Test Client", "version" => "1.0.0"}
            }
          },
          1
        )

      {:ok, response_json} =
        StreamableHTTP.handle_message(
          transport,
          session_id,
          init_message_encoded
        )

      {:ok, response} = Jason.decode(response_json)
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert is_map(response["result"])
      assert response["result"]["protocolVersion"] == "2025-03-26"
      assert is_map(response["result"]["serverInfo"])
      assert is_map(response["result"]["capabilities"])

      {:ok, initialized_message_encoded} =
        Message.encode_notification(%{
          "method" => "notifications/initialized"
        })

      {:ok, nil} =
        StreamableHTTP.handle_message(
          transport,
          session_id,
          initialized_message_encoded
        )

      {:ok, ping_message_encoded} =
        Message.encode_request(
          %{"method" => "ping"},
          2
        )

      {:ok, ping_response_json} =
        StreamableHTTP.handle_message(
          transport,
          session_id,
          ping_message_encoded
        )

      {:ok, ping_response} = Jason.decode(ping_response_json)
      assert ping_response["jsonrpc"] == "2.0"
      assert ping_response["id"] == 2
      assert ping_response["result"] == %{}
    end
  end
end
