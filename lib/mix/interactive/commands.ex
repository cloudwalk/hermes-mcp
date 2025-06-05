defmodule Mix.Interactive.Commands do
  @moduledoc """
  Common command implementations for interactive MCP shells.

  This module contains the implementation of all commands available in the
  interactive MCP shells. It provides a consistent set of commands across
  different transport implementations, with shared functionality for:

  - Listing available commands
  - Fetching and displaying tools, prompts, and resources
  - Calling tools and getting prompts
  - Handling user input and error cases
  - Formatting and displaying results

  Each command follows a similar pattern, receiving client and loop function
  references to enable proper continuation of the interactive shell.
  """

  alias Hermes.Client
  alias Hermes.MCP.Response
  alias Hermes.Transport.SSE
  alias Hermes.Transport.STDIO
  alias Hermes.Transport.StreamableHTTP
  alias Mix.Interactive
  alias Mix.Interactive.State
  alias Mix.Interactive.UI

  @commands %{
    "help" => "Show this help message",
    "ping" => "Send a ping to the server to check connection health",
    "list_tools" => "List server tools",
    "call_tool" => "Call a server tool with arguments",
    "list_prompts" => "List server prompts",
    "get_prompt" => "Get a server prompt",
    "list_resources" => "List server resources",
    "read_resource" => "Read a server resource",
    "initialize" => "Retry server connection initialization",
    "show_state" => "Show internal state of client and transport",
    "clear" => "Clear the screen",
    "exit" => "Exit the interactive session"
  }

  @doc """
  Returns the map of available commands and their descriptions.
  """
  def commands, do: @commands

  @doc """
  Process a command entered by the user.
  """
  def process_command("help", _client, loop_fn), do: print_help(loop_fn)
  def process_command("ping", client, loop_fn), do: ping_server(client, loop_fn)
  def process_command("list_tools", client, loop_fn), do: list_tools(client, loop_fn)
  def process_command("call_tool", client, loop_fn), do: call_tool(client, loop_fn)
  def process_command("list_prompts", client, loop_fn), do: list_prompts(client, loop_fn)
  def process_command("get_prompt", client, loop_fn), do: get_prompt(client, loop_fn)
  def process_command("initialize", client, loop_fn), do: initialize_client(client, loop_fn)
  def process_command("show_state", client, loop_fn), do: show_state(client, loop_fn)

  def process_command("list_resources", client, loop_fn) do
    list_resources(client, loop_fn)
  end

  def process_command("read_resource", client, loop_fn) do
    read_resource(client, loop_fn)
  end

  def process_command("clear", _client, loop_fn), do: clear_screen(loop_fn)
  def process_command("exit", client, _loop_fn), do: exit_client(client)
  def process_command("", _client, loop_fn), do: loop_fn.()
  def process_command(unknown, _client, loop_fn), do: unknown_command(unknown, loop_fn)

  defp print_help(loop_fn) do
    IO.puts("\n#{UI.colors().info}Available commands:#{UI.colors().reset}")

    Enum.each(@commands, fn {cmd, desc} ->
      IO.puts("  #{UI.colors().command}#{String.pad_trailing(cmd, 15)}#{UI.colors().reset} #{desc}")
    end)

    IO.puts("")
    loop_fn.()
  end

  defp list_tools(client, loop_fn) do
    IO.puts("\n#{UI.colors().info}Fetching tools...#{UI.colors().reset}")

    case Client.list_tools(client) do
      {:ok, %Response{result: %{"tools" => tools}}} ->
        UI.print_items("tools", tools, "name")

      {:error, reason} ->
        UI.print_error(reason)
    end

    loop_fn.()
  end

  defp call_tool(client, loop_fn) do
    IO.write("#{UI.colors().prompt}Tool name: #{UI.colors().reset}")
    tool_name = "" |> IO.gets() |> String.trim()

    IO.write("#{UI.colors().prompt}Tool arguments (JSON): #{UI.colors().reset}")
    args_input = "" |> IO.gets() |> String.trim()

    case JSON.decode(args_input) do
      {:ok, tool_args} ->
        perform_tool_call(client, tool_name, tool_args)

      {:error, error} ->
        IO.puts("#{UI.colors().error}Error parsing JSON: #{inspect(error)}#{UI.colors().reset}")
    end

    loop_fn.()
  end

  defp perform_tool_call(client, tool_name, tool_args) do
    IO.puts("\n#{UI.colors().info}Calling tool #{tool_name}...#{UI.colors().reset}")

    case Client.call_tool(client, tool_name, tool_args) do
      {:ok, %Response{result: result}} ->
        IO.puts("#{UI.colors().success}Tool call successful#{UI.colors().reset}")
        IO.puts("\n#{UI.colors().info}Result:#{UI.colors().reset}")
        IO.puts(UI.format_output(result))

      {:error, reason} ->
        UI.print_error(reason)
    end

    IO.puts("")
  end

  defp list_prompts(client, loop_fn) do
    IO.puts("\n#{UI.colors().info}Fetching prompts...#{UI.colors().reset}")

    case Client.list_prompts(client) do
      {:ok, %Response{result: %{"prompts" => prompts}}} ->
        UI.print_items("prompts", prompts, "name")

      {:error, reason} ->
        UI.print_error(reason)
    end

    loop_fn.()
  end

  defp get_prompt(client, loop_fn) do
    IO.write("#{UI.colors().prompt}Prompt name: #{UI.colors().reset}")
    prompt_name = "" |> IO.gets() |> String.trim()

    IO.write("#{UI.colors().prompt}Prompt arguments (JSON): #{UI.colors().reset}")
    args_input = "" |> IO.gets() |> String.trim()

    case JSON.decode(args_input) do
      {:ok, prompt_args} ->
        perform_get_prompt(client, prompt_name, prompt_args)

      {:error, error} ->
        IO.puts("#{UI.colors().error}Error parsing JSON: #{inspect(error)}#{UI.colors().reset}")
    end

    loop_fn.()
  end

  defp perform_get_prompt(client, prompt_name, prompt_args) do
    IO.puts("\n#{UI.colors().info}Getting prompt #{prompt_name}...#{UI.colors().reset}")

    case Client.get_prompt(client, prompt_name, prompt_args) do
      {:ok, %Response{result: result}} ->
        IO.puts("#{UI.colors().success}Got prompt successfully#{UI.colors().reset}")
        IO.puts("\n#{UI.colors().info}Result:#{UI.colors().reset}")
        IO.puts(UI.format_output(result))

      {:error, reason} ->
        UI.print_error(reason)
    end

    IO.puts("")
  end

  defp list_resources(client, loop_fn) do
    IO.puts("\n#{UI.colors().info}Fetching resources...#{UI.colors().reset}")

    case Client.list_resources(client) do
      {:ok, %Response{result: %{"resources" => resources}}} ->
        UI.print_items("resources", resources, "uri")

      {:error, reason} ->
        UI.print_error(reason)
    end

    loop_fn.()
  end

  defp read_resource(client, loop_fn) do
    IO.write("#{UI.colors().prompt}Resource URI: #{UI.colors().reset}")
    resource_uri = "" |> IO.gets() |> String.trim()

    IO.puts("\n#{UI.colors().info}Reading resource #{resource_uri}...#{UI.colors().reset}")

    case Client.read_resource(client, resource_uri) do
      {:ok, %Response{result: result}} ->
        IO.puts("#{UI.colors().success}Read resource successfully#{UI.colors().reset}")
        IO.puts("\n#{UI.colors().info}Content:#{UI.colors().reset}")
        IO.puts(UI.format_output(result))

      {:error, reason} ->
        UI.print_error(reason)
    end

    IO.puts("")
    loop_fn.()
  end

  defp clear_screen(loop_fn) do
    IO.write(IO.ANSI.clear() <> IO.ANSI.home())
    loop_fn.()
  end

  defp exit_client(client) do
    IO.puts("\n#{UI.colors().info}Closing connection and exiting...#{UI.colors().reset}")
    Client.close(client)
    :ok
  end

  defp initialize_client(client, loop_fn) do
    IO.puts("\n#{UI.colors().info}Reinitializing client connection...#{UI.colors().reset}")

    old_state = :sys.get_state(client)

    GenServer.cast(client, :initialize)
    Process.flag(:trap_exit, true)
    :timer.sleep(500)

    receive do
      {:EXIT, _, {:error, err}} ->
        print_initialization_error(err, old_state)
        loop_fn.()
    after
      500 -> :ok
    end

    if Process.alive?(client) do
      Interactive.CLI.check_client_connection(client)
      loop_fn.()
    else
      IO.puts("#{UI.colors().error}Client #{inspect(client)} is not alive#{UI.colors().reset}")

      if old_state do
        IO.puts("#{UI.colors().info}Last client state before failure:#{UI.colors().reset}")
        State.print_state(client)
      end

      loop_fn.()
    end
  end

  defp print_initialization_error(error, state) do
    UI.print_error(error)

    verbose = System.get_env("HERMES_VERBOSE") == "1"

    if verbose && state do
      IO.puts("\n#{UI.colors().info}Additional error context (HERMES_VERBOSE=1):#{UI.colors().reset}")

      case error do
        %{reason: :connection_refused} ->
          print_connection_error_context(state)

        %{reason: :request_timeout} ->
          print_timeout_error_context(state)

        %{reason: :server_error, data: data} ->
          print_server_error_context(data, state)

        _ ->
          IO.puts("  #{UI.colors().info}Last client state:#{UI.colors().reset}")
          # Can't use print_state directly as client might be dead
          IO.puts("    #{inspect(state, pretty: true, limit: 10)}")
      end
    else
      IO.puts("#{UI.colors().info}For more detailed error information, set HERMES_VERBOSE=1#{UI.colors().reset}")
    end
  end

  defp print_connection_error_context(state) do
    transport_info = state.transport

    case transport_info do
      %{layer: SSE} ->
        transport_pid = transport_info[:name] || SSE

        if Process.alive?(transport_pid) do
          transport_state = :sys.get_state(transport_pid)
          IO.puts("  #{UI.colors().info}Server URL:#{UI.colors().reset} #{transport_state[:server_url]}")
          IO.puts("  #{UI.colors().info}SSE URL:#{UI.colors().reset} #{transport_state[:sse_url]}")
        end

      %{layer: STDIO} ->
        transport_pid = transport_info[:name] || STDIO

        if Process.alive?(transport_pid) do
          transport_state = :sys.get_state(transport_pid)
          IO.puts("  #{UI.colors().info}Command:#{UI.colors().reset} #{transport_state.command}")
          print_stdio_args(transport_state)
        end

      %{layer: StreamableHTTP} ->
        transport_pid = transport_info[:name] || StreamableHTTP

        if Process.alive?(transport_pid) do
          transport_state = :sys.get_state(transport_pid)
          IO.puts("  #{UI.colors().info}MCP URL:#{UI.colors().reset} #{URI.to_string(transport_state.mcp_url)}")

          if transport_state.session_id do
            IO.puts("  #{UI.colors().info}Session ID:#{UI.colors().reset} #{transport_state.session_id}")
          end
        end

      _ ->
        IO.puts("  #{UI.colors().info}Transport:#{UI.colors().reset} #{inspect(transport_info)}")
    end

    IO.puts("  #{UI.colors().info}Client Info:#{UI.colors().reset} #{inspect(state.client_info)}")
  end

  defp print_timeout_error_context(state) do
    IO.puts("  #{UI.colors().info}Protocol Version:#{UI.colors().reset} #{state.protocol_version}")
    IO.puts("  #{UI.colors().info}Pending Requests:#{UI.colors().reset} #{map_size(state.pending_requests)}")

    if state.server_capabilities do
      IO.puts("  #{UI.colors().info}Server Capabilities:#{UI.colors().reset} #{inspect(state.server_capabilities)}")
    end
  end

  defp print_server_error_context(data, state) do
    IO.puts("  #{UI.colors().info}Server Error Data:#{UI.colors().reset} #{inspect(data)}")
    IO.puts("  #{UI.colors().info}Protocol Version:#{UI.colors().reset} #{state.protocol_version}")

    if state.server_info do
      IO.puts("  #{UI.colors().info}Server Info:#{UI.colors().reset} #{inspect(state.server_info)}")
    end
  end

  defp show_state(client, loop_fn) do
    IO.puts("\n#{UI.colors().info}Getting internal state information...#{UI.colors().reset}")

    State.print_state(client)

    IO.puts("")
    loop_fn.()
  end

  defp ping_server(client, loop_fn) do
    IO.puts("\n#{UI.colors().info}Pinging server...#{UI.colors().reset}")

    case Client.ping(client) do
      :pong ->
        IO.puts("#{UI.colors().success}✓ Pong! Server is responding#{UI.colors().reset}")

      {:error, reason} ->
        UI.print_error(reason)
    end

    IO.puts("")
    loop_fn.()
  end

  defp unknown_command(command, loop_fn) do
    IO.puts("#{UI.colors().error}Unknown command: #{command}#{UI.colors().reset}")
    IO.puts("Type #{UI.colors().command}help#{UI.colors().reset} for available commands")
    loop_fn.()
  end

  defp print_stdio_args(state) do
    if state.args do
      IO.puts("  #{UI.colors().info}Args:#{UI.colors().reset} #{inspect(state.args)}")
    end
  end
end
