defmodule Mix.Tasks.Sse.Interactive do
  @moduledoc """
  Mix task to test the SSE transport implementation, interactively sending commands.
  """

  use Mix.Task

  alias Hermes.Client
  alias Hermes.Transport.SSE

  alias Mix.Tasks.Stdio

  require Logger

  @shortdoc "Test the SSE transport implementation interactively."

  @switches [
    server_url: :string
  ]

  def run(args) do
    Mix.Task.run("app.start")

    {parsed, _} = OptionParser.parse!(args, strict: @switches)
    server_url = parsed[:server_url] || "http://localhost:8000"

    Logger.info("Starting SSE interaction MCP server on #{server_url}")

    {:ok, sse} =
      SSE.start_link(
        server_url: server_url,
        client: :sse_test
      )

    Logger.info("SSE transport started on PID #{inspect(sse)}")

    {:ok, client} =
      Client.start_link(
        name: :sse_test,
        transport: SSE,
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

    Logger.info("Client started on PID #{inspect(client)}")

    # yeah, i know...
    Stdio.Interactive.loop(client)
  end
end
