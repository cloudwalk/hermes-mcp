defmodule Mix.Tasks.Stdio.Interactive do
  @shortdoc "Test the STDIO transport implementation interactively."

  @moduledoc """
  Mix task to test the STDIO transport implementation, interactively sending commands.

  ## Options

  * `--command` - Command to execute for the STDIO transport (default: "mcp")
  * `--args` - Comma-separated arguments for the command (default: "run,priv/dev/echo/index.py")
  """

  use Mix.Task

  alias Hermes.Client
  alias Hermes.Transport.STDIO
  alias Mix.Interactive.Shell
  alias Mix.Interactive.UI

  @switches [
    command: :string,
    args: :string
  ]

  def run(args) do
    # Disable logger output to keep the UI clean
    Application.put_env(:logger, :level, :error)

    Mix.Task.run("app.start")

    {parsed, _} = OptionParser.parse!(args, strict: @switches, aliases: [c: :command])
    cmd = parsed[:command] || "mcp"
    args = String.split(parsed[:args] || "run,priv/dev/echo/index.py", ",", trim: true)

    header = UI.header("HERMES MCP STDIO INTERACTIVE")
    IO.puts(header)
    IO.puts("#{UI.colors().info}Starting STDIO interaction MCP server#{UI.colors().reset}\n")

    if cmd == "mcp" and not (!!System.find_executable("mcp")) do
      IO.puts(
        "#{UI.colors().error}Error: mcp executable not found in PATH, maybe you need to activate venv#{UI.colors().reset}"
      )

      System.halt(1)
    end

    {:ok, _} =
      STDIO.start_link(
        command: cmd,
        args: args,
        client: :stdio_test
      )

    IO.puts("#{UI.colors().success}✓ STDIO transport started#{UI.colors().reset}")

    {:ok, client} =
      Client.start_link(
        name: :stdio_test,
        transport: [layer: STDIO],
        client_info: %{
          "name" => "Mix.Tasks.STDIO",
          "version" => "1.0.0"
        },
        capabilities: %{
          "roots" => %{
            "listChanged" => true
          },
          "sampling" => %{}
        }
      )

    IO.puts("#{UI.colors().success}✓ Client connected successfully#{UI.colors().reset}")
    IO.puts("\nType #{UI.colors().command}help#{UI.colors().reset} for available commands\n")

    Shell.loop(client)
  end
end
