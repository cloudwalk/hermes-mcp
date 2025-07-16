defmodule Mix.Tasks.Hermes.Sse.Interactive do
  @shortdoc "Test the SSE transport implementation interactively."

  @moduledoc """
  Mix task to test the SSE transport implementation, interactively sending commands.

  > #### Deprecated {: .warning}
  >
  > This task uses the deprecated SSE transport. As of MCP specification 2025-03-26,
  > the HTTP+SSE transport has been replaced by the Streamable HTTP transport.
  >
  > For testing new servers, please use `mix hermes.streamable_http.interactive` instead.
  > This task is maintained for backward compatibility with servers using the
  > 2024-11-05 protocol version.

  ## Options

  * `--base-url` - Base URL for the SSE server (default: http://localhost:8000)
  * `--base-path` - Base path to append to the base URL
  * `--sse-path` - Specific SSE endpoint path
  * `--header` - Add a header to requests (can be specified multiple times)

  ## Examples

      mix hermes.sse.interactive --base-url http://localhost:8000
      mix hermes.sse.interactive --header "Authorization: Bearer token123"
      mix hermes.sse.interactive --header "X-API-Key: secret" --header "X-Custom: value"
  """

  use Mix.Task

  alias Hermes.Transport.SSE
  alias Mix.Interactive.SupervisedShell
  alias Mix.Interactive.UI

  @switches [
    base_url: :string,
    base_path: :string,
    sse_path: :string,
    header: :keep,
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
    base_path = parsed[:base_path] || "/"
    sse_path = parsed[:sse_path] || "/sse"
    headers = parse_headers(Keyword.get_values(parsed, :header))

    if base_url == "" do
      IO.puts("#{UI.colors().error}Error: --base-url cannot be empty#{UI.colors().reset}")

      IO.puts("Please provide a valid URL, e.g., --base-url=http://localhost:8000")
      System.halt(1)
    end

    server_url = base_url |> URI.merge(base_path) |> URI.to_string()

    header = UI.header("HERMES MCP SSE INTERACTIVE")
    IO.puts(header)

    IO.puts("#{UI.colors().info}Connecting to SSE server at: #{server_url}#{UI.colors().reset}\n")

    SupervisedShell.start(
      transport_module: SSE,
      transport_opts: [
        name: SSE,
        client: :sse_test,
        server: [
          base_url: base_url,
          base_path: base_path,
          sse_path: sse_path
        ],
        headers: headers
      ],
      client_opts: [
        name: :sse_test,
        transport: [layer: SSE, name: SSE],
        protocol_version: "2024-11-05",
        client_info: %{
          "name" => "Mix.Tasks.SSE",
          "version" => "1.0.0"
        },
        capabilities: %{
          "tools" => %{},
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

  defp parse_headers(header_list) when is_list(header_list) do
    header_list
    |> Enum.map(&parse_header/1)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp parse_header(header_string) do
    case String.split(header_string, ":", parts: 2) do
      [key, value] ->
        {String.trim(key), String.trim(value)}

      _ ->
        IO.puts(
          "#{UI.colors().warning}Warning: Invalid header format '#{header_string}'. Expected 'Header-Name: value'#{UI.colors().reset}"
        )

        nil
    end
  end
end
