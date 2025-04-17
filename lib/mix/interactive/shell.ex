defmodule Mix.Interactive.Shell do
  @moduledoc """
  Base functionality for interactive MCP shells.

  This module acts as the core command loop for interactive MCP shells,
  providing a consistent interface and user experience across different
  transport implementations (SSE, STDIO).

  It handles basic functionality like reading user input and delegating
  command processing to the appropriate handlers.
  """

  alias Mix.Interactive.Commands
  alias Mix.Interactive.Readline
  alias Mix.Interactive.UI

  @doc """
  Main command loop for interactive shells.
  """
  def loop(client) do
    loop_with_history(client, Readline.new())
  end

  defp loop_with_history(client, readline_state) do
    prompt = "#{UI.colors().prompt}mcp> #{UI.colors().reset}"

    # Store the current readline state in the process dictionary
    Process.put(:readline_state, readline_state)

    case Readline.gets(prompt, readline_state) do
      {:ok, input, new_state} ->
        Commands.process_command(input, client, fn -> loop_with_history(client, new_state) end)

      {:eof, _} ->
        IO.puts("\n#{UI.colors().info}End of input, exiting...#{UI.colors().reset}")
        Commands.process_command("exit", client, fn -> :ok end)

      {:error, reason, state} ->
        IO.puts("#{UI.colors().error}Error reading input: #{inspect(reason)}#{UI.colors().reset}")
        loop_with_history(client, state)
    end
  end

  @doc """
  Prints the command history.
  """
  def print_history(readline_state, loop_fn) do
    IO.puts("\n#{UI.colors().info}Command history:#{UI.colors().reset}")

    readline_state.history
    |> Enum.with_index(1)
    |> Enum.each(fn {cmd, idx} ->
      IO.puts("  #{UI.colors().command}#{idx}#{UI.colors().reset} #{cmd}")
    end)

    IO.puts("")
    loop_fn.()
  end
end
