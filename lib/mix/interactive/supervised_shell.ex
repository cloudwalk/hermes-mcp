defmodule Mix.Interactive.SupervisedShell do
  @moduledoc false

  alias Mix.Interactive.CLI
  alias Mix.Interactive.Commands
  alias Mix.Interactive.UI

  defstruct [
    :transport_module,
    :transport_opts,
    :client_opts,
    :transport_pid,
    :client_pid,
    :restart_count,
    :max_restarts
  ]

  @max_restarts 3
  @restart_delay 1000

  @doc """
  Starts a supervised interactive shell session.

  ## Options
    * `:transport_module` - The transport module (e.g., Hermes.Transport.StreamableHTTP)
    * `:transport_opts` - Options for starting the transport
    * `:client_opts` - Options for starting the client (excluding transport)
    * `:max_restarts` - Maximum number of automatic restarts (default: 3)
  """
  def start(opts) do
    state = %__MODULE__{
      transport_module: Keyword.fetch!(opts, :transport_module),
      transport_opts: Keyword.fetch!(opts, :transport_opts),
      client_opts: Keyword.fetch!(opts, :client_opts),
      restart_count: 0,
      max_restarts: Keyword.get(opts, :max_restarts, @max_restarts)
    }

    Process.flag(:trap_exit, true)

    case start_processes(state) do
      {:ok, state} ->
        IO.puts("\nType #{UI.colors().command}help#{UI.colors().reset} for available commands\n")

        supervised_loop(state)

      {:error, reason} ->
        IO.puts("#{UI.colors().error}Failed to start processes: #{inspect(reason)}#{UI.colors().reset}")

        {:error, reason}
    end
  end

  defp supervised_loop(%{client_pid: client} = state) do
    if Process.alive?(client) do
      IO.write("#{UI.colors().prompt}mcp> #{UI.colors().reset}")

      parent = self()

      input_pid =
        spawn_link(fn ->
          line = IO.gets("")
          send(parent, {:input, line})
        end)

      receive do
        {:EXIT, pid, reason}
        when pid == state.client_pid or pid == state.transport_pid ->
          Process.exit(input_pid, :kill)
          handle_process_exit(pid, reason, state)

        {:EXIT, ^input_pid, _reason} ->
          supervised_loop(state)

        {:input, :eof} ->
          :ok

        {:input, line} ->
          line
          |> String.trim()
          |> Commands.process_command(client, fn -> supervised_loop(state) end)
      end
    else
      handle_process_exit(state.client_pid, :noproc, state)
    end
  end

  defp handle_process_exit(pid, reason, state) do
    cond do
      pid == state.client_pid ->
        IO.puts("\n#{UI.colors().error}✗ Client process crashed: #{format_exit_reason(reason)}#{UI.colors().reset}")

        handle_restart(state)

      pid == state.transport_pid ->
        IO.puts("\n#{UI.colors().error}✗ Transport process crashed: #{format_exit_reason(reason)}#{UI.colors().reset}")

        handle_restart(state)

      true ->
        supervised_loop(state)
    end
  end

  defp format_exit_reason({:timeout, _}), do: "Request timeout"
  defp format_exit_reason({:error, %{reason: reason}}), do: "Error: #{reason}"
  defp format_exit_reason(:normal), do: "Normal termination"
  defp format_exit_reason(:shutdown), do: "Shutdown"
  defp format_exit_reason(reason), do: inspect(reason)

  defp handle_restart(state) do
    if state.restart_count < state.max_restarts do
      IO.puts(
        "#{UI.colors().info}→ Attempting automatic restart (#{state.restart_count + 1}/#{state.max_restarts})...#{UI.colors().reset}"
      )

      Process.sleep(@restart_delay)

      cleanup_processes(state)

      new_state = %{state | restart_count: state.restart_count + 1}

      case start_processes(new_state) do
        {:ok, restarted_state} ->
          IO.puts("#{UI.colors().success}✓ Successfully restarted#{UI.colors().reset}")

          IO.write("\n#{UI.colors().prompt}mcp> #{UI.colors().reset}")
          supervised_loop(restarted_state)

        {:error, reason} ->
          IO.puts("#{UI.colors().error}✗ Restart failed: #{inspect(reason)}#{UI.colors().reset}")

          offer_manual_restart(new_state)
      end
    else
      IO.puts("#{UI.colors().error}✗ Maximum restart attempts reached#{UI.colors().reset}")

      offer_manual_restart(state)
    end
  end

  defp offer_manual_restart(state) do
    IO.puts("\n#{UI.colors().info}Options:#{UI.colors().reset}")
    IO.puts("  #{UI.colors().command}r#{UI.colors().reset} - Retry connection")
    IO.puts("  #{UI.colors().command}q#{UI.colors().reset} - Quit")
    IO.write("\n#{UI.colors().prompt}Choice: #{UI.colors().reset}")

    case "" |> IO.gets() |> String.trim() |> String.downcase() do
      "r" ->
        IO.puts("#{UI.colors().info}→ Retrying connection...#{UI.colors().reset}")
        cleanup_processes(state)
        new_state = %{state | restart_count: 0}

        case start_processes(new_state) do
          {:ok, restarted_state} ->
            IO.puts("#{UI.colors().success}✓ Successfully reconnected#{UI.colors().reset}")

            supervised_loop(restarted_state)

          {:error, reason} ->
            IO.puts("#{UI.colors().error}✗ Retry failed: #{inspect(reason)}#{UI.colors().reset}")

            offer_manual_restart(new_state)
        end

      "q" ->
        IO.puts("#{UI.colors().info}Exiting...#{UI.colors().reset}")
        cleanup_processes(state)
        :ok

      _ ->
        offer_manual_restart(state)
    end
  end

  defp start_processes(state) do
    # Start client first - it will hibernate waiting for transport's :initialize message
    with {:ok, client_pid} <- start_client(state),
         {:ok, transport_pid} <- start_transport(state) do
      Process.monitor(transport_pid)
      Process.monitor(client_pid)

      IO.puts("#{UI.colors().info}• Checking connection...#{UI.colors().reset}")
      CLI.check_client_connection(client_pid)

      {:ok, %{state | transport_pid: transport_pid, client_pid: client_pid}}
    end
  end

  defp start_transport(%{transport_module: module, transport_opts: opts}) do
    IO.puts("#{UI.colors().info}• Starting transport...#{UI.colors().reset}")

    case module.start_link(opts) do
      {:ok, pid} ->
        IO.puts("#{UI.colors().success}✓ Transport started#{UI.colors().reset}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        IO.puts("#{UI.colors().info}• Transport already running#{UI.colors().reset}")
        {:ok, pid}

      error ->
        error
    end
  end

  defp start_client(%{client_opts: opts}) do
    IO.puts("#{UI.colors().info}• Starting client...#{UI.colors().reset}")

    case Hermes.Client.Base.start_link(opts) do
      {:ok, pid} ->
        IO.puts("#{UI.colors().success}✓ Client started#{UI.colors().reset}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        IO.puts("#{UI.colors().info}• Client already running#{UI.colors().reset}")
        {:ok, pid}

      error ->
        error
    end
  end

  defp cleanup_processes(state) do
    if state.client_pid && Process.alive?(state.client_pid) do
      Process.exit(state.client_pid, :shutdown)
    end

    if state.transport_pid && Process.alive?(state.transport_pid) do
      Process.exit(state.transport_pid, :shutdown)
    end

    Process.sleep(100)
  end
end
