defmodule Hermes.Server.Transport.STDIOTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Hermes.Server.Base
  alias Hermes.Server.Transport.STDIO

  @moduletag capture_log: true, capture_io: true

  setup do
    opts = [
      module: TestServer,
      transport: [layer: STDIO]
    ]

    server = start_supervised!({Base, opts})
    %{server: server}
  end

  describe "start_link/1" do
    test "starts successfully with valid options", %{server: server} do
      name = :"test_stdio_transport_#{:rand.uniform(1_000_000)}"
      opts = [server: server, name: name]

      assert {:ok, pid} = STDIO.start_link(opts)
      assert Process.alive?(pid)
      assert Process.whereis(name) == pid

      assert :ok = STDIO.shutdown(pid)
      wait_for_process_exit(pid)
    end
  end

  describe "send_message/2" do
    test "sends message via cast", %{server: server} do
      name = :"test_send_message_#{:rand.uniform(1_000_000)}"
      {:ok, pid} = STDIO.start_link(server: server, name: name)

      message = "test message"

      assert capture_io(pid, fn ->
               assert :ok = STDIO.send_message(pid, message)
               Process.sleep(50)
             end) =~ "test message"

      assert :ok = STDIO.shutdown(pid)
      wait_for_process_exit(pid)
    end
  end

  describe "shutdown/1" do
    test "shuts down the transport gracefully", %{server: server} do
      name = :"shutdown_test_#{:rand.uniform(1_000_000)}"
      {:ok, pid} = STDIO.start_link(server: server, name: name)

      ref = Process.monitor(pid)

      assert :ok = STDIO.shutdown(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      refute Process.whereis(name)
    end
  end

  describe "basic functionality" do
    test "starts and stops cleanly", %{server: server} do
      name = :"basic_test_#{:rand.uniform(1_000_000)}"

      assert {:ok, pid} = STDIO.start_link(server: server, name: name)
      assert Process.alive?(pid)

      assert :ok = STDIO.shutdown(pid)
      wait_for_process_exit(pid)
    end

    test "manages reading tasks correctly", %{server: server} do
      name = :"async_test_#{:rand.uniform(1_000_000)}"
      {:ok, pid} = STDIO.start_link(server: server, name: name)

      assert Process.alive?(pid)

      STDIO.shutdown(pid)
      wait_for_process_exit(pid)
    end
  end

  defp wait_for_process_exit(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      500 -> :error
    end
  end
end
