defmodule Hermes.SSE.Event do
  @moduledoc false

  @type t :: %__MODULE__{
          id: String.t() | nil,
          event: String.t(),
          data: String.t(),
          retry: integer() | nil
        }

  defstruct id: nil, event: "message", data: "", retry: nil

  @doc """
  Encodes SSE events into the wire format.

  ## Examples

      iex> event = %Hermes.SSE.Event{data: "hello"}
      iex> inspect(event)
      "event: message\\ndata: hello\\n\\n"
      
      iex> event = %Hermes.SSE.Event{id: "123", event: "ping", data: "pong"}
      iex> inspect(event)
      "id: 123\\nevent: ping\\ndata: pong\\n\\n"
  """
  def encode(%__MODULE__{} = event) do
    event
    |> build_fields()
    |> Enum.join()
  end

  defp build_fields(event) do
    []
    |> maybe_add_field("id", event.id)
    |> maybe_add_field("event", event.event)
    |> maybe_add_field("retry", event.retry)
    |> add_data_field(event.data)
    |> add_terminator()
  end

  defp maybe_add_field(fields, _name, nil), do: fields
  defp maybe_add_field(fields, _name, ""), do: fields

  defp maybe_add_field(fields, name, value) do
    fields ++ ["#{name}: #{value}\n"]
  end

  defp add_data_field(fields, ""), do: fields

  defp add_data_field(fields, data) when is_binary(data) do
    data
    |> String.split("\n")
    |> Enum.reduce(fields, fn line, acc ->
      acc ++ ["data: #{line}\n"]
    end)
  end

  defp add_terminator(fields), do: fields ++ ["\n"]
end
