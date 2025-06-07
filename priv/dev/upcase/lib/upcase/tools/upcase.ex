defmodule Upcase.Tools.Upcase do
  @moduledoc "Converts text to upcase"

  use Hermes.Server.Component, type: :tool
  alias Hermes.Server.Response

  schema do
    %{text: {:required, :string}}
  end

  @impl true
  def execute(%{text: text}, frame) do
    {:reply,
     Response.tool()
     |> Response.text(String.upcase(text))
     |> Response.build(), frame}
  end
end
