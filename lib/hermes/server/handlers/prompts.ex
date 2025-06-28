defmodule Hermes.Server.Handlers.Prompts do
  @moduledoc false

  alias Hermes.MCP.Error
  alias Hermes.Server.Component.Prompt
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
    prompts = server_module.__components__(:prompt) ++ Frame.get_prompts(frame)
    {:reply, %{"prompts" => prompts}, frame}
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
  def handle_get(
        %{"params" => %{"name" => prompt_name, "arguments" => params}},
        frame,
        server
      ) do
    registered_prompts = server.__components__(:prompt) ++ Frame.get_prompts(frame)

    if prompt = find_prompt_module(registered_prompts, prompt_name) do
      with {:ok, params} <- validate_params(params, prompt, frame),
           do: forward_to(server, prompt, params, frame)
    else
      payload = %{message: "Prompt not found: #{prompt_name}"}
      {:error, Error.protocol(:invalid_params, payload), frame}
    end
  end

  # Private functions

  defp find_prompt_module(prompts, name), do: Enum.find(prompts, &(&1.name == name))

  defp validate_params(params, %Prompt{} = prompt, frame) do
    with {:error, errors} <- prompt.validate_input.(params) do
      message = Schema.format_errors(errors)
      {:error, Error.protocol(:invalid_params, %{message: message}), frame}
    end
  end

  defp forward_to(server, %Prompt{handler: nil} = prompt, params, frame) do
    case server.handle_prompt_get(prompt.name, params, frame) do
      {:reply, %Response{} = response, frame} ->
        {:reply, Response.to_protocol(response), frame}

      {:noreply, frame} ->
        {:reply, %{"content" => [], "isError" => false}, frame}

      {:error, %Error{} = error, frame} ->
        {:error, error, frame}
    end
  end

  defp forward_to(_server, %Prompt{handler: handler}, params, frame) do
    case handler.get_messages(params, frame) do
      {:reply, %Response{} = response, frame} ->
        {:reply, Response.to_protocol(response), frame}

      {:noreply, frame} ->
        {:reply, %{"content" => [], "isError" => false}, frame}

      {:error, %Error{} = error, frame} ->
        {:error, error, frame}
    end
  end
end
