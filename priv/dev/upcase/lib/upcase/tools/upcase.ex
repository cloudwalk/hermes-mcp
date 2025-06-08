defmodule Upcase.Tools.Upcase do
  @moduledoc "Converts text to upcase"

  use Hermes.Server.Component, type: :tool
  alias Hermes.Server.Response

  schema do
    %{text: {:required, :string}}
  end

  @impl true
  def execute(%{text: text}, frame) do
    {:reply, Response.text(Response.tool(), String.upcase(text)), frame}
  end
end
