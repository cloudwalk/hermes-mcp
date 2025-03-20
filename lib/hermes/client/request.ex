defmodule Hermes.Client.Request do
  @moduledoc """
  Represents a pending request in the MCP client.

  This struct encapsulates all information about an in-progress request:
  - `id` - The unique request ID
  - `method` - The MCP method being called
  - `from` - The GenServer caller reference
  - `timer_ref` - Reference to the timeout timer
  - `start_time` - When the request started (monotonic time in milliseconds)
  """

  @type t :: %__MODULE__{
          id: String.t(),
          method: String.t(),
          from: GenServer.from(),
          timer_ref: reference(),
          start_time: integer()
        }

  defstruct [:id, :method, :from, :timer_ref, :start_time]

  @doc """
  Creates a new request struct.

  ## Parameters

    * `attrs` - Map containing the request attributes
      * `:id` - The unique request ID
      * `:method` - The MCP method name
      * `:from` - The GenServer caller reference
      * `:timer_ref` - Reference to the timeout timer
  """
  @spec new(%{id: String.t(), method: String.t(), from: GenServer.from(), timer_ref: reference()}) :: t()
  def new(%{id: id, method: method, from: from, timer_ref: timer_ref}) do
    %__MODULE__{
      id: id,
      method: method,
      from: from,
      timer_ref: timer_ref,
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
