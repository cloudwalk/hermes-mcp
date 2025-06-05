defmodule Upcase.Server do
  @moduledoc """
  A simple MCP server that upcases input text.
  """

  use Hermes.Server, name: "Upcase MCP Server", version: "1.0.0", capabilities: [:tools]

  alias Hermes.MCP.Error

  def start_link(opts \\ []) do
    Hermes.Server.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok, frame) do
    {:ok, frame}
  end

  @impl true
  def handle_request(%{"method" => "tools/list"} = _request, state) do
    response = %{
      "tools" => [
        %{
          "name" => "upcase",
          "description" => "Converts text to uppercase",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "text" => %{
                "type" => "string",
                "description" => "The text to convert to uppercase"
              }
            },
            "required" => ["text"]
          }
        }
      ]
    }

    {:reply, response, state}
  end

  @impl true
  def handle_request(
        %{"method" => "tools/call", "params" => %{"name" => "upcase", "arguments" => args}} =
          _request,
        state
      ) do
    case Map.get(args, "text") do
      nil ->
        {:error, Error.invalid_params(%{message: "Missing required parameter: text"}), state}

      text when is_binary(text) ->
        upcased_text = String.upcase(text)

        response = %{
          "content" => [
            %{
              "type" => "text",
              "text" => upcased_text
            }
          ],
          "isError" => false
        }

        {:reply, response, state}

      _ ->
        {:error, Error.invalid_params(%{message: "Parameter 'text' must be a string"}), state}
    end
  end

  @impl true
  def handle_request(request, state) do
    {:error, Error.method_not_found(%{method: request["method"]}), state}
  end

  @impl true
  def handle_notification(_notification, state) do
    {:noreply, state}
  end
end
