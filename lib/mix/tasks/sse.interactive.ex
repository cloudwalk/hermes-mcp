defmodule Mix.Tasks.Sse.Interactive do
  @shortdoc "Test the SSE transport implementation interactively."

  @moduledoc """
  Mix task to test the SSE transport implementation, interactively sending commands.
  """

  use Mix.Task

  alias Hermes.Client
  alias Hermes.Transport.SSE
  alias Mix.Tasks.Stdio

  require Logger

  @switches [
    base_url: :string,
    base_path: :string,
    sse_path: :string
  ]

  def run(args) do
    Mix.Task.run("app.start")

    {parsed, _} = OptionParser.parse!(args, strict: @switches)
    server_options = Keyword.put_new(parsed, :base_url, "http://localhost:8000")
    server_url = Path.join(server_options[:base_url], server_options[:base_path] || "")

    Logger.info("Starting SSE interaction MCP server on #{server_url}")

    {:ok, sse} =
      SSE.start_link(
        client: :sse_test,
        server: server_options
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
