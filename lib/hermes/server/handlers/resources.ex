defmodule Hermes.Server.Handlers.Resources do
  @moduledoc false

  alias Hermes.MCP.Error
  alias Hermes.Server.Component.Resource
  alias Hermes.Server.Frame
  alias Hermes.Server.Response

  @doc """
  Handles the resources/list request with optional pagination.

  ## Parameters

  - `request` - The MCP request containing optional cursor in params
  - `frame` - The server frame
  - `server_module` - The server module implementing resource components

  ## Returns

  - `{:reply, result, frame}` - List of resources with optional nextCursor
  - `{:error, error, frame}` - If pagination cursor is invalid
  """
  @spec handle_list(Frame.t(), module()) ::
          {:reply, map(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def handle_list(frame, server_module) do
    resources = server_module.__components__(:resource) ++ Frame.get_resources(frame)
    {:reply, %{"resources" => resources}, frame}
  end

  @doc """
  Handles the resources/read request to read content from one or more resources.

  Supports both single URI and multiple URIs formats:
  - Single: `%{"uri" => "file:///example.txt"}`
  - Multiple: `%{"uris" => ["file:///a.txt", "file:///b.txt"]}`

  ## Parameters

  - `request` - The MCP request containing URI(s) to read
  - `frame` - The server frame
  - `server_module` - The server module implementing resource components

  ## Returns

  - `{:reply, result, frame}` - Resource contents wrapped in "contents" array
  - `{:error, error, frame}` - If resource not found or read fails
  """
  @spec handle_read(map(), Frame.t(), module()) ::
          {:reply, map(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def handle_read(%{"params" => %{"uri" => uri}}, frame, server) when is_binary(uri) do
    resources = server.__components__(:resource) ++ Frame.get_resources(frame)

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

  defp read_single_resource(
         server,
         %Resource{handler: nil, uri: uri, mime_type: mime_type},
         frame
       ) do
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

  defp read_single_resource(
         _server,
         %Resource{handler: handler, uri: uri, mime_type: mime_type},
         frame
       ) do
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
