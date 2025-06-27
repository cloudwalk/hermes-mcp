defmodule Hermes.Server.Handlers.Tools do
  @moduledoc false

  alias Hermes.MCP.Error
  alias Hermes.Server.Component.Schema
  alias Hermes.Server.Component.Tool
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
    tools = server_module.__components__(:tool) ++ Frame.get_tools(frame)
    {:reply, %{"tools" => tools}, frame}
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
  def handle_call(%{"params" => %{"name" => tool_name, "arguments" => params}}, frame, server) do
    registered_tools = server.__components__(:tool) ++ Frame.get_tools(frame)

    if tool = find_tool_module(registered_tools, tool_name) do
      with {:ok, params} <- validate_params(params, tool, frame), do: forward_to(server, tool, params, frame)
    else
      payload = %{message: "Tool not found: #{tool_name}"}
      {:error, Error.protocol(:invalid_params, payload), frame}
    end
  end

  # Private functions

  defp find_tool_module(tools, name), do: Enum.find(tools, &(&1.name == name))

  defp validate_params(params, %Tool{} = tool, frame) do
    with {:error, errors} <- tool.validate_input.(params) do
      message = Schema.format_errors(errors)
      {:error, Error.protocol(:invalid_params, %{message: message}), frame}
    end
  end

  defp forward_to(server, %Tool{handler: nil} = tool, params, frame) do
    case server.handle_tool(tool.name, params, frame) do
      {:reply, %Response{} = response, frame} ->
        {:reply, Response.to_protocol(response), frame}

      {:noreply, frame} ->
        {:reply, %{"content" => [], "isError" => false}, frame}

      {:error, %Error{} = error, frame} ->
        {:error, error, frame}
    end
  end

  defp forward_to(_server, %Tool{handler: handler}, params, frame) do
    case handler.execute(params, frame) do
      {:reply, %Response{} = response, frame} ->
        {:reply, Response.to_protocol(response), frame}

      {:noreply, frame} ->
        {:reply, %{"content" => [], "isError" => false}, frame}

      {:error, %Error{} = error, frame} ->
        {:error, error, frame}
    end
  end
end
