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
  alias Mix.Interactive.UI

  @commands %{
    "help" => "Show this help message",
    "list_tools" => "List server tools",
    "call_tool" => "Call a server tool with arguments",
    "list_prompts" => "List server prompts",
    "get_prompt" => "Get a server prompt",
    "list_resources" => "List server resources",
    "read_resource" => "Read a server resource",
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
  def process_command("list_tools", client, loop_fn), do: list_tools(client, loop_fn)
  def process_command("call_tool", client, loop_fn), do: call_tool(client, loop_fn)
  def process_command("list_prompts", client, loop_fn), do: list_prompts(client, loop_fn)
  def process_command("get_prompt", client, loop_fn), do: get_prompt(client, loop_fn)

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

  defp unknown_command(command, loop_fn) do
    IO.puts("#{UI.colors().error}Unknown command: #{command}#{UI.colors().reset}")
    IO.puts("Type #{UI.colors().command}help#{UI.colors().reset} for available commands")
    loop_fn.()
  end
end
