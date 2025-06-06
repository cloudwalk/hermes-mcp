defmodule TestServer do
  @moduledoc """
  Test implementation of the Server.Behaviour for testing.
  """

  use Hermes.Server, name: "Test Server", version: "1.0.0", capabilities: [:tools]

  alias Hermes.MCP.Error
  alias Hermes.Server.Frame

  def start_link(opts) do
    Hermes.Server.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok, %Frame{} = frame) do
    {:ok, frame}
  end

  @impl true
  def handle_request(request, frame) do
    method = request["method"]
    handle_method(method, request, frame)
  end

  defp handle_method("tools/list", _request, frame), do: {:reply, %{"tools" => []}, frame}
  defp handle_method("ping", _request, frame), do: {:reply, %{}, frame}
  defp handle_method("tools/call", request, frame), do: handle_tools_call(request, frame)
  defp handle_method("resources/list", _request, frame), do: {:reply, %{"resources" => []}, frame}
  defp handle_method("prompts/list", _request, frame), do: {:reply, %{"prompts" => []}, frame}

  defp handle_method("resources/read", request, frame) do
    params = request["params"] || %{}
    {:error, Error.invalid_params(%{param: "uri", message: "Resource not found: #{params["uri"]}"}), frame}
  end

  defp handle_method("prompts/get", request, frame) do
    params = request["params"] || %{}
    {:error, Error.invalid_params(%{param: "name", message: "Prompt not found: #{params["name"]}"}), frame}
  end

  defp handle_method(method, _request, frame) do
    {:error, Error.method_not_found(%{method: method}), frame}
  end

  defp handle_tools_call(request, frame) do
    params = request["params"] || %{}

    case Map.get(params, "name") do
      nil ->
        {:error, Error.invalid_params(%{param: "name", message: "name parameter is required"}), frame}

      name ->
        {:reply,
         %{
           "content" => [%{"type" => "text", "text" => "Tool '#{name}' executed successfully"}],
           "isError" => false
         }, frame}
    end
  end

  @impl true
  def handle_notification(notification, frame) do
    case notification["method"] do
      "notifications/cancelled" -> {:noreply, Map.put(frame, :notification_received, true)}
      "notifications/initialized" -> {:noreply, Map.put(frame, :initialized_notification_received, true)}
      _ -> {:noreply, frame}
    end
  end
end
