defmodule Hermes.Server.Handlers.Tools do
  @moduledoc false

  alias Hermes.MCP.Error
  alias Hermes.Server.Component
  alias Hermes.Server.Component.Schema
  alias Hermes.Server.Frame
  alias Hermes.Server.Response

  @doc """
  Handles the tools/list request with optional pagination.

  ## Parameters

  - `request` - The MCP request containing optional cursor in params
  - `frame` - The server frame
  - `server_module` - The server module implementing tool components

  ## Returns

  - `{:reply, result, frame}` - List of tools with optional nextCursor
  - `{:error, error, frame}` - If pagination cursor is invalid
  """
  @spec handle_list(Frame.t(), module()) ::
          {:reply, map(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def handle_list(frame, server_module) do
    tools = server_module.__components__(:tool)
    protocol_version = Frame.get_protocol_version(frame) || "2024-11-05"
    response = %{"tools" => Enum.map(tools, &parse_tool_definition(&1, protocol_version))}

    {:reply, response, frame}
  end

  @doc """
  Handles the tools/call request to execute a specific tool.

  ## Parameters

  - `request` - The MCP request containing tool name and arguments
  - `frame` - The server frame
  - `server_module` - The server module implementing tool components

  ## Returns

  - `{:reply, result, frame}` - Tool execution result
  - `{:error, error, frame}` - If tool not found or execution fails
  """
  @spec handle_call(map(), Frame.t(), module()) ::
          {:reply, map(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def handle_call(%{"params" => %{"name" => tool_name, "arguments" => params}}, frame, server_module) do
    registered_tools = server_module.__components__(:tool)

    if tool = find_tool_module(registered_tools, tool_name) do
      with {:ok, params} <- validate_params(params, tool, frame), do: forward_to(tool, params, frame)
    else
      payload = %{message: "Tool not found: #{tool_name}"}
      {:error, Error.protocol(:invalid_params, payload), frame}
    end
  end

  # Private functions

  defp find_tool_module(tools, name) do
    Enum.find_value(tools, fn
      {^name, module} -> module
      _ -> nil
    end)
  end

  defp parse_tool_definition({name, module}, protocol_version) do
    base = %{
      "name" => name,
      "description" => Component.get_description(module),
      "inputSchema" => module.input_schema()
    }

    if Hermes.Protocol.supports_feature?(protocol_version, :tool_annotations) and
         Code.ensure_loaded?(module) and function_exported?(module, :annotations, 0) do
      Map.put(base, "annotations", module.annotations())
    else
      base
    end
  end

  defp validate_params(params, module, frame) do
    with {:error, errors} <- module.mcp_schema(params) do
      message = Schema.format_errors(errors)
      {:error, Error.protocol(:invalid_params, %{message: message}), frame}
    end
  end

  defp forward_to(module, params, frame) do
    case module.execute(params, frame) do
      {:reply, %Response{} = response, frame} ->
        {:reply, Response.to_protocol(response), frame}

      {:noreply, frame} ->
        {:reply, %{"content" => [], "isError" => false}, frame}

      {:error, %Error{} = error, frame} ->
        {:error, error, frame}
    end
  end
end
