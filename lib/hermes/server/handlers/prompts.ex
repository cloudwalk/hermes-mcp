defmodule Hermes.Server.Handlers.Prompts do
  @moduledoc """
  Handles MCP protocol prompt-related methods.

  This module processes:
  - `prompts/list` - Lists available prompts with optional pagination
  - `prompts/get` - Retrieves and generates messages for a specific prompt

  ## Pagination Support

  The `prompts/list` method supports pagination through cursor parameters:

      # Request
      %{"method" => "prompts/list", "params" => %{"cursor" => "optional-cursor"}}
      
      # Response with more results
      %{
        "prompts" => [...],
        "nextCursor" => "next-page-cursor"
      }
      
      # Response for last page
      %{"prompts" => [...]}
  """

  alias Hermes.MCP.Error
  alias Hermes.Server.Component
  alias Hermes.Server.Component.Schema
  alias Hermes.Server.Frame
  alias Hermes.Server.Response

  @doc """
  Handles the prompts/list request with optional pagination.

  ## Parameters

  - `request` - The MCP request containing optional cursor in params
  - `frame` - The server frame
  - `server_module` - The server module implementing prompt components

  ## Returns

  - `{:reply, result, frame}` - List of prompts with optional nextCursor
  - `{:error, error, frame}` - If pagination cursor is invalid
  """
  @spec handle_list(Frame.t(), module()) ::
          {:reply, map(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def handle_list(frame, server_module) do
    prompts = server_module.__components__(:prompt)
    response = %{"prompts" => Enum.map(prompts, &parse_prompt_definition/1)}

    {:reply, response, frame}
  end

  @doc """
  Handles the prompts/get request to retrieve messages for a specific prompt.

  ## Parameters

  - `request` - The MCP request containing prompt name and arguments
  - `frame` - The server frame
  - `server_module` - The server module implementing prompt components

  ## Returns

  - `{:reply, result, frame}` - Generated messages from the prompt
  - `{:error, error, frame}` - If prompt not found or generation fails
  """
  @spec handle_get(map(), Frame.t(), module()) ::
          {:reply, map(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def handle_get(%{"params" => %{"name" => prompt_name, "arguments" => params}}, frame, server_module) do
    registered_prompts = server_module.__components__(:prompt)

    if prompt = find_prompt_module(registered_prompts, prompt_name) do
      with {:ok, params} <- validate_params(params, prompt, frame), do: forward_to(prompt, params, frame)
    else
      payload = %{message: "Prompt not found: #{prompt_name}"}
      {:error, Error.protocol(:invalid_params, payload), frame}
    end
  end

  # Private functions

  defp find_prompt_module(prompts, name) do
    Enum.find_value(prompts, fn
      {^name, module} -> module
      _ -> nil
    end)
  end

  defp parse_prompt_definition({name, module}) do
    %{
      "name" => name,
      "description" => Component.get_description(module),
      "arguments" => module.arguments()
    }
  end

  defp validate_params(params, module, frame) do
    with {:error, errors} <- module.mcp_schema(params) do
      message = Schema.format_errors(errors)
      {:error, Error.protocol(:invalid_params, %{message: message}), frame}
    end
  end

  defp forward_to(module, params, frame) do
    case module.get_messages(params, frame) do
      {:reply, %Response{} = response, frame} ->
        {:reply, Response.to_protocol(response), frame}

      {:noreply, frame} ->
        {:reply, %{"content" => [], "isError" => false}, frame}

      {:error, %Error{} = error, frame} ->
        {:error, error, frame}
    end
  end
end
