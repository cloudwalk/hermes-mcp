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
    case request["method"] do
      "tools/list" ->
        {:reply, %{"tools" => []}, state}

      "ping" ->
        {:reply, %{}, state}

      "tools/call" ->
        handle_tools_call(request, state)

      "resources/list" ->
        {:reply, %{"resources" => []}, state}

      "resources/read" ->
        params = request["params"] || %{}
        {:error, Error.invalid_params(%{param: "uri", message: "Resource not found: #{params["uri"]}"}), state}

      "prompts/list" ->
        {:reply, %{"prompts" => []}, state}

      "prompts/get" ->
        params = request["params"] || %{}
        {:error, Error.invalid_params(%{param: "name", message: "Prompt not found: #{params["name"]}"}), state}

      _ ->
        {:error, Error.method_not_found(%{method: request["method"]}), state}
    end
  end

  defp handle_tools_call(request, state) do
    params = request["params"] || %{}

    case Map.get(params, "name") do
      nil ->
        {:error, Error.invalid_params(%{param: "name", message: "name parameter is required"}), state}

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
