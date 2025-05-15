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
      "test" ->
        {:reply, %{"result" => "test_success"}, state}

      "noreply" ->
        {:noreply, state}

      "error" ->
        {:error, %Error{code: -32_000, data: %{message: "Test error"}}, state}

      "update_state" ->
        {:reply, %{"result" => "updated"}, Map.put(state, :updated, true)}

      _ ->
        {:error, %Error{code: -32_601, data: %{message: "Method not found"}}, state}
    end
  end

  @impl true
  def handle_notification(notification, state) do
    case notification["method"] do
      "test_notification" -> {:noreply, Map.put(state, :notification_received, true)}
      _ -> {:noreply, state}
    end
  end

  @impl true
  def server_info, do: %{"name" => "Test Server", "version" => "1.0.0"}

  @impl true
  def server_capabilities, do: %{"test_capability" => true}
end
