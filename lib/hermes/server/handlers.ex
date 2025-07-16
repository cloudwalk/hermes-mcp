defmodule Hermes.Server.Handlers do
  @moduledoc false

  alias Hermes.MCP.Error
  alias Hermes.Server.Frame
  alias Hermes.Server.Handlers.Completion
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
      "list" -> Tools.handle_list(request, frame, module)
      "call" -> Tools.handle_call(request, frame, module)
    end
  end

  def handle(%{"method" => "prompts/" <> action} = request, module, frame) do
    case action do
      "list" -> Prompts.handle_list(request, frame, module)
      "get" -> Prompts.handle_get(request, frame, module)
    end
  end

  def handle(%{"method" => "resources/" <> action} = request, module, frame) do
    case action do
      "list" -> Resources.handle_list(request, frame, module)
      "read" -> Resources.handle_read(request, frame, module)
      "templates/list" -> Resources.handle_templates_list(request, frame, module)
    end
  end

  def handle(%{"method" => "completion/complete"} = request, module, frame) do
    Completion.handle_complete(request, frame, module)
  end

  def handle(%{"method" => method}, _module, frame) do
    {:error, Error.protocol(:method_not_found, %{method: method}), frame}
  end

  def get_server_tools(module, frame) do
    Enum.sort_by(module.__components__(:tool) ++ Frame.get_tools(frame), & &1.name)
  end

  def get_server_prompts(module, frame) do
    Enum.sort_by(module.__components__(:prompt) ++ Frame.get_prompts(frame), & &1.name)
  end

  def get_server_resources(module, frame) do
    (module.__components__(:resource) ++ Frame.get_resources(frame))
    |> Enum.reject(& &1.uri_template)
    |> Enum.sort_by(& &1.name)
  end

  def get_server_resource_templates(module, frame) do
    (module.__components__(:resource) ++ Frame.get_resources(frame))
    |> Enum.filter(& &1.uri_template)
    |> Enum.sort_by(& &1.name)
  end

  @spec maybe_paginate(map, list(struct), non_neg_integer | nil) ::
          {list(struct), cursor :: String.t() | nil}
  def maybe_paginate(_, components, nil), do: {components, nil}

  def maybe_paginate(%{"params" => %{"cursor" => cursor}}, components, limit) when limit > 0 do
    last_name = Base.decode64!(cursor, padding: false)
    {_taken, remain} = Enum.split_while(components, &(&1.name <= last_name))
    maybe_paginate(%{}, remain, limit)
  end

  def maybe_paginate(_, components, limit) when limit > 0 do
    if length(components) > limit do
      taken = Enum.take(components, limit)
      next_name = List.last(taken).name
      remain = length(components -- taken)

      {taken, if(next_name && remain > 0, do: Base.encode64(next_name, padding: false))}
    else
      {components, nil}
    end
  end
end
