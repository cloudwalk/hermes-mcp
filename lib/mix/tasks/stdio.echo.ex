defmodule Mix.Tasks.Stdio.Echo do
  @moduledoc """
  Mix task to test the STDIO transport implementation.
  """

  use Mix.Task

  alias Hermes.Client
  alias Hermes.Transport.STDIO

  require Logger

  @shortdoc "Test the STDIO transport implementation."

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

    Logger.info("Listing server tools")
    {:ok, %{"tools" => tools}} = Client.list_tools(client)
    Logger.info("Found #{length(tools)} tools")

    Process.sleep(1_000)

    Logger.info("Listing server prompts")
    {:ok, %{"prompts" => prompts}} = Client.list_prompts(client)
    Logger.info("Found #{length(prompts)} prompts")

    Process.sleep(1_000)

    Logger.info("Listing server resources")
    {:ok, %{"resources" => resources}} = Client.list_resources(client)
    Logger.info("Found #{length(resources)} resources")

    Process.sleep(1_000)

    Logger.info("Sending ping request")
    Client.ping(client) |> then(&Logger.info("Ping response: #{inspect(&1)}"))

    Process.sleep(1_000)

    Logger.info("Calling server echo_tool")
    {:ok, result} = Client.call_tool(client, "echo_tool", %{"message" => "Hello, world!"})
    Logger.info("Server echo_tool returned: #{inspect(result)}")

    Process.sleep(1_000)

    Logger.info("Calling non existant tools")
    {:error, _} = Client.call_tool(client, "non_existant_tool", %{})

    Process.sleep(1_000)

    Logger.info("Calling server echo_prompt")
    {:ok, result} = Client.get_prompt(client, "echo_prompt", %{"message" => "Hello, world!"})
    Logger.info("Server echo_prompt returned: #{inspect(result)}")

    Process.sleep(1_000)

    Logger.info("Calling non existant prompt")
    {:error, _} = Client.get_prompt(client, "non_existant_prompt", %{})

    Process.sleep(1_000)

    Logger.info("Reading server resource from URI")
    {:ok, resource} = Client.read_resource(client, "echo://hello")
    Logger.info("Server resource echo_resource: #{inspect(resource)}")

    Process.sleep(1_000)

    Logger.info("Reading non existant resource")
    {:error, _} = Client.read_resource(client, "non_existant_resource")

    System.halt(0)
  end
end
