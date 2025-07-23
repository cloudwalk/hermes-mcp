defmodule Mix.Interactive.CLI do
  @moduledoc false

  alias Mix.Interactive.Shell
  alias Mix.Interactive.UI

  @version Mix.Project.config()[:version]

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
          mcp_path: :string,
          header: :keep,
          sse_path: :string,
          ws_path: :string,
          command: :string,
          args: :string,
          verbose: :count
        ],
        aliases: [t: :transport, c: :command, v: :verbose]
      )

    verbose_count = opts[:verbose] || 0
    log_level = get_log_level_from_verbose(verbose_count)
    configure_logger_with_metadata(log_level)

    transport = opts[:transport] || "sse"

    case transport do
      "sse" ->
        run_sse_interactive(opts)

      "websocket" ->
        run_websocket_interactive(opts)

      "stdio" ->
        run_stdio_interactive(opts)

      "streamable_http" ->
        run_streamable_http_interactive(opts)

      _ ->
        IO.puts("""
        #{UI.colors().error}ERROR: Unknown transport type "#{transport}"
        Usage: hermes-mcp --transport [sse|websocket|stdio|streamable_http] [options]

        Available transports:
          sse             - SSE transport implementation
          websocket       - WebSocket transport implementation
          stdio           - STDIO transport implementation
          streamable_http - StreamableHTTP transport implementation

        Run with --help for more information#{UI.colors().reset}
        """)

        System.halt(1)
    end
  end

  defp run_sse_interactive(opts) do
    server_options = Keyword.put_new(opts, :base_url, "http://localhost:8000")

    server_url =
      Path.join(server_options[:base_url], server_options[:base_path] || "")

    IO.puts(UI.header("HERMES MCP SSE INTERACTIVE"))

    client_info = %{"name" => "Hermes.CLI.SSE", "version" => "0.1.0"}
    name = SSETest
    transport = SSETest.Transport

    opts = [name: name, transport: {:sse, server_options}, client_info: client_info]
    {:ok, _} = Hermes.Client.Supervisor.start_link(name, opts)

    sse = Process.whereis(transport)

    IO.puts("#{UI.colors().info}Connecting to SSE server at: #{server_url}#{UI.colors().reset}\n")

    check_sse_connection(sse)

    client = Process.whereis(name)
    IO.puts("#{UI.colors().info}• Starting client connection...#{UI.colors().reset}")
    check_client_connection(client)

    IO.puts("\nType #{UI.colors().command}help#{UI.colors().reset} for available commands\n")

    Shell.loop(client)
  end

  defp run_websocket_interactive(opts) do
    server_options = Keyword.put_new(opts, :base_url, "http://localhost:8000")

    server_url =
      Path.join(server_options[:base_url], server_options[:base_path] || "")

    IO.puts(UI.header("HERMES MCP WEBSOCKET INTERACTIVE"))

    client_info = %{"name" => "Hermes.CLI.Websocket", "version" => "0.1.0"}

    name = WebsocketTest
    transport = WebsocketTest.Transport

    opts = [
      name: name,
      transport: {:websocket, server_options},
      client_info: client_info
    ]

    {:ok, _} = Hermes.Client.Supervisor.start_link(name, opts)

    ws = Process.whereis(transport)

    IO.puts("#{UI.colors().info}Connecting to WebSocket server at: #{server_url}#{UI.colors().reset}\n")

    check_websocket_connection(ws)

    client = Process.whereis(name)
    IO.puts("#{UI.colors().info}• Starting client connection...#{UI.colors().reset}")
    check_client_connection(client)

    IO.puts("\nType #{UI.colors().command}help#{UI.colors().reset} for available commands\n")

    Shell.loop(client)
  end

  defp run_stdio_interactive(opts) do
    cmd = opts[:command] || "mcp"
    args = String.split(opts[:args] || "run,priv/dev/echo/index.py", ",", trim: true)

    IO.puts(UI.header("HERMES MCP STDIO INTERACTIVE"))

    IO.puts("#{UI.colors().info}Starting STDIO interaction MCP server#{UI.colors().reset}\n")

    if cmd == "mcp" and not (!!System.find_executable("mcp")) do
      IO.puts(
        "#{UI.colors().error}Error: mcp executable not found in PATH, maybe you need to activate venv#{UI.colors().reset}"
      )

      System.halt(1)
    end

    client_info = %{"name" => "Hermes.CLI.STDIO", "versoin" => "0.1.0"}
    name = STDIOTest
    transport = STDIOTest.Transport

    opts = [
      name: name,
      transport: {:stdio, command: cmd, args: args},
      client_info: client_info
    ]

    {:ok, _} = Hermes.Client.Supervisor.start_link(name, opts)

    if Process.whereis(transport) do
      IO.puts("#{UI.colors().success}✓ STDIO transport started#{UI.colors().reset}")
    end

    client = Process.whereis(name)
    IO.puts("#{UI.colors().info}• Starting client connection...#{UI.colors().reset}")
    check_client_connection(client)

    IO.puts("\nType #{UI.colors().command}help#{UI.colors().reset} for available commands\n")

    Shell.loop(client)
  end

  defp run_streamable_http_interactive(opts) do
    headers = parse_headers(Keyword.get_values(opts, :header))

    server_options =
      opts
      |> Keyword.put(:headers, headers)
      |> Keyword.put_new(:base_url, "http://localhost:8000")

    server_url =
      Path.join(server_options[:base_url], server_options[:base_path] || "")

    IO.puts(UI.header("HERMES MCP STREAMABLE HTTP INTERACTIVE"))

    client_info = %{"name" => "Hermes.CLI.StreamableHTTP", "version" => "0.1.0"}
    name = StreamableHTTPTest
    transport = StreamableHTTPTest.Transport

    opts = [
      name: name,
      transport: {:streamable_http, server_options},
      client_info: client_info
    ]

    {:ok, _} = Hermes.Client.Supervisor.start_link(name, opts)

    http = Process.whereis(transport)

    IO.puts("#{UI.colors().info}Connecting to StreamableHTTP server at: #{server_url}#{UI.colors().reset}\n")

    check_streamable_http_connection(http)

    client = Process.whereis(name)
    IO.puts("#{UI.colors().info}• Starting client connection...#{UI.colors().reset}")
    check_client_connection(client)

    IO.puts("\nType #{UI.colors().command}help#{UI.colors().reset} for available commands\n")

    Shell.loop(client)
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

  def check_client_connection(client, attempt \\ 5)

  def check_client_connection(_client, attempt) when attempt <= 0 do
    IO.puts("#{UI.colors().error}✗ Server connection not established#{UI.colors().reset}")

    IO.puts("#{UI.colors().info}Use the 'initialize' command to retry connection#{UI.colors().reset}")
  end

  def check_client_connection(client, attempt) do
    :timer.sleep(200 * attempt)

    if cap = Hermes.Client.Base.get_server_capabilities(client) do
      IO.puts("#{UI.colors().info}Server capabilities: #{inspect(cap, pretty: true)}#{UI.colors().reset}")

      IO.puts("#{UI.colors().success}✓ Successfully connected to server#{UI.colors().reset}")
    else
      IO.puts("#{UI.colors().warning}! Waiting for server connection...#{UI.colors().reset}")

      check_client_connection(client, attempt - 1)
    end
  end

  def check_sse_connection(sse, attempt \\ 3)

  def check_sse_connection(_sse, attempt) when attempt <= 0 do
    IO.puts("#{UI.colors().error}✗ SSE connection not established#{UI.colors().reset}")

    IO.puts("#{UI.colors().info}Use the 'initialize' command to retry connection#{UI.colors().reset}")
  end

  def check_sse_connection(sse, attempt) do
    :timer.sleep(500)

    state = :sys.get_state(sse)

    if state[:message_url] == nil do
      IO.puts("#{UI.colors().warning}! Waiting for server connection...#{UI.colors().reset}")

      check_sse_connection(sse, attempt - 1)
    else
      IO.puts(
        "#{UI.colors().info}SSE connection:\n\s\s- sse stream url: #{state[:sse_url]}\n\s\s- message url: #{state[:message_url]}#{UI.colors().reset}"
      )

      IO.puts("#{UI.colors().success}✓ Successfully connected via SSE#{UI.colors().reset}")
    end
  end

  def check_websocket_connection(ws, attempt \\ 3)

  def check_websocket_connection(_ws, attempt) when attempt <= 0 do
    IO.puts("#{UI.colors().error}✗ WebSocket connection not established#{UI.colors().reset}")

    IO.puts("#{UI.colors().info}Use the 'initialize' command to retry connection#{UI.colors().reset}")
  end

  def check_websocket_connection(ws, attempt) do
    :timer.sleep(500)

    state = :sys.get_state(ws)

    if state[:stream_ref] == nil do
      IO.puts("#{UI.colors().warning}! Waiting for server connection...#{UI.colors().reset}")

      check_websocket_connection(ws, attempt - 1)
    else
      IO.puts("#{UI.colors().info}WebSocket connection:\n\s\s- ws url: #{state[:ws_url]}#{UI.colors().reset}")

      IO.puts("#{UI.colors().success}✓ Successfully connected via WebSocket#{UI.colors().reset}")
    end
  end

  def check_streamable_http_connection(http, attempt \\ 3)

  def check_streamable_http_connection(_http, attempt) when attempt <= 0 do
    IO.puts("#{UI.colors().error}✗ StreamableHTTP connection not established#{UI.colors().reset}")

    IO.puts("#{UI.colors().info}Use the 'initialize' command to retry connection#{UI.colors().reset}")
  end

  def check_streamable_http_connection(http, attempt) do
    :timer.sleep(500)

    state = :sys.get_state(http)

    if state[:message_url] == nil do
      IO.puts("#{UI.colors().warning}! Waiting for server connection...#{UI.colors().reset}")

      check_streamable_http_connection(http, attempt - 1)
    else
      IO.puts(
        "#{UI.colors().info}StreamableHTTP connection:\n\s\s- base url: #{state[:base_url]}\n\s\s- message url: #{state[:message_url]}#{UI.colors().reset}"
      )

      IO.puts("#{UI.colors().success}✓ Successfully connected via StreamableHTTP#{UI.colors().reset}")
    end
  end

  @doc false
  def show_help do
    colors = UI.colors()

    IO.puts("""
    #{colors.info}Hermes MCP Client v#{@version}#{colors.reset}
    #{colors.success}A command-line MCP client for interacting with MCP servers#{colors.reset}

    #{colors.info}USAGE:#{colors.reset}
      hermes-mcp [OPTIONS]

    #{colors.info}OPTIONS:#{colors.reset}
      #{colors.command}-h, --help#{colors.reset}             Show this help message and exit
      #{colors.command}-t, --transport TYPE#{colors.reset}   Transport type to use (sse|websocket|stdio|streamable_http) [default: sse]
      #{colors.command}-v#{colors.reset}                     Set log level: -v (warning), -vv (info), -vvv (debug) [default: error]
      
    #{colors.info}SSE TRANSPORT OPTIONS:#{colors.reset}
      #{colors.command}--base-url URL#{colors.reset}         Base URL for SSE server [default: http://localhost:8000]
      #{colors.command}--base-path PATH#{colors.reset}       Base path for the SSE server
      #{colors.command}--sse-path PATH#{colors.reset}        Path for SSE endpoint

    #{colors.info}WEBSOCKET TRANSPORT OPTIONS:#{colors.reset}
      #{colors.command}--base-url URL#{colors.reset}         Base URL for WebSocket server [default: http://localhost:8000]
      #{colors.command}--base-path PATH#{colors.reset}       Base path for the WebSocket server
      #{colors.command}--ws-path PATH#{colors.reset}         Path for WebSocket endpoint [default: /ws]

    #{colors.info}STREAMABLE HTTP TRANSPORT OPTIONS:#{colors.reset}
      #{colors.command}--base-url URL#{colors.reset}         Base URL for StreamableHTTP server [default: http://localhost:8000]
      #{colors.command}--mcp-path PATH#{colors.reset}        Base path for the StreamableHTTP server [default: /mcp]
      #{colors.command}--header HEADER#{colors.reset}        Pass HTTP header to the server, can be passed multiple times

    #{colors.info}STDIO TRANSPORT OPTIONS:#{colors.reset}
      #{colors.command}-c, --command CMD#{colors.reset}      Command to execute [default: mcp]
      #{colors.command}--args ARGS#{colors.reset}            Comma-separated arguments for the command
                               [default: run,priv/dev/echo/index.py]

    #{colors.info}EXAMPLES:#{colors.reset}
      # Connect to a local SSE server
      hermes-mcp 

      # Connect to a remote SSE server
      hermes-mcp --transport sse --base-url https://remote-server.example.com

      # Connect to a WebSocket server
      hermes-mcp --transport websocket --base-url http://localhost:8000 --ws-path /mcp/ws

      # Connect to a StreamableHTTP server
      hermes-mcp --transport streamable_http --base-url http://localhost:8000

      # Run a local MCP server with stdio
      hermes-mcp --transport stdio --command ./my-mcp-server --args arg1,arg2

    #{colors.info}INTERACTIVE COMMANDS:#{colors.reset}
      Once connected, type 'help' to see available interactive commands.
    """)
  end

  # Helper functions for log levels
  defp get_log_level_from_verbose(count) do
    case count do
      0 -> :error
      1 -> :warning
      2 -> :info
      _ -> :debug
    end
  end

  defp configure_logger_with_metadata(log_level) do
    metadata = Logger.metadata()
    Logger.configure(level: log_level)
    Logger.metadata(metadata)
  end
end
