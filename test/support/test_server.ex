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
      "tools/list" -> {:reply, "test_success", state}
      "ping" -> {:reply, %{}, state}
      _ -> {:error, Error.method_not_found(%{method: request["method"]}), state}
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
end
