if Code.ensure_loaded?(:gun) do
  defmodule Hermes.Transport.WebSocketTest do
    use ExUnit.Case, async: false
    use Mimic

    alias Hermes.Transport.WebSocket

    @moduletag capture_log: true

    setup :set_mimic_global
    setup :verify_on_exit!

    setup do
      gun_pid = self()
      mock_ref = make_ref()

      client = start_supervised!(StubClient)

      Mimic.stub(:gun, :open, fn _host, _port, _opts ->
        Process.sleep(50)
        {:ok, gun_pid}
      end)

      Mimic.stub(:gun, :await_up, fn _pid, _timeout ->
        {:ok, :http}
      end)

      Mimic.stub(:gun, :ws_upgrade, fn _pid, _path, _headers ->
        mock_ref
      end)

      Mimic.stub(:gun, :ws_send, fn _pid, _stream_ref, _data ->
        :ok
      end)

      Mimic.stub(:gun, :close, fn _pid ->
        :ok
      end)

      %{client: client, gun_pid: gun_pid, mock_ref: mock_ref}
    end

    describe "start_link/1" do
      test "fails with invalid options" do
        transport_opts = [
          server: [
            base_path: "/mcp",
            ws_path: "/ws"
          ]
        ]

        assert_raise Peri.InvalidSchema, fn ->
          WebSocket.start_link(transport_opts)
        end
      end

      test "successfully connects to a WebSocket server", %{
        client: client,
        gun_pid: gun_pid,
        mock_ref: mock_ref
      } do
        transport_opts = [
          client: client,
          server: [
            base_url: "ws://localhost:4000",
            base_path: "/mcp",
            ws_path: "/ws"
          ]
        ]

        {:ok, ws_pid} = WebSocket.start_link(transport_opts)
        Process.monitor(ws_pid)

        send(ws_pid, {:gun_upgrade, gun_pid, mock_ref, ["websocket"], %{}})

        assert Process.alive?(ws_pid)

        :ok = WebSocket.shutdown(ws_pid)

        assert_receive {:DOWN, _, :process, ^ws_pid, :normal}, 1000
      end

      test "can send messages through the WebSocket", %{
        client: client,
        gun_pid: gun_pid,
        mock_ref: mock_ref
      } do
        test_message = "test message"
        test_pid = self()

        Mimic.expect(:gun, :ws_send, fn pid, stream_ref, {:text, message} ->
          assert pid == gun_pid
          assert stream_ref == mock_ref
          assert message == test_message
          send(test_pid, {:message_sent, message})
          :ok
        end)

        transport_opts = [
          client: client,
          server: [
            base_url: "ws://localhost:4000",
            base_path: "/mcp",
            ws_path: "/ws"
          ]
        ]

        {:ok, ws_pid} = WebSocket.start_link(transport_opts)
        ref = Process.monitor(ws_pid)

        send(ws_pid, {:gun_upgrade, gun_pid, mock_ref, ["websocket"], %{}})

        assert Process.alive?(ws_pid)

        assert :ok = WebSocket.send_message(ws_pid, test_message, [])

        assert_receive {:message_sent, ^test_message}, 1000

        :ok = WebSocket.shutdown(ws_pid)

        assert_receive {:DOWN, ^ref, :process, ^ws_pid, :normal}, 1000
      end

      test "can receive messages from the WebSocket", %{
        client: client,
        gun_pid: gun_pid,
        mock_ref: mock_ref
      } do
        test_message = ~s({"jsonrpc":"2.0","method":"test","params":{}})

        transport_opts = [
          client: client,
          server: [
            base_url: "ws://localhost:4000",
            base_path: "/mcp",
            ws_path: "/ws"
          ]
        ]

        :ok = StubClient.clear_messages()

        {:ok, ws_pid} = WebSocket.start_link(transport_opts)
        ref = Process.monitor(ws_pid)

        send(ws_pid, {:gun_upgrade, gun_pid, mock_ref, ["websocket"], %{}})
        Process.sleep(50)

        send(ws_pid, {:gun_ws, gun_pid, mock_ref, {:text, test_message}})

        Process.sleep(100)

        messages = StubClient.get_messages()
        assert test_message in messages

        :ok = WebSocket.shutdown(ws_pid)

        assert_receive {:DOWN, ^ref, :process, ^ws_pid, :normal}, 1000
      end

      test "handles WebSocket close events", %{
        client: client,
        gun_pid: gun_pid,
        mock_ref: mock_ref
      } do
        transport_opts = [
          client: client,
          server: [
            base_url: "ws://localhost:4000",
            base_path: "/mcp",
            ws_path: "/ws"
          ]
        ]

        {:ok, ws_pid} = WebSocket.start_link(transport_opts)
        ref = Process.monitor(ws_pid)

        send(ws_pid, {:gun_upgrade, gun_pid, mock_ref, ["websocket"], %{}})

        send(ws_pid, {:gun_ws, gun_pid, mock_ref, :close})

        assert_receive {:DOWN, ^ref, :process, ^ws_pid, :normal}, 1000
        refute Process.alive?(ws_pid)
      end

      test "handles WebSocket close with code events", %{
        client: client,
        gun_pid: gun_pid,
        mock_ref: mock_ref
      } do
        Process.flag(:trap_exit, true)

        transport_opts = [
          client: client,
          server: [
            base_url: "ws://localhost:4000",
            base_path: "/mcp",
            ws_path: "/ws"
          ]
        ]

        {:ok, ws_pid} = WebSocket.start_link(transport_opts)

        Process.link(ws_pid)

        send(ws_pid, {:gun_upgrade, gun_pid, mock_ref, ["websocket"], %{}})
        Process.sleep(50)

        assert Process.alive?(ws_pid)

        send(ws_pid, {:gun_ws, gun_pid, mock_ref, {:close, 1000, "Normal closure"}})

        assert_receive {:EXIT, ^ws_pid, {:ws_closed, 1000, "Normal closure"}}, 1000

        refute Process.alive?(ws_pid)

        Process.flag(:trap_exit, false)
      end
    end
  end
end
