defmodule EchoMCP.Tools.Echo do
  @moduledoc """
  Use this tool to repeat
  """

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:text, {:required, :string}, description: "The text string to be echoed")
  end

  @impl true
  def execute(%{text: text}, frame) do
    dbg(frame)
    {:reply, Response.text(Response.tool(), text), frame}
  end
end
