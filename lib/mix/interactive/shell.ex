defmodule Mix.Interactive.Shell do
  @moduledoc false

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
