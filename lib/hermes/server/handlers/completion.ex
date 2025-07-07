defmodule Hermes.Server.Handlers.Completion do
  @moduledoc false

  alias Hermes.MCP.Error
  alias Hermes.Server.Frame
  alias Hermes.Server.Response

  @spec handle_complete(map(), Frame.t(), module()) ::
          {:reply, map(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def handle_complete(%{"params" => params}, frame, server) do
    %{"ref" => ref} = params
    argument = Map.get(params, "argument", %{})

    if Hermes.exported?(server, :handle_completion, 3) do
      case server.handle_completion(ref, argument, frame) do
        {:reply, %Response{type: :completion} = response, frame} ->
          result = Response.to_protocol(response)
          {:reply, %{"completion" => result}, frame}

        {:reply, %{"values" => values}, frame} when is_list(values) ->
          {:reply, %{"completion" => %{"values" => values}}, frame}

        {:reply, %{"values" => values, "total" => total, "hasMore" => has_more}, frame} ->
          result = %{
            "completion" => %{
              "values" => values,
              "total" => total,
              "hasMore" => has_more
            }
          }

          {:reply, result, frame}

        {:error, %Error{} = error, frame} ->
          {:error, error, frame}
      end
    else
      error =
        Error.protocol(:method_not_found, %{
          method: "completion/complete",
          message: "Server does not implement handle_completion/3"
        })

      {:error, error, frame}
    end
  end

  def handle_complete(%{}, frame, _server) do
    error =
      Error.protocol(:invalid_params, %{
        message: "Missing required parameter: ref"
      })

    {:error, error, frame}
  end
end
