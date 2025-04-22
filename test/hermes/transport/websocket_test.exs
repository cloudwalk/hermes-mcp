defmodule Hermes.Transport.WebSocketTest do
  use ExUnit.Case, async: true

  import Mox

  alias Hermes.Transport.WebSocket

  setup :verify_on_exit!

  describe "start_link/1" do
    setup do
      stub(Hermes.MockTransport, :start_link, fn _opts -> {:ok, self()} end)
      stub(Hermes.MockTransport, :send_message, fn _pid, _message -> :ok end)
      stub(Hermes.MockTransport, :shutdown, fn _pid -> :ok end)

      client = start_supervised!(StubClient)
      %{client: client}
    end

    setup do
      :meck.new(:gun, [:non_strict, :passthrough])
      :meck.expect(:gun, :open, fn _host, _port, _opts -> {:ok, self()} end)
      :meck.expect(:gun, :await_up, fn _pid, _timeout -> {:ok, :http} end)
      :meck.expect(:gun, :ws_upgrade, fn _pid, _path, _headers -> make_ref() end)
      :meck.expect(:gun, :ws_send, fn _pid, _stream_ref, _data -> :ok end)
      :meck.expect(:gun, :close, fn _pid -> :ok end)

      on_exit(fn ->
        :meck.unload(:gun)
      end)

      :ok
    end

    test "starts with valid options", %{client: client} do
      transport_opts = [
        client: client,
        server: [
          base_url: "http://localhost:8000",
          base_path: "/mcp",
          ws_path: "/ws"
        ]
      ]

      assert {:ok, pid} = WebSocket.start_link(transport_opts)
      assert Process.alive?(pid)
    end

    test "fails with invalid options" do
      transport_opts = [
        server: [
          base_path: "/mcp",
          ws_path: "/ws"
        ]
      ]

      assert_raise RuntimeError, ~r/missing required key/, fn ->
        WebSocket.start_link(transport_opts)
      end
    end
  end

  describe "send_message/2" do
    setup do
      :meck.new(:gun, [:non_strict, :passthrough])
      :meck.expect(:gun, :open, fn _host, _port, _opts -> {:ok, self()} end)
      :meck.expect(:gun, :await_up, fn _pid, _timeout -> {:ok, :http} end)
      :meck.expect(:gun, :ws_upgrade, fn _pid, _path, _headers -> make_ref() end)
      :meck.expect(:gun, :ws_send, fn _pid, _stream_ref, _data -> :ok end)
      :meck.expect(:gun, :close, fn _pid -> :ok end)

      client = start_supervised!(StubClient)

      transport_opts = [
        client: client,
        server: [
          base_url: "http://localhost:8000",
          base_path: "/mcp",
          ws_path: "/ws"
        ]
      ]

      {:ok, pid} = WebSocket.start_link(transport_opts)

      ref = make_ref()
      send(pid, {:gun_upgrade, self(), ref, ["websocket"], []})

      on_exit(fn ->
        :meck.unload(:gun)
      end)

      %{ws: pid, client: client, stream_ref: ref}
    end

    test "sends message successfully", %{ws: pid, stream_ref: _ref} do
      assert :ok = WebSocket.send_message(pid, "test message")
    end

    test "handles server messages", %{ws: pid, client: _client, stream_ref: ref} do
      message = ~s({"jsonrpc":"2.0","method":"test","params":{}})
      send(pid, {:gun_ws, self(), ref, {:text, message}})

      assert Process.alive?(pid)
    end
  end

  describe "shutdown/1" do
    setup do
      :meck.new(:gun, [:non_strict, :passthrough])
      :meck.expect(:gun, :open, fn _host, _port, _opts -> {:ok, self()} end)
      :meck.expect(:gun, :await_up, fn _pid, _timeout -> {:ok, :http} end)
      :meck.expect(:gun, :ws_upgrade, fn _pid, _path, _headers -> make_ref() end)
      :meck.expect(:gun, :ws_send, fn _pid, _stream_ref, _data -> :ok end)
      :meck.expect(:gun, :close, fn _pid -> :ok end)

      client = start_supervised!(StubClient)

      transport_opts = [
        client: client,
        server: [
          base_url: "http://localhost:8000",
          base_path: "/mcp",
          ws_path: "/ws"
        ]
      ]

      {:ok, pid} = WebSocket.start_link(transport_opts)

      on_exit(fn ->
        :meck.unload(:gun)
      end)

      %{ws: pid, client: client}
    end

    test "shuts down connection", %{ws: pid} do
      assert :ok = WebSocket.shutdown(pid)
      :timer.sleep(10)
      refute Process.alive?(pid)
    end
  end
end
