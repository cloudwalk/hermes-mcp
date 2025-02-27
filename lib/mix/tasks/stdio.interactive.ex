defmodule Mix.Tasks.Stdio.Interactive do
  @moduledoc """
  Mix task to test the STDIO transport implementation, interactively sending commands.
  """

  use Mix.Task

  alias Hermes.Client
  alias Hermes.Transport.STDIO

  require Logger

  @shortdoc "Test the STDIO transport implementation interactively."

  @switches [
    command: :string,
    args: :string
  ]

  def run(args) do
    {parsed, _} = OptionParser.parse!(args, strict: @switches, aliases: [c: :command])
    cmd = parsed[:command] || "mcp"
    args = String.split(parsed[:args] || "run,priv/dev/echo/index.py", ",", trim: true)

    Logger.info("Starting STDIO interaction MCP server")

    if cmd == "mcp" and not (!!System.find_executable("mcp")) do
      Logger.error("mcp executable not found in PATH, maybe you need to activate venv")
      System.halt(1)
    end

    {:ok, stdio} =
      STDIO.start_link(
        command: cmd,
        args: args,
        client: :stdio_test
      )

    Logger.info("STDIO transport started on PID #{inspect(stdio)}")

    {:ok, client} =
      Client.start_link(
        name: :stdio_test,
        transport: STDIO,
        client_info: %{
          "name" => "Mix.Tasks.STDIO",
          "version" => "1.0.0"
        },
        capabilities: %{
          "roots" => %{
            "listChanged" => true
          },
          "sampling" => %{}
        }
      )

    Logger.info("Client started on PID #{inspect(client)}")

    Process.sleep(1_000)

    Logger.info("Type 'help' for a list of commands")

    loop(client)
  end

  defp loop(client) do
    exec(client, IO.gets(">>> ") |> String.trim_trailing())
  end

  defp exec(client, "help"), do: print_help(client)
  defp exec(client, "list_tools"), do: list_tools(client)
  defp exec(client, "call_tool"), do: call_tool(client)
  defp exec(client, "list_prompts"), do: list_prompts(client)
  defp exec(client, "get_prompt"), do: get_prompt(client)
  defp exec(client, "list_resources"), do: list_resources(client)
  defp exec(client, "read_resource"), do: read_resource(client)

  defp exec(client, "exit") do
    Logger.info("Exiting interactive session")
    Client.close(client)
  end

  defp exec(client, _), do: loop(client)

  defp print_help(client) do
    IO.puts("Available commands:")
    IO.puts("  help - show this help message")
    IO.puts("  list_tools - list server tools")
    IO.puts("  call_tool - call a server tool with arguments")
    IO.puts("  list_prompts - list server prompts")
    IO.puts("  get_prompt - get a server prompt")
    IO.puts("  list_resources - list server resources")
    IO.puts("  read_resource - read a server resource")
    IO.puts("  exit - exit the interactive session")

    loop(client)
  end

  defp list_tools(client) do
    with {:ok, %{"tools" => tools}} <- Client.list_tools(client) do
      Logger.info("Found #{length(tools)} tools")
    end

    loop(client)
  end

  defp call_tool(client) do
    tool_name = IO.gets("Enter tool name:") |> String.trim_trailing()

    tool_args =
      IO.gets("Enter tool arguments (as JSON):") |> String.trim_trailing() |> Jason.decode!()

    with {:ok, result} <- Client.call_tool(client, tool_name, tool_args) do
      Logger.info("Tool result: #{inspect(result)}")
    end

    loop(client)
  end

  defp list_prompts(client) do
    with {:ok, %{"prompts" => prompts}} <- Client.list_prompts(client) do
      Logger.info("Found #{length(prompts)} prompts")
    end

    loop(client)
  end

  defp get_prompt(client) do
    prompt_name = IO.gets("Enter prompt name:") |> String.trim_trailing()

    prompt_args =
      IO.gets("Enter prompt arguments (as JSON):")
      |> String.trim_trailing()
      |> Jason.decode!()

    with {:ok, result} <- Client.get_prompt(client, prompt_name, prompt_args) do
      Logger.info("Prompt result: #{inspect(result)}")
    end

    loop(client)
  end

  defp list_resources(client) do
    with {:ok, %{"resources" => resources}} <- Client.list_resources(client) do
      Logger.info("Found #{length(resources)} resources")
    end

    loop(client)
  end

  defp read_resource(client) do
    resource_name = IO.gets("Enter resource name:") |> String.trim_trailing()

    with {:ok, resource} <- Client.read_resource(client, resource_name) do
      Logger.info("Resource: #{inspect(resource)}")
    end

    loop(client)
  end
end
