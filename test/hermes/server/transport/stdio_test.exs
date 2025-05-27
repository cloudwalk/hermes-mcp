defmodule Hermes.Server.Transport.STDIOTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Hermes.MCP.Message
  alias Hermes.Server.Base
  alias Hermes.Server.Transport.STDIO

  @moduletag capture_log: true

  setup do
    opts = [
      module: TestServer,
      name: :test_stdio_server,
      transport: [layer: STDIO]
    ]

    server = start_supervised!({Base, opts})
    %{server: server}
  end

  describe "start_link/1" do
    test "starts successfully with valid options", %{server: server} do
      opts = [server: server, name: :test_stdio_transport]

      assert {:ok, pid} = STDIO.start_link(opts)
      assert Process.alive?(pid)
      assert Process.whereis(:test_stdio_transport) == pid

      assert :ok = STDIO.shutdown(pid)
      wait_for_process_exit(pid)
    end
  end

  describe "send_message/2" do
    test "sends message to stdout", %{server: server} do
      {:ok, pid} = STDIO.start_link(server: server)

      message = "test message"

      output =
        capture_io(fn ->
          assert :ok = STDIO.send_message(pid, message)
          Process.sleep(50)
        end)

      assert output == message

      assert :ok = STDIO.shutdown(pid)
      wait_for_process_exit(pid)
    end
  end

  describe "shutdown/1" do
    test "shuts down the transport gracefully", %{server: server} do
      {:ok, pid} = STDIO.start_link(server: server, name: :shutdown_test)

      ref = Process.monitor(pid)

      assert :ok = STDIO.shutdown(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      refute Process.whereis(:shutdown_test)
    end
  end

  describe "message handling" do
    setup %{server: server} do
      {:ok, pid} = STDIO.start_link(server: server, name: :message_test)

      on_exit(fn ->
        if Process.alive?(pid) do
          STDIO.shutdown(pid)
          wait_for_process_exit(pid)
        end
      end)

      %{transport: pid, server: server}
    end

    test "forwards request message to server", %{server: server} do
      request = %{"method" => "ping", "params" => %{}}
      assert {:ok, message} = Message.encode_request(request, 123)

      STDIO.handle_continue({:forward_to_server, message}, %{server: server})

      output = capture_io(fn -> Process.sleep(100) end)
      assert output =~ "test_success"
    end

    test "forwards notification message to server", %{server: server} do
      assert data = %{"method" => "notifications/cancelled", "params" => %{"requestId" => 123, "reason" => "test"}}
      assert {:ok, notification} = Message.encode_notification(data)

      STDIO.handle_continue({:forward_to_server, notification}, %{server: server})

      output = capture_io(fn -> Process.sleep(100) end)
      assert output == ""
    end

    test "handles decoding errors gracefully", %{transport: transport, server: server} do
      invalid_json = "{ this is not valid json }"
      ref = Process.monitor(transport)

      STDIO.handle_continue({:forward_to_server, invalid_json}, %{server: server})

      Process.sleep(100)
      refute_received {:DOWN, ^ref, :process, ^transport, _}
    end
  end

  describe "error handling" do
    test "handles EOF from stdin", %{server: server} do
      {:ok, pid} = STDIO.start_link(server: server, name: :eof_test)

      ref = Process.monitor(pid)

      # Simulate EOF from stdin
      send(pid, {:io_request, self(), make_ref(), {:get_line, :stdio, :line}})
      send(pid, {:io_reply, make_ref(), :eof})

      # Should terminate due to EOF
      assert_receive {:DOWN, ^ref, :process, ^pid, {:error, :eof}}, 500
    end

    test "handles read errors", %{server: server} do
      {:ok, pid} = STDIO.start_link(server: server, name: :error_test)

      ref = Process.monitor(pid)

      # Simulate read error
      send(pid, {:io_request, self(), make_ref(), {:get_line, :stdio, :line}})
      send(pid, {:io_reply, make_ref(), {:error, :test_error}})

      # Should terminate due to error
      assert_receive {:DOWN, ^ref, :process, ^pid, {:error, :test_error}}, 500
    end
  end

  # Helper functions

  defp wait_for_process_exit(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      500 -> :error
    end
  end
end
