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
    invocation =
      Handlers.safe_invoke({:resource, uri}, fn ->
        server.handle_resource_read(uri, frame)
      end)

    handle_resource_invocation(invocation, uri, mime_type, frame)
  end

  defp read_single_resource(_server, %Resource{handler: handler, uri: uri, mime_type: mime_type}, frame) do
    invocation =
      Handlers.safe_invoke({:resource, uri}, fn ->
        handler.read(%{"uri" => uri}, frame)
      end)

    handle_resource_invocation(invocation, uri, mime_type, frame)
  end

  defp handle_resource_invocation({:ok, {:reply, %Response{} = response, frame}}, uri, mime_type, _frame) do
    content = Response.to_protocol(response, uri, mime_type)
    {:reply, %{"contents" => [content]}, frame}
  end

  defp handle_resource_invocation({:ok, {:noreply, frame}}, uri, mime_type, _frame) do
    content = %{"uri" => uri, "mimeType" => mime_type, "text" => ""}
    {:reply, %{"contents" => [content]}, frame}
  end

  defp handle_resource_invocation({:ok, {:error, %Error{} = error, frame}}, _uri, _mime_type, _frame),
    do: {:error, error, frame}

  defp handle_resource_invocation({:caught, _kind, _reason, _stack}, uri, _mime_type, frame) do
    # See note in tools.ex — full reason already logged by safe_invoke,
    # don't leak it across the JSON-RPC boundary.
    {:error, Error.execution("Resource read failed", %{uri: uri}), frame}
  end
end
