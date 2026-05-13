defmodule Hermes.Server.Handlers.Tools do
  @moduledoc false

  alias Hermes.MCP.Error
  alias Hermes.Server.Component.Schema
  alias Hermes.Server.Component.Tool
  alias Hermes.Server.Frame
  alias Hermes.Server.Handlers
  alias Hermes.Server.Response

  @spec handle_list(map, Frame.t(), module()) ::
          {:reply, map(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def handle_list(request, frame, server_module) do
    tools = Handlers.get_server_tools(server_module, frame)
    limit = frame.private[:pagination_limit]
    {tools, cursor} = Handlers.maybe_paginate(request, tools, limit)

    {:reply,
     then(
       %{"tools" => tools},
       &if(cursor, do: Map.put(&1, "nextCursor", cursor), else: &1)
     ), frame}
  end

  @spec handle_call(map(), Frame.t(), module()) ::
          {:reply, map(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def handle_call(%{"params" => %{"name" => tool_name, "arguments" => params}}, frame, server) do
    registered_tools = Handlers.get_server_tools(server, frame)

    if tool = find_tool_module(registered_tools, tool_name) do
      with {:ok, params} <- validate_params(params, tool, frame),
           do: forward_to(server, tool, params, frame)
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
    invocation =
      Handlers.safe_invoke({:tool, tool.name}, fn ->
        server.handle_tool_call(tool.name, params, frame)
      end)

    handle_tool_invocation(invocation, tool, frame)
  end

  defp forward_to(_server, %Tool{handler: handler} = tool, params, frame) do
    invocation =
      Handlers.safe_invoke({:tool, tool.name}, fn ->
        handler.execute(params, frame)
      end)

    handle_tool_invocation(invocation, tool, frame)
  end

  defp handle_tool_invocation({:ok, {:reply, %Response{} = response, frame}}, tool, _frame) do
    maybe_validate_output_schema(tool, response, frame)
  end

  defp handle_tool_invocation({:ok, {:noreply, frame}}, _tool, _frame) do
    {:reply, %{"content" => [], "isError" => false}, frame}
  end

  defp handle_tool_invocation({:ok, {:error, %Error{} = error, frame}}, _tool, _frame) do
    {:error, error, frame}
  end

  defp handle_tool_invocation({:caught, _kind, _reason, _stack}, tool, frame) do
    # Full reason + stacktrace is already logged at `:error` level by
    # Handlers.safe_invoke/2. Don't echo it back to the client — exception
    # messages from user code commonly contain internal details (query
    # snippets, upstream API error text, secrets) that shouldn't leak
    # across the JSON-RPC boundary.
    {:error, Error.execution("Tool execution failed", %{tool: tool.name}), frame}
  end

  @output_schema_err "Tool doesnt conform for it output schema"

  defp maybe_validate_output_schema(%Tool{output_schema: nil}, resp, frame) do
    {:reply, Response.to_protocol(resp), frame}
  end

  defp maybe_validate_output_schema(%Tool{} = tool, %Response{structured_content: nil}, frame) do
    metadata = %{tool_name: tool.name}
    {:error, Error.execution(@output_schema_err, metadata), frame}
  end

  defp maybe_validate_output_schema(%Tool{} = tool, %Response{} = resp, frame) do
    case tool.validate_output.(resp.structured_content) do
      {:ok, _} -> {:reply, Response.to_protocol(resp), frame}
      {:error, errors} -> {:error, Error.execution(@output_schema_err, %{errors: errors}), frame}
    end
  end
end
