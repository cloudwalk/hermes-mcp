defmodule Upcase.Tools.Upcase do
  @moduledoc "Converts text to upcase"

  use Hermes.Server.Component, type: :tool

  schema do
    %{text: {:required, :string}}
  end

  @impl true
  def execute(%{text: text}, frame) do
    upcased_text = String.upcase(text)

    response = %{
      "content" => [
        %{
          "type" => "text",
          "text" => upcased_text
        }
      ],
      "isError" => false
    }

    {:reply, response, frame}
  end
end
