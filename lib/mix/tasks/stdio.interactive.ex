defmodule Mix.Tasks.Hermes.Stdio.Interactive do
  @shortdoc "Test the STDIO transport implementation interactively."

  @moduledoc """
  Mix task to test the STDIO transport implementation, interactively sending commands.

  ## Options

  * `--command` - Command to execute for the STDIO transport (default: "mcp")
  * `--args` - Comma-separated arguments for the command (default: "run,priv/dev/echo/index.py")
  """

  use Mix.Task

  alias Hermes.Transport.STDIO
  alias Mix.Interactive.SupervisedShell
  alias Mix.Interactive.UI

  @switches [
    command: :string,
    args: :string,
    verbose: :count
  ]

  def run(args) do
    # Start required applications without requiring a project
    Application.ensure_all_started(:hermes_mcp)

    # Parse arguments and set log level
    {parsed, _} =
      OptionParser.parse!(args,
        strict: @switches,
        aliases: [c: :command, v: :verbose]
      )

    verbose_count = parsed[:verbose] || 0
    log_level = get_log_level(verbose_count)
    configure_logger(log_level)

    cmd = parsed[:command] || "mcp"

    args =
      String.split(parsed[:args] || "run,priv/dev/echo/index.py", ",", trim: true)

    header = UI.header("HERMES MCP STDIO INTERACTIVE")
    IO.puts(header)

    IO.puts("#{UI.colors().info}Starting STDIO interaction MCP server#{UI.colors().reset}\n")

    if cmd == "mcp" and not (!!System.find_executable("mcp")) do
      IO.puts(
        "#{UI.colors().error}Error: mcp executable not found in PATH, maybe you need to activate venv#{UI.colors().reset}"
      )

      System.halt(1)
    end

    SupervisedShell.start(
      transport_module: STDIO,
      transport_opts: [
        name: STDIO,
        command: cmd,
        args: args,
        client: :stdio_test
      ],
      client_opts: [
        name: :stdio_test,
        transport: [layer: STDIO, name: STDIO],
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
      ]
    )
  end

  # Helper functions
  defp get_log_level(count) do
    case count do
      0 -> :error
      1 -> :warning
      2 -> :info
      _ -> :debug
    end
  end

  defp configure_logger(log_level) do
    metadata = Logger.metadata()
    Logger.configure(level: log_level)
    Logger.metadata(metadata)
  end
end
