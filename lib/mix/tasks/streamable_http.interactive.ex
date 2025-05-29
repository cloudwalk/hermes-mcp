defmodule Mix.Tasks.Hermes.StreamableHttp.Interactive do
  @shortdoc "Test the Streamable HTTP transport implementation interactively."

  @moduledoc """
  Mix task to test the Streamable HTTP transport implementation, interactively sending commands.

  ## Options

  * `--base-url` - Base URL for the MCP server (default: http://localhost:8000)
  * `--mcp-path` - MCP endpoint path (default: /mcp)
  """

  use Mix.Task

  alias Hermes.Client
  alias Hermes.Transport.StreamableHTTP
  alias Mix.Interactive.Shell
  alias Mix.Interactive.UI

  @switches [
    base_url: :string,
    mcp_path: :string,
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

    base_url = parsed[:base_url] || "http://localhost:8000"
    mcp_path = parsed[:mcp_path] || "/mcp"
    server_url = Path.join(base_url, mcp_path)

    header = UI.header("HERMES MCP STREAMABLE HTTP INTERACTIVE")
    IO.puts(header)
    IO.puts("#{UI.colors().info}Connecting to Streamable HTTP server at: #{server_url}#{UI.colors().reset}\n")

    {:ok, _} =
      StreamableHTTP.start_link(
        client: :streamable_http_test,
        base_url: base_url,
        mcp_path: mcp_path
      )

    IO.puts("#{UI.colors().success}✓ Streamable HTTP transport started#{UI.colors().reset}")

    {:ok, client} =
      Client.start_link(
        name: :streamable_http_test,
        transport: [layer: StreamableHTTP],
        client_info: %{
          "name" => "Mix.Tasks.StreamableHTTP",
          "version" => "1.0.0"
        },
        capabilities: %{
          "roots" => %{
            "listChanged" => true
          },
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
