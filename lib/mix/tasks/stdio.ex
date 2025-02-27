defmodule Mix.Tasks.Stdio do
  @moduledoc """
  Mix task to test the STDIO transport implementation.
  """

  use Mix.Task

  alias Hermes.Client
  alias Hermes.Transport.STDIO

  require Logger

  @shortdoc "Test the STDIO transport implementation."

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

    Logger.info("STDIO transport started on #{inspect(stdio)}")

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

    Logger.info("Client started on #{inspect(client)}")

    Process.sleep(1_000)

    Logger.info("Listing server tools")

    with {:ok, %{"tools" => tools}} <- Client.list_tools(client) do
      Logger.info("Found #{length(tools)} tools")
    end

    Process.sleep(1_000)

    Logger.info("Listing server prompts")

    with {:ok, %{"prompts" => prompts}} <- Client.list_prompts(client) do
      Logger.info("Found #{length(prompts)} prompts")
    end

    Process.sleep(1_000)

    Logger.info("Listing server resources")

    with {:ok, %{"resources" => resources}} <- Client.list_resources(client) do
      Logger.info("Found #{length(resources)} resources")
    end

    Process.sleep(1_000)

    Logger.info("Sending ping request")
    Client.ping(client) |> then(&Logger.info("Ping response: #{inspect(&1)}"))

    Process.sleep(1_000)

    Logger.info("Calling server echo_tool")

    with {:ok, result} <- Client.call_tool(client, "echo_tool", %{"message" => "Hello, world!"}) do
      Logger.info("Server echo_tool returned: #{inspect(result)}")
    end

    Process.sleep(1_000)

    Logger.info("Calling non existant tools")
    with {:error, _} <- Client.call_tool(client, "non_existant_tool", %{}), do: nil

    Process.sleep(1_000)

    Logger.info("Calling server echo_prompt")

    with {:ok, result} <-
           Client.get_prompt(client, "echo_prompt", %{"message" => "Hello, world!"}) do
      Logger.info("Server echo_prompt returned: #{inspect(result)}")
    end

    Process.sleep(1_000)

    Logger.info("Calling non existant prompt")
    with {:error, _} <- Client.get_prompt(client, "non_existant_prompt", %{}), do: nil

    Process.sleep(1_000)

    Logger.info("Reading server resource from URI")

    with {:ok, resource} <- Client.read_resource(client, "echo://hello") do
      Logger.info("Server resource echo_resource: #{inspect(resource)}")
    end

    Process.sleep(1_000)

    Logger.info("Reading non existant resource")
    with {:error, _} <- Client.read_resource(client, "non_existant_resource"), do: nil

    Client.close(client)
  end
end
