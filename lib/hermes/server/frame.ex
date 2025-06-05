defmodule Hermes.Server.Frame do
  @moduledoc "Like LiveView Socket or Plug.Conn"

  alias Hermes.Server.Transport.STDIO
  alias Hermes.Server.Transport.StreamableHTTP

  @type transport_t :: %{name: GenServer.name(), layer: StreamableHTTP | STDIO}

  @type t :: %__MODULE__{
          assigns: Enumerable.t(),
          transport: transport_t,
          initialized: boolean
        }

  defstruct assigns: %{}, transport: %{}, initialized: false

  @spec assign(t, Enumerable.t()) :: t
  @spec assign(t, key :: atom, value :: any) :: t
  def assign(%__MODULE__{} = frame, assigns) when is_map(assigns) or is_list(assigns) do
    Enum.reduce(assigns, frame, fn {key, value}, frame -> assign(frame, key, value) end)
  end

  def assign(%__MODULE__{} = frame, key, value) when is_atom(key) do
    %{frame | assigns: Map.put(frame.assigns, key, value)}
  end

  @spec assign_new(t, key :: atom, value_fun :: (-> term)) :: t
  def assign_new(%__MODULE__{} = frame, key, fun) when is_atom(key) and is_function(fun, 0) do
    case frame.assigns do
      %{^key => _} -> frame
      _ -> assign(frame, key, fun.())
    end
  end
end
