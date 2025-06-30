defmodule EchoMCP.Server do
  @moduledoc false

  use Hermes.Server, capabilities: [:tools, :prompts, :resources]

  alias Hermes.Server.Response

  require Logger

  @impl true
  # we have runtime values
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
     )
     |> register_prompt("greeting",
       arguments: %{
         name: {:required, :string, description: "Person's name"},
         style: {{:enum, ["formal", "casual"]}, default: "casual", description: "Greeting style"}
       },
       description: "Generate a personalized greeting message"
     )
     |> register_tool("save_note",
       input_schema: %{
         title: {:required, :string, max: 100, description: "Note title"},
         content: {:required, :string, description: "Note content"},
         metadata:
           {:object,
            %{
              tags: {:list, :string, description: "Tags for categorization"},
              priority:
                {:enum, ["low", "medium", "high"],
                 default: "medium", description: "Note priority"}
            }, description: "Additional note metadata"}
       },
       description: "Save a note with optional metadata"
     )
     |> register_resource("file:///server/info",
       name: "server_info",
       description: "Current server status and configuration",
       mime_type: "application/json"
     )}
  end

  @impl true
  def handle_tool_call("echo", %{text: text}, frame) do
    Logger.info("[#{__MODULE__}] => echo tool was called #{frame.assigns.counter + 1}")
    resp = Response.text(Response.tool(), text)
    {:reply, resp, assign(frame, counter: frame.assigns.counter + 1)}
  end

  def handle_tool_call("save_note", params, frame) do
    Logger.info("[#{__MODULE__}] => save_note tool called with: #{inspect(params)}")

    note_summary = """
    Note saved successfully!
    Title: #{params.title}
    Priority: #{get_in(params, [:metadata, :priority]) || "medium"}
    Tags: #{inspect(get_in(params, [:metadata, :tags]) || [])}
    """

    resp = Response.text(Response.tool(), note_summary)
    {:reply, resp, frame}
  end

  @impl true
  def handle_prompt_get("greeting", %{name: name, style: style}, frame) do
    Logger.info("[#{__MODULE__}] => greeting prompt called for #{name} with style: #{style}")

    message =
      case style do
        "formal" -> "Good day, #{name}. I hope this message finds you well."
        "casual" -> "Hey #{name}! How's it going?"
        _ -> "Hello, #{name}!"
      end

    {:reply, Response.user_message(Response.prompt(), message), frame}
  end

  @impl true
  def handle_resource_read("file:///server/info", frame) do
    Logger.info("[#{__MODULE__}] => server_info resource read")

    priv_dir = List.to_string(:code.priv_dir(:echo))
    file_path = Path.join([priv_dir, "static", "server_info.json"])
    {:ok, content} = File.read!(file_path)

    {:reply, Response.blob(Response.resource(), content), frame}
  end
end
