defmodule EchoMCP.Server do
  @moduledoc false

  use Hermes.Server, name: "Echo Server", version: Echo.version(), capabilities: [:tools]

  def start_link(opts) do
    Hermes.Server.start_link(__MODULE__, :ok, opts)
  end

  component(EchoMCP.Tools.Echo)

  @impl true
  def init(:ok, frame) do
    {:ok, frame}
  end

  @impl true
  def handle_notification(_, frame) do
    {:noreply, frame}
  end
end
