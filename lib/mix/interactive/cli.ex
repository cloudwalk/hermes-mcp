defmodule Mix.Interactive.CLI do
  @moduledoc """
  Standalone CLI application for Hermes MCP interactive shells.

  This module serves as the entry point for the standalone binary compiled with Burrito.
  It can start either the SSE or STDIO interactive shell based on command-line arguments.
  """

  alias Hermes.Client
  alias Hermes.Transport.SSE
  alias Hermes.Transport.STDIO
  alias Mix.Interactive.Shell
  alias Mix.Interactive.UI

  @doc """
  Main entry point for the standalone CLI application.
  """
  def main(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          transport: :string,
          base_url: :string,
          base_path: :string,
          sse_path: :string,
          command: :string,
          args: :string
        ],
        aliases: [t: :transport, c: :command]
      )

    transport = opts[:transport] || "sse"

    case transport do
      "sse" ->
        run_sse_interactive(opts)

      "stdio" ->
        run_stdio_interactive(opts)

      _ ->
        IO.puts("""
        #{UI.colors().error}ERROR: Unknown transport type "#{transport}"
        Usage: hermes-mcp --transport [sse|stdio] [options]

        Available transports:
          sse   - SSE transport implementation
          stdio - STDIO transport implementation

        Run with --help for more information#{UI.colors().reset}
        """)

        System.halt(1)
    end
  end

  defp run_sse_interactive(opts) do
    # Disable logger output to keep the UI clean
    Logger.configure(level: :error)

    server_options = Keyword.put_new(opts, :base_url, "http://localhost:8000")
    server_url = Path.join(server_options[:base_url], server_options[:base_path] || "")

    header = UI.header("HERMES MCP SSE INTERACTIVE")
    IO.puts(header)
    IO.puts("#{UI.colors().info}Connecting to SSE server at: #{server_url}#{UI.colors().reset}\n")

    {:ok, _} =
      SSE.start_link(
        client: :sse_test,
        server: server_options
      )

    IO.puts("#{UI.colors().success}✓ SSE transport started#{UI.colors().reset}")

    {:ok, client} =
      Client.start_link(
        name: :sse_test,
        transport: [layer: SSE],
        client_info: %{
          "name" => "Hermes.CLI.SSE",
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

  defp run_stdio_interactive(opts) do
    # Disable logger output to keep the UI clean
    Logger.configure(level: :error)

    cmd = opts[:command] || "mcp"
    args = String.split(opts[:args] || "run,priv/dev/echo/index.py", ",", trim: true)

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
          "name" => "Hermes.CLI.STDIO",
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
