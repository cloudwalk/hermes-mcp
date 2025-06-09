defmodule Hermes.Server.Handlers do
  @moduledoc false

  alias Hermes.MCP.Error
  alias Hermes.Server.Frame
  alias Hermes.Server.Handlers.Prompts
  alias Hermes.Server.Handlers.Resources
  alias Hermes.Server.Handlers.Tools
  alias Hermes.Server.Response

  @spec handle(map, module, Frame.t()) ::
          {:reply, response :: Response.t(), new_state :: Frame.t()}
          | {:noreply, new_state :: Frame.t()}
          | {:error, error :: Error.t(), new_state :: Frame.t()}
  def handle(%{"method" => "tools/" <> action} = request, module, frame) do
    case action do
      "list" -> Tools.handle_list(frame, module)
      "call" -> Tools.handle_call(request, frame, module)
    end
  end

  def handle(%{"method" => "prompts/" <> action} = request, module, frame) do
    case action do
      "list" -> Prompts.handle_list(frame, module)
      "get" -> Prompts.handle_get(request, frame, module)
    end
  end

  def handle(%{"method" => "resources/" <> action} = request, module, frame) do
    case action do
      "list" -> Resources.handle_list(frame, module)
      "read" -> Resources.handle_read(request, frame, module)
    end
  end

  def handle(%{"method" => method}, _module, frame) do
    {:error, Error.protocol(:method_not_found, %{method: method}), frame}
  end
end
