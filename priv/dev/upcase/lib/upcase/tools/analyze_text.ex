defmodule Upcase.Tools.AnalyzeText do
  @moduledoc "Analyzes text and returns structured data"

  use Hermes.Server.Component, type: :tool
  alias Hermes.Server.Response

  schema do
    %{text: {:required, :string}}
  end

  @impl true
  def execute(%{text: text}, frame) do
    analysis = %{
      original: text,
      length: String.length(text),
      word_count: length(String.split(text, ~r/\s+/, trim: true)),
      character_stats: %{
        uppercase: count_chars(text, &(&1 in ?A..?Z)),
        lowercase: count_chars(text, &(&1 in ?a..?z)),
        digits: count_chars(text, &(&1 in ?0..?9)),
        spaces: count_chars(text, &(&1 == ?\s))
      },
      transformations: %{
        uppercase: String.upcase(text),
        lowercase: String.downcase(text),
        reversed: String.reverse(text)
      }
    }

    {:reply,
     Response.tool()
     |> Response.json(analysis)
     |> Response.build(), frame}
  end

  defp count_chars(text, predicate) do
    text
    |> String.to_charlist()
    |> Enum.count(predicate)
  end
end