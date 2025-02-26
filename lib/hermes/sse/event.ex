defmodule Hermes.SSE.Event do
  @moduledoc """
  Represents a Server-Sent Event.

  Fields:
    - `:id`    - identifier of the event (if any)
    - `:event` - event type (defaults to "message")
    - `:data`  - the event data (concatenates multiple data lines with a newline)
    - `:retry` - reconnection time (parsed as integer, if provided)
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          event: String.t(),
          data: String.t(),
          retry: integer() | nil
        }

  defstruct id: nil, event: "message", data: "", retry: nil
end
