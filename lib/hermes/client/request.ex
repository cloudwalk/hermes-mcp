defmodule Hermes.Client.Request do
  @moduledoc false

  @type t :: %__MODULE__{
          id: String.t(),
          method: String.t(),
          from: GenServer.from(),
          timer_ref: reference(),
          start_time: integer(),
          params: map()
        }

  defstruct [:id, :method, :from, :timer_ref, :start_time, :params]

  @doc """
  Creates a new request struct.

  ## Parameters

    * `attrs` - Map containing the request attributes
      * `:id` - The unique request ID
      * `:method` - The MCP method name
      * `:from` - The GenServer caller reference
      * `:timer_ref` - Reference to the request-specific timeout timer
  """
  @spec new(%{
          id: String.t(),
          method: String.t(),
          from: GenServer.from(),
          timer_ref: reference(),
          params: map()
        }) :: t()
  def new(attrs) do
    %__MODULE__{
      id: attrs.id,
      method: attrs.method,
      from: attrs.from,
      timer_ref: attrs.timer_ref,
      params: attrs.params,
      start_time: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Calculates the elapsed time for a request in milliseconds.
  """
  @spec elapsed_time(t()) :: integer()
  def elapsed_time(%__MODULE__{start_time: start_time}) do
    System.monotonic_time(:millisecond) - start_time
  end
end

defimpl Inspect, for: Hermes.Client.Request do
  def inspect(%{id: id, method: method, start_time: start_time}, _opts) do
    elapsed = System.monotonic_time(:millisecond) - start_time
    "#MCP.Client.Request<#{id} #{method} (elapsed: #{elapsed}ms)>"
  end
end
