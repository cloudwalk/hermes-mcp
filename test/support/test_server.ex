defmodule TestServer do
  @moduledoc """
  Test implementation of the Server.Behaviour for testing.
  """

  @behaviour Hermes.Server.Behaviour

  alias Hermes.MCP.Error

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_request(request, state) do
    method = request["method"]
    handle_method(method, request, state)
  end

  defp handle_method("tools/list", _request, state), do: {:reply, %{"tools" => []}, state}
  defp handle_method("ping", _request, state), do: {:reply, %{}, state}
  defp handle_method("tools/call", request, state), do: handle_tools_call(request, state)
  defp handle_method("resources/list", _request, state), do: {:reply, %{"resources" => []}, state}
  defp handle_method("prompts/list", _request, state), do: {:reply, %{"prompts" => []}, state}

  defp handle_method("resources/read", request, state) do
    params = request["params"] || %{}
    {:error, Error.resource(:not_found, %{uri: params["uri"]}), state}
  end

  defp handle_method("prompts/get", request, state) do
    params = request["params"] || %{}
    {:error, Error.protocol(:invalid_params, %{param: "name", message: "Prompt not found: #{params["name"]}"}), state}
  end

  defp handle_method(method, _request, state) do
    {:error, Error.protocol(:method_not_found, %{method: method}), state}
  end

  defp handle_tools_call(request, state) do
    params = request["params"] || %{}

    case Map.get(params, "name") do
      nil ->
        {:error, Error.protocol(:invalid_params, %{param: "name", message: "name parameter is required"}), state}

      name ->
        {:reply,
         %{
           "content" => [%{"type" => "text", "text" => "Tool '#{name}' executed successfully"}],
           "isError" => false
         }, state}
    end
  end

  @impl true
  def handle_notification(notification, state) do
    case notification["method"] do
      "notifications/cancelled" -> {:noreply, Map.put(state, :notification_received, true)}
      "notifications/initialized" -> {:noreply, Map.put(state, :initialized_notification_received, true)}
      _ -> {:noreply, state}
    end
  end

  @impl true
  def server_info, do: %{"name" => "Test Server", "version" => "1.0.0"}

  @impl true
  def server_capabilities, do: %{"tools" => %{"listChanged" => true}}

  @impl true
  def supported_protocol_versions do
    ["2024-11-05", "2025-03-26"]
  end
end
