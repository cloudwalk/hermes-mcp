defmodule Hermes.Server.Frame do
  @moduledoc """
  Server frame for maintaining state across MCP message handling.

  Similar to LiveView's Socket or Plug.Conn, the Frame provides a consistent
  interface for storing and updating server state throughout the request lifecycle.

  ## Usage

      # Create a new frame
      frame = Frame.new()

      # Assign values
      frame = Frame.assign(frame, :user_id, 123)
      frame = Frame.assign(frame, %{status: :active, count: 0})

      # Conditional assignment
      frame = Frame.assign_new(frame, :timestamp, fn -> DateTime.utc_now() end)

  ## Fields

  - `assigns` - A map containing arbitrary data assigned during request processing
  - `initialized` - Boolean indicating if the server has been initialized
  """

  @type t :: %__MODULE__{
          assigns: Enumerable.t(),
          initialized: boolean
        }

  defstruct assigns: %{}, initialized: false

  @doc """
  Creates a new frame with optional initial assigns.

  ## Examples

      iex> Frame.new()
      %Frame{assigns: %{}, initialized: false}

      iex> Frame.new(%{user: "alice"})
      %Frame{assigns: %{user: "alice"}, initialized: false}
  """
  @spec new :: t
  @spec new(assigns :: Enumerable.t()) :: t
  def new(assigns \\ %{}), do: struct(__MODULE__, assigns: assigns)

  @doc """
  Assigns a value or multiple values to the frame.

  ## Examples

      # Single assignment
      frame = Frame.assign(frame, :status, :active)

      # Multiple assignments via map
      frame = Frame.assign(frame, %{status: :active, count: 5})

      # Multiple assignments via keyword list
      frame = Frame.assign(frame, status: :active, count: 5)
  """
  @spec assign(t, Enumerable.t()) :: t
  @spec assign(t, key :: atom, value :: any) :: t
  def assign(%__MODULE__{} = frame, assigns) when is_map(assigns) or is_list(assigns) do
    Enum.reduce(assigns, frame, fn {key, value}, frame -> assign(frame, key, value) end)
  end

  def assign(%__MODULE__{} = frame, key, value) when is_atom(key) do
    %{frame | assigns: Map.put(frame.assigns, key, value)}
  end

  @doc """
  Assigns a value to the frame only if the key doesn't already exist.

  The value is computed lazily using the provided function, which is only
  called if the key is not present in assigns.

  ## Examples

      # Only assigns if :timestamp doesn't exist
      frame = Frame.assign_new(frame, :timestamp, fn -> DateTime.utc_now() end)

      # Function is not called if key exists
      frame = frame |> Frame.assign(:count, 5)
                    |> Frame.assign_new(:count, fn -> expensive_computation() end)
      # count remains 5
  """
  @spec assign_new(t, key :: atom, value_fun :: (-> term)) :: t
  def assign_new(%__MODULE__{} = frame, key, fun) when is_atom(key) and is_function(fun, 0) do
    case frame.assigns do
      %{^key => _} -> frame
      _ -> assign(frame, key, fun.())
    end
  end
end
