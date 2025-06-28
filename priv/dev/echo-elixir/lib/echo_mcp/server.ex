defmodule EchoMCP.Server do
  @moduledoc false

  use Hermes.Server, capabilities: [:tools]

  alias Hermes.Server.Response

  require Logger

  @impl true
  def server_info do
    %{"name" => "echo server", "version" => Echo.version()}
  end

  @impl true
  def init(client_info, frame) do
    Logger.debug("[#{__MODULE__}] => Initialized MCP connection with #{inspect(client_info)}")

    {:ok,
     frame
     |> assign(counter: 0)
     |> register_tool("echo",
       input_schema: %{
         text: {:required, :string, max: 150, description: "the text to be echoed"}
       },
       annotations: %{read_only: true},
       description: "echoes the given text back to the LLM"
     )}
  end

  @impl true
  def handle_tool_call("echo", %{text: text}, frame) do
    Logger.info("[#{__MODULE__}] => echo tool was called #{frame.assigns.counter + 1}")
    resp = Response.text(Response.tool(), text)
    {:reply, resp, assign(frame, counter: frame.assigns.counter + 1)}
  end
end
