defmodule TestServers.FullServer do
  @moduledoc """
  Test server using high-level Hermes.Server with basic MCP capabilities.

  Provides empty implementations of tools, prompts, and resources for testing.
  """

  use Hermes.Server,
    name: "Full Test Server",
    version: "1.0.0",
    capabilities: [
      {:tools, list_changed: true},
      {:prompts, list_changed: true},
      {:resources, list_changed: true, subscribe: true}
    ]

  @impl true
  def init(_arg, frame) do
    {:ok, frame}
  end

  @impl true
  def handle_notification(_notification, frame) do
    {:noreply, frame}
  end
end
