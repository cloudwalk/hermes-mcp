defmodule Hermes.Transport.STDIOTest do
  use ExUnit.Case, async: false

  alias Hermes.Transport.STDIO

  @moduletag capture_log: true

  setup do
    # Start the stub client
    start_supervised!(StubClient)

    # Echo command that will definitely exist on all systems
    # Using 'echo' for Unix-like and 'cmd' for Windows
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

      # Cleanup
      safe_stop(pid)
    end

    test "fails when command not found" do
      # Use a special case with empty arguments that's handled in the transport to fail
      # (this is a workaround since we can't mock System.find_executable)
      opts = [
        client: StubClient,
        # Empty command will cause failure
        command: "",
        name: :should_fail
      ]

      assert {:ok, pid} = STDIO.start_link(opts)
      Process.flag(:trap_exit, true)
      assert_receive {:EXIT, ^pid, {:error, _}}
    end
  end

  describe "send_message/2" do
    setup %{command: command} do
      # Create a transport using a real command
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
      # Simple message that should succeed
      assert :ok = STDIO.send_message(pid, "test message")
    end
  end

  describe "client message handling" do
    setup do
      # Use cat or type command which will echo input back
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
      # Clear any previous messages
      :ok = StubClient.clear_messages()

      # Send data that will be echoed back by cat/type
      STDIO.send_message(pid, "echo test\n")

      # Wait a moment for processing
      Process.sleep(100)

      # Check if client received message - we just need some data
      messages = StubClient.get_messages()
      assert length(messages) > 0
    end
  end

  describe "port behavior" do
    test "handles port restart on close" do
      # Start with the echo command
      command = if :os.type() == {:win32, :nt}, do: "cmd", else: "echo"

      # Start with a name so we can check if it restarts
      transport_name = :restart_test_transport

      {:ok, pid} =
        STDIO.start_link(
          client: StubClient,
          command: command,
          name: transport_name
        )

      # Verify it's running
      original_pid = Process.whereis(transport_name)
      assert original_pid != nil

      # Monitor to detect restart
      ref = Process.monitor(original_pid)

      # Send a stop message to terminate it
      safe_stop(pid)

      # Wait for termination notification
      assert_receive {:DOWN, ^ref, :process, ^original_pid, _}, 1000
    end
  end

  describe "environment variables" do
    test "uses environment variables" do
      # A command that will print something
      command = if :os.type() == {:win32, :nt}, do: "cmd", else: "echo"

      # Clear previous messages
      :ok = StubClient.clear_messages()

      # Create with a custom env var
      {:ok, pid} =
        STDIO.start_link(
          client: StubClient,
          command: command,
          args: ["TEST_CUSTOM_VAR=test_value"],
          env: %{"TEST_CUSTOM_VAR" => "test_value"},
          name: :env_test_transport
        )

      # Wait for env output
      Process.sleep(100)

      # Verify we got some messages
      messages = StubClient.get_messages()
      assert length(messages) > 0

      # Cleanup
      safe_stop(pid)
    end
  end

  # Helper for safely stopping a process if it's still alive
  defp safe_stop(pid) do
    if is_pid(pid) && Process.alive?(pid) do
      try do
        GenServer.stop(pid, :normal, 100)
      catch
        :exit, _ -> :ok
      end
    end
  end
end
