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
  alias Mix.Interactive.UI

  @doc """
  Main command loop for interactive shells.
  """
  def loop(client) do
    IO.write("#{UI.colors().prompt}mcp> #{UI.colors().reset}")

    ""
    |> IO.gets()
    |> String.trim()
    |> Commands.process_command(client, fn -> loop(client) end)
  end
end
