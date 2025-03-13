defmodule Hermes.SSE.Parser do
  @moduledoc """
  Parses a raw SSE stream into a list of `%SSE.Event{}` structs.
  """

  alias Hermes.SSE.Event

  @doc """
  Parses a string containing one or more SSE events.

  Each event is separated by an empty line (two consecutive newlines).
  Returns a list of `%SSE.Event{}` structs.
  """
  def run(sse_data) when is_binary(sse_data) do
    sse_data
    |> String.split(~r/\r?\n\r?\n/, trim: true)
    |> Enum.map(&parse_event/1)
    |> Enum.reject(&(&1.data == ""))
  end

  defp parse_event(event_block) do
    event_block
    |> String.split(~r/\r?\n/)
    |> Enum.reduce(%Event{}, &parse_event_line/2)
  end

  defp parse_event_line("", event), do: event
  # ignore SSE comments
  defp parse_event_line(<<":", _rest::binary>>, event), do: event

  defp parse_event_line(line, event) do
    case String.split(line, ":", parts: 2) do
      ["id", value] -> %{event | id: String.trim_leading(value)}
      ["event", value] -> %{event | event: String.trim_leading(value)}
      ["data", value] -> handle_data(event, String.trim_leading(value))
      ["retry", value] -> handle_retry(event, String.trim_leading(value))
      [_, _] -> event
      [_] -> event
    end
  end

  defp handle_data(%Event{data: ""} = event, data) do
    %{event | data: data}
  end

  defp handle_data(%Event{data: current_data} = event, data) do
    %{event | data: current_data <> "\n" <> data}
  end

  defp handle_retry(%Event{retry: _} = event, value) do
    case Integer.parse(value) do
      {retry, _} -> %{event | retry: retry}
      :error -> event
    end
  end
end
