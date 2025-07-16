defmodule Hermes.Server.Handlers.Prompts do
  @moduledoc false

  alias Hermes.MCP.Error
  alias Hermes.Server.Component.Prompt
  alias Hermes.Server.Component.Schema
  alias Hermes.Server.Frame
  alias Hermes.Server.Handlers
  alias Hermes.Server.Response

  @spec handle_list(map, Frame.t(), module()) ::
          {:reply, map(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def handle_list(request, frame, server_module) do
    prompts = Handlers.get_server_prompts(server_module, frame)
    limit = frame.private[:pagination_limit]
    {prompts, cursor} = Handlers.maybe_paginate(request, prompts, limit)

    {:reply,
     then(
       %{"prompts" => prompts},
       &if(cursor, do: Map.put(&1, "nextCursor", cursor), else: &1)
     ), frame}
  end

  @spec handle_get(map(), Frame.t(), module()) ::
          {:reply, map(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def handle_get(%{"params" => %{"name" => prompt_name, "arguments" => params}}, frame, server) do
    registered_prompts = Handlers.get_server_prompts(server, frame)

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
