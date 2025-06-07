defmodule Upcase.Server do
  @moduledoc """
  A simple MCP server that upcases input text.
  """

  use Hermes.Server,
    name: "Upcase MCP Server",
    version: "1.0.0",
    capabilities: [:tools, :prompts, :resources]

  def start_link(opts \\ []) do
    Hermes.Server.start_link(__MODULE__, :ok, opts)
  end

  component(Upcase.Tools.Upcase)
  component(Upcase.Prompts.TextTransform)
  component(Upcase.Resources.Examples)

  @impl true
  def init(:ok, frame) do
    {:ok, frame}
  end

  @impl true
  def handle_notification(_notification, state) do
    {:noreply, state}
  end
end
