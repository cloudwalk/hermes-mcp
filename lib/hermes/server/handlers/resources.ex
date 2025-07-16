defmodule Hermes.Server.Handlers.Resources do
  @moduledoc false

  alias Hermes.MCP.Error
  alias Hermes.Server.Component.Resource
  alias Hermes.Server.Frame
  alias Hermes.Server.Handlers
  alias Hermes.Server.Response

  @spec handle_list(map, Frame.t(), module()) ::
          {:reply, map(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def handle_list(request, frame, server_module) do
    resources = Handlers.get_server_resources(server_module, frame)
    limit = frame.private[:pagination_limit]
    {resources, cursor} = Handlers.maybe_paginate(request, resources, limit)

    {:reply,
     then(
       %{"resources" => resources},
       &if(cursor, do: Map.put(&1, "nextCursor", cursor), else: &1)
     ), frame}
  end

  @spec handle_templates_list(map, Frame.t(), module()) ::
          {:reply, map(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def handle_templates_list(request, frame, server_module) do
    templates = Handlers.get_server_resource_templates(server_module, frame)
    limit = frame.private[:pagination_limit]
    {templates, cursor} = Handlers.maybe_paginate(request, templates, limit)

    {:reply,
     then(
       %{"resourceTemplates" => templates},
       &if(cursor, do: Map.put(&1, "nextCursor", cursor), else: &1)
     ), frame}
  end

  @spec handle_read(map(), Frame.t(), module()) ::
          {:reply, map(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def handle_read(%{"params" => %{"uri" => uri}}, frame, server) when is_binary(uri) do
    resources = Handlers.get_server_resources(server, frame)

    if resource = find_resource_module(resources, uri) do
      read_single_resource(server, resource, frame)
    else
      payload = %{message: "Resource not found: #{uri}"}
      error = Error.resource(:not_found, payload)
      {:error, error, frame}
    end
  end

  # Private functions

  defp find_resource_module(resources, uri), do: Enum.find(resources, &(&1.uri == uri))

  defp read_single_resource(server, %Resource{handler: nil, uri: uri, mime_type: mime_type}, frame) do
    case server.handle_resource_read(uri, frame) do
      {:reply, %Response{} = response, frame} ->
        content = Response.to_protocol(response, uri, mime_type)
        {:reply, %{"contents" => [content]}, frame}

      {:noreply, frame} ->
        content = %{"uri" => uri, "mimeType" => mime_type, "text" => ""}
        {:reply, %{"contents" => [content]}, frame}

      {:error, %Error{} = error, frame} ->
        {:error, error, frame}
    end
  end

  defp read_single_resource(_server, %Resource{handler: handler, uri: uri, mime_type: mime_type}, frame) do
    case handler.read(%{"uri" => uri}, frame) do
      {:reply, %Response{} = response, frame} ->
        content = Response.to_protocol(response, uri, mime_type)
        {:reply, %{"contents" => [content]}, frame}

      {:noreply, frame} ->
        content = %{"uri" => uri, "mimeType" => mime_type, "text" => ""}
        {:reply, %{"contents" => [content]}, frame}

      {:error, %Error{} = error, frame} ->
        {:error, error, frame}
    end
  end
end
