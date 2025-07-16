defmodule Mix.Tasks.Hermes.StreamableHttp.Interactive do
  @shortdoc "Test the Streamable HTTP transport implementation interactively."

  @moduledoc """
  Mix task to test the Streamable HTTP transport implementation, interactively sending commands.

  ## Options

  * `--base-url` - Base URL for the MCP server (default: http://localhost:8000)
  * `--mcp-path` - MCP endpoint path (default: /mcp)
  * `--header` - Add a header to requests (can be specified multiple times)

  ## Examples

      mix hermes.streamable_http.interactive --base-url http://localhost:8000
      mix hermes.streamable_http.interactive --header "Authorization: Bearer token123"
      mix hermes.streamable_http.interactive --header "X-API-Key: secret" --header "X-Custom: value"
  """

  use Mix.Task

  alias Hermes.Transport.StreamableHTTP
  alias Mix.Interactive.SupervisedShell
  alias Mix.Interactive.UI

  @switches [
    base_url: :string,
    mcp_path: :string,
    header: :keep,
    verbose: :count
  ]

  def run(args) do
    # Start required applications without requiring a project
    Application.ensure_all_started([:hermes_mcp, :peri])

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
    headers = parse_headers(Keyword.get_values(parsed, :header))

    header = UI.header("HERMES MCP STREAMABLE HTTP INTERACTIVE")
    IO.puts(header)

    IO.puts("#{UI.colors().info}Connecting to Streamable HTTP server at: #{server_url}#{UI.colors().reset}\n")

    SupervisedShell.start(
      transport_module: StreamableHTTP,
      transport_opts: [
        name: StreamableHTTP,
        client: :streamable_http_test,
        base_url: base_url,
        mcp_path: mcp_path,
        headers: headers
      ],
      client_opts: [
        name: :streamable_http_test,
        transport: [layer: StreamableHTTP, name: StreamableHTTP],
        protocol_version: "2025-03-26",
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
