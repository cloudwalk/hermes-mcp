defmodule Hermes.Transport.STDIOTest do
  use ExUnit.Case, async: false

  alias Hermes.Transport.STDIO

  @moduletag capture_log: true

  setup do
    start_supervised!(StubClient)

    command = if :os.type() == {:win32, :nt}, do: "cmd", else: "echo"

    %{command: command}
  end

  describe "start_link/1" do
    test "successfully starts transport", %{command: command} do
      opts = [
        client: StubClient,
        command: command,
        args: ["hello"],
        name: :test_transport
      ]

      assert {:ok, pid} = STDIO.start_link(opts)
      assert Process.whereis(:test_transport) != nil

      safe_stop(pid)
    end

    test "fails when command not found" do
      opts = [
        client: StubClient,
        command: "abc",
        name: :should_fail
      ]

      assert {:ok, pid} = STDIO.start_link(opts)
      Process.flag(:trap_exit, true)
      assert_receive {:EXIT, ^pid, {:error, _}}
    end
  end

  describe "send_message/2" do
    setup %{command: command} do
      {:ok, pid} =
        STDIO.start_link(
          client: StubClient,
          command: command,
          args: ["test"],
          name: :test_send_transport
        )

      on_exit(fn -> safe_stop(pid) end)

      %{transport_pid: pid}
    end

    test "sends message successfully", %{transport_pid: pid} do
      assert :ok = STDIO.send_message(pid, "test message", [])
    end
  end

  describe "client message handling" do
    setup do
      command = if :os.type() == {:win32, :nt}, do: "cmd", else: "cat"

      {:ok, pid} =
        STDIO.start_link(
          client: StubClient,
          command: command,
          name: :test_echo_transport
        )

      on_exit(fn -> safe_stop(pid) end)

      %{transport_pid: pid}
    end

    test "forwards data to client", %{transport_pid: pid} do
      :ok = StubClient.clear_messages()

      STDIO.send_message(pid, "echo test\n", [])

      Process.sleep(100)

      messages = StubClient.get_messages()
      assert length(messages) > 0
    end
  end

  describe "port behavior" do
    test "handles port restart on close" do
      command = if :os.type() == {:win32, :nt}, do: "cmd", else: "echo"

      transport_name = :restart_test_transport

      {:ok, pid} =
        STDIO.start_link(
          client: StubClient,
          command: command,
          name: transport_name
        )

      original_pid = Process.whereis(transport_name)
      assert original_pid != nil

      ref = Process.monitor(original_pid)

      safe_stop(pid)

      assert_receive {:DOWN, ^ref, :process, ^original_pid, _}, 1000
    end
  end

  describe "environment variables" do
    test "uses environment variables" do
      command = if :os.type() == {:win32, :nt}, do: "cmd", else: "echo"

      :ok = StubClient.clear_messages()

      {:ok, pid} =
        STDIO.start_link(
          client: StubClient,
          command: command,
          args: ["TEST_CUSTOM_VAR=test_value"],
          env: %{"TEST_CUSTOM_VAR" => "test_value"},
          name: :env_test_transport
        )

      Process.sleep(100)

      messages = StubClient.get_messages()
      assert length(messages) > 0

      safe_stop(pid)
    end
  end

  defp safe_stop(pid) do
    if is_pid(pid) && Process.alive?(pid) do
      try do
        STDIO.shutdown(pid)
        Process.sleep(50)
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 100)
      catch
        :exit, _ -> :ok
      end
    end
  end
end
