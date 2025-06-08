defmodule Upcase.Resources.Examples do
  @moduledoc "Provides example texts for transformation"

  use Hermes.Server.Component,
    type: :resource,
    uri: "upcase://examples",
    mime_type: "application/json"

  alias Hermes.Server.Response

  @impl true
  def read(_params, frame) do
    examples = %{
      "examples" => [
        %{
          "title" => "Basic Text",
          "text" => "hello world",
          "description" => "Simple lowercase text for basic transformations"
        },
        %{
          "title" => "Mixed Case",
          "text" => "ThE QuIcK BrOwN FoX",
          "description" => "Text with mixed casing"
        },
        %{
          "title" => "With Punctuation",
          "text" => "Hello, World! How are you?",
          "description" => "Text with punctuation marks"
        },
        %{
          "title" => "Multi-line",
          "text" => "First line\nSecond line\nThird line",
          "description" => "Text spanning multiple lines"
        },
        %{
          "title" => "Special Characters",
          "text" => "café résumé naïve",
          "description" => "Text with accented characters"
        }
      ],
      "metadata" => %{
        "version" => "1.0.0",
        "last_updated" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    {:reply, Response.json(Response.resource(), examples), frame}
  end
end
