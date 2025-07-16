defmodule StubServer do
  @moduledoc """
  Minimal test server that implements only the required callbacks.

  Used for testing low-level server functionality (Base server tests).
  This server has no components and provides only the bare minimum implementation.
  """

  use Hermes.Server,
    name: "Test Server",
    version: "1.0.0",
    capabilities: [:tools, :prompts, :resources]

  import Hermes.Server.Frame, only: [assign: 3]

  alias Hermes.MCP.Error
  alias Hermes.Server.Response

  @tools [
    %{
      "name" => "greet",
      "description" => "greets someone",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "for whom to greet"}
        },
        "required" => ["name"]
      }
    }
  ]

  @resources [
    %{
      "uri" => "config://test",
      "description" => "config test",
      "name" => "config.test",
      "mimeType" => "text/plain"
    }
  ]

  @prompts [
    %{
      "name" => "beauty",
      "description" => "asks the llm to say if you're beautiful or not",
      "arguments" => [
        %{
          "name" => "who",
          "description" => "who to judge beauty",
          "required" => false
        }
      ]
    }
  ]

  @impl true
  def handle_request(%{"method" => "ping"}, frame) do
    {:reply, %{}, frame}
  end

  def handle_request(%{"method" => "tools/" <> action, "params" => params}, frame) do
    case action do
      "list" -> {:reply, %{"tools" => @tools}, frame}
      "call" -> handle_tool_call(params, frame)
    end
  end

  def handle_request(%{"method" => "prompts/" <> action, "params" => params}, frame) do
    case action do
      "list" -> {:reply, %{"prompts" => @prompts}, frame}
      "get" -> handle_prompt_get(params, frame)
    end
  end

  def handle_request(%{"method" => "resources/" <> action, "params" => params}, frame) do
    case action do
      "list" -> {:reply, %{"resources" => @resources}, frame}
      "read" -> handle_read_resource(params, frame)
    end
  end

  def handle_request(%{"method" => _}, frame) do
    {:error, Error.protocol(:method_not_found), frame}
  end

  @impl true
  def handle_notification(_notification, frame) do
    {:noreply, frame}
  end

  @impl true
  def handle_sampling(response, request_id, frame) do
    frame = assign(frame, :last_sampling_response, response)
    frame = assign(frame, :last_sampling_request_id, request_id)
    {:noreply, frame}
  end

  defp handle_tool_call(%{"arguments" => %{"name" => name}, "name" => "greet"}, frame) do
    Response.tool()
    |> Response.text("Hello #{name}!")
    |> Response.to_protocol()
    |> then(&{:reply, &1, frame})
  end

  defp handle_tool_call(%{"name" => name}, frame) do
    {:error, Error.protocol(:invalid_request, %{message: "tool #{name} not found"}), frame}
  end

  defp handle_read_resource(%{"uri" => uri}, frame) do
    Response.resource()
    |> Response.text("some teste config")
    |> Response.to_protocol(uri, "text/plain")
    |> then(&%{"contents" => [&1]})
    |> then(&{:reply, &1, frame})
  end

  defp handle_prompt_get(%{"arguments" => %{"who" => who}}, frame) do
    Response.prompt()
    |> Response.user_message("says that #{who} is beuatiful")
    |> Response.to_protocol()
    |> then(&{:reply, &1, frame})
  end
end
