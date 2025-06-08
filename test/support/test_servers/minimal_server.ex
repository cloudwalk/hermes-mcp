defmodule TestServers.MinimalServer do
  @moduledoc """
  Minimal test server that implements only the required callbacks.

  Used for testing low-level server functionality (Base server tests).
  This server has no components and provides only the bare minimum implementation.
  """

  @behaviour Hermes.Server.Behaviour

  alias Hermes.MCP.Error

  @impl true
  def server_info do
    %{"name" => "Minimal Test Server", "version" => "1.0.0"}
  end

  @impl true
  def server_capabilities, do: %{}

  @impl true
  def supported_protocol_versions do
    ["2025-03-26", "2024-11-05"]
  end

  @impl true
  def init(:ok, frame) do
    {:ok, frame}
  end

  @impl true
  def handle_request(%{"method" => "ping"}, frame) do
    {:reply, %{}, frame}
  end

  def handle_request(%{"method" => method}, frame) do
    {:error, Error.protocol(:method_not_found, %{method: method}), frame}
  end

  @impl true
  def handle_notification(_notification, frame) do
    {:noreply, frame}
  end
end
