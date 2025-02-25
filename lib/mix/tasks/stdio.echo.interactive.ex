defmodule Mix.Tasks.Stdio.Echo.Interactive do
  @moduledoc """
  Mix task to test the STDIO transport implementation, interactively sending commands.
  """

  use Mix.Task

  alias Hermes.Client
  alias Hermes.Transport.STDIO

  require Logger

  @shortdoc "Test the STDIO transport implementation interactively."

  def run(_) do
    server_path = Path.expand("priv/dev/echo/index.py")

    Logger.info("Starting STDIO interaction on #{server_path} MCP server")

    if not File.exists?(server_path) do
      Logger.error("Server path does not exist: #{server_path}")
      System.halt(1)
    end

    if not (!!System.find_executable("mcp")) do
      Logger.error("mcp executable not found in PATH, maybe you need to activate venv")
      System.halt(1)
    end

    {:ok, stdio} =
      STDIO.start_link(
        command: "mcp",
        args: ["run", server_path],
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
  defp exec(_, "exit"), do: Logger.info("Exiting interactive session")
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
    {:ok, %{"tools" => tools}} = Client.list_tools(client)
    IO.puts("Found #{length(tools)} tools")

    loop(client)
  end

  defp call_tool(client) do
    tool_name = IO.gets("Enter tool name:") |> String.trim_trailing()

    tool_args =
      IO.gets("Enter tool arguments (as JSON):") |> String.trim_trailing() |> Jason.decode!()

    {:ok, result} = Client.call_tool(client, tool_name, tool_args)
    IO.puts("Tool result: #{inspect(result)}")

    loop(client)
  end

  defp list_prompts(client) do
    {:ok, %{"prompts" => prompts}} = Client.list_prompts(client)
    IO.puts("Found #{length(prompts)} prompts")

    loop(client)
  end

  defp get_prompt(client) do
    prompt_name = IO.gets("Enter prompt name:") |> String.trim_trailing()

    prompt_args =
      IO.gets("Enter prompt arguments (as JSON):")
      |> String.trim_trailing()
      |> Jason.decode!()

    {:ok, result} = Client.get_prompt(client, prompt_name, prompt_args)
    IO.puts("Prompt result: #{inspect(result)}")

    loop(client)
  end

  defp list_resources(client) do
    {:ok, %{"resources" => resources}} = Client.list_resources(client)
    IO.puts("Found #{length(resources)} resources")

    loop(client)
  end

  defp read_resource(client) do
    resource_name = IO.gets("Enter resource name:") |> String.trim_trailing()

    {:ok, resource} = Client.read_resource(client, resource_name)
    IO.puts("Resource: #{inspect(resource)}")

    loop(client)
  end
end
