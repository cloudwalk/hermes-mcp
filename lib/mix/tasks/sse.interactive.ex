defmodule Mix.Tasks.Sse.Interactive do
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
    sse_path: :string
  ]

  def run(args) do
    # Disable logger output to keep the UI clean
    Application.put_env(:logger, :level, :error)

    Mix.Task.run("app.start")

    {parsed, _} = OptionParser.parse!(args, strict: @switches)
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
        client_info: %{
          "name" => "Mix.Tasks.SSE",
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
