if Code.ensure_loaded?(:gun) do
  defmodule Mix.Tasks.Hermes.Websocket.Interactive do
    @shortdoc "Test the WebSocket transport implementation interactively."

    @moduledoc """
    Mix task to test the WebSocket transport implementation, interactively sending commands.

    ## Options

    * `--base-url` - Base URL for the WebSocket server (default: http://localhost:8000)
    * `--base-path` - Base path to append to the base URL
    * `--ws-path` - Specific WebSocket endpoint path (default: /ws)
    """

    use Mix.Task

    alias Hermes.Client
    alias Hermes.Transport.WebSocket
    alias Mix.Interactive.CLI
    alias Mix.Interactive.Shell
    alias Mix.Interactive.UI

    @switches [
      base_url: :string,
      base_path: :string,
      ws_path: :string,
      verbose: :count
    ]

    def run(args) do
      # Start required applications without requiring a project
      Application.ensure_all_started([:hermes_mcp, :peri, :gun])

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

      header = UI.header("HERMES MCP WEBSOCKET INTERACTIVE")
      IO.puts(header)
      IO.puts("#{UI.colors().info}Connecting to WebSocket server at: #{server_url}#{UI.colors().reset}\n")

      {:ok, pid} =
        WebSocket.start_link(
          client: :websocket_test,
          server: server_options
        )

      IO.puts("#{UI.colors().success}✓ WebSocket transport started#{UI.colors().reset}")

      {:ok, client} =
        Client.start_link(
          name: :websocket_test,
          transport: [layer: WebSocket, name: pid],
          client_info: %{
            "name" => "Mix.Tasks.WebSocket",
            "version" => "1.0.0"
          },
          capabilities: %{
            "tools" => %{},
            "sampling" => %{}
          }
        )

      IO.puts("#{UI.colors().success}✓ Client connected successfully#{UI.colors().reset}")
      
      IO.puts("#{UI.colors().info}• Starting client connection...#{UI.colors().reset}")
      CLI.check_client_connection(client)
      
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
end
