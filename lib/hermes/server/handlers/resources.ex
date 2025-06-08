defmodule Hermes.Server.Handlers.Resources do
  @moduledoc """
  Handles MCP protocol resource-related methods.

  This module processes:
  - `resources/list` - Lists available resources with optional pagination
  - `resources/read` - Reads content from one or more resources

  ## Pagination Support

  The `resources/list` method supports pagination through cursor parameters:

      # Request
      %{"method" => "resources/list", "params" => %{"cursor" => "optional-cursor"}}
      
      # Response with more results
      %{
        "resources" => [...],
        "nextCursor" => "next-page-cursor"
      }
      
      # Response for last page
      %{"resources" => [...]}

  ## Resource Reading

  The `resources/read` method supports reading multiple resources at once:

      # Single resource
      %{"method" => "resources/read", "params" => %{"uri" => "file:///example.txt"}}
      
      # Multiple resources  
      %{"method" => "resources/read", "params" => %{"uris" => ["file:///a.txt", "file:///b.txt"]}}
      
      # Response (always wrapped in contents array)
      %{
        "contents" => [
          %{
            "uri" => "file:///example.txt",
            "mimeType" => "text/plain", 
            "text" => "content"
          }
        ]
      }
  """

  alias Hermes.MCP.Error
  alias Hermes.Server.Component
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
    resources = server_module.__components__(:resource)
    response = %{"resources" => Enum.map(resources, &parse_resource_definition/1)}

    {:reply, response, frame}
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
  def handle_read(%{"params" => %{"uri" => uri}}, frame, server_module) when is_binary(uri) do
    resources = server_module.__components__(:resource)

    if resource = find_resource_module(resources, uri) do
      read_single_resource(resource, uri, frame)
    else
      payload = %{message: "Resource not found: #{uri}"}
      error = Error.resource(:not_found, payload)
      {:error, error, frame}
    end
  end

  # Private functions

  defp find_resource_module(resources, uri) do
    Enum.find_value(resources, fn {_name, module} ->
      if module.uri() == uri, do: module
    end)
  end

  defp parse_resource_definition({_name, module}) do
    %{
      "uri" => module.uri(),
      "name" => Component.get_description(module),
      "mimeType" => module.mime_type()
    }
  end

  defp read_single_resource(module, uri, frame) do
    case module.read(%{"uri" => uri}, frame) do
      {:reply, %Response{} = response, frame} ->
        content = Response.to_protocol(response, uri, module.mime_type())
        {:reply, %{"contents" => [content]}, frame}

      {:noreply, frame} ->
        content = %{"uri" => uri, "mimeType" => module.mime_type(), "text" => ""}
        {:reply, %{"contents" => [content]}, frame}

      {:error, %Error{} = error, frame} ->
        {:error, error, frame}
    end
  end
end
