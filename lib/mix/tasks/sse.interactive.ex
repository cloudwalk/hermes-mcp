defmodule Mix.Tasks.Hermes.Sse.Interactive do
  @shortdoc "Test the SSE transport implementation interactively."

  @moduledoc """
  Mix task to test the SSE transport implementation, interactively sending commands.

  ## Options

  * `--base-url` - Base URL for the SSE server (default: http://localhost:8000)
  * `--base-path` - Base path to append to the base URL
  * `--sse-path` - Specific SSE endpoint path
  """

  use Mix.Task

  alias Hermes.Client
  alias Hermes.Transport.SSE
  alias Mix.Interactive.Shell
  alias Mix.Interactive.UI

  @switches [
    base_url: :string,
    base_path: :string,
    sse_path: :string,
    verbose: :count
  ]

  def run(args) do
    # Start required applications without requiring a project
    Application.ensure_all_started([:hermes_mcp, :peri])

    # Parse arguments and set log level
    {parsed, _} =
      OptionParser.parse!(args,
        strict: @switches,
        aliases: [v: :verbose]
      )

    verbose_count = parsed[:verbose] || 0
    log_level = get_log_level(verbose_count)
    configure_logger(log_level)

    server_options = Keyword.put_new(parsed, :base_url, "http://localhost:8000")
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
        protocol_version: "2024-11-05",
        client_info: %{
          "name" => "Mix.Tasks.SSE",
          "version" => "1.0.0"
        },
        capabilities: %{
          "tools" => %{},
          "sampling" => %{}
        }
      )

    IO.puts("#{UI.colors().success}✓ Client connected successfully#{UI.colors().reset}")
    IO.puts("\nType #{UI.colors().command}help#{UI.colors().reset} for available commands\n")

    Shell.loop(client)
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
