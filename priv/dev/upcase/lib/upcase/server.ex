defmodule Upcase.Server do
  @moduledoc """
  A simple MCP server that upcases input text.
  """

  use Hermes.Server

  require Logger

  @impl true
  def server_info do
    %{"name" => "Upcase MCP Server", "version" => "1.0.0"}
  end

  @impl true
  def server_capabilities do
    %{"tools" => %{}}
  end

  @impl true
  def supported_protocol_versions do
    ["2025-03-26", "2024-10-07", "2024-05-11"]
  end

  component(Upcase.Tools.Upcase)
  component(Upcase.Tools.AnalyzeText)
  component(Upcase.Prompts.TextTransform)
  component(Upcase.Resources.Examples)

  @impl true
  def init(client_info, frame) do
    Logger.info("We had the client_info: #{inspect(client_info)}")
    schedule_hello()
    {:ok, assign(frame, counter: 0) |> put_pagination_limit(1)}
  end

  @impl true
  def handle_info(:hello, frame) do
    schedule_hello()
    frame = assign(frame, counter: frame.assigns.counter + 1)
    IO.puts("HELLO FROM UPCASE (on #{inspect(self())})! COUNTING: #{frame.assigns.counter}")
    {:noreply, frame}
  end

  defp schedule_hello do
    Process.send_after(self(), :hello, 1_650)
  end
end
