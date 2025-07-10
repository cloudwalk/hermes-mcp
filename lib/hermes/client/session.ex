defmodule Hermes.Client.Session do
  @moduledoc false

  @type private_t :: %{
          optional(:session_id) => String.t(),
          optional(:server_info) => map,
          optional(:server_capabilities) => map,
          optional(:protocol_version) => String.t()
        }

  @type t :: %__MODULE__{
          assigns: map,
          private: private_t,
          initialized: boolean
        }

  defstruct assigns: %{}, initialized: false, private: %{}

  @spec assign(t, Enumerable.t()) :: t
  @spec assign(t, key :: atom, value :: any) :: t
  def assign(%__MODULE__{} = session, assigns) when is_map(assigns) or is_list(assigns) do
    Enum.reduce(assigns, session, fn {key, value}, session ->
      assign(session, key, value)
    end)
  end

  def assign(%__MODULE__{} = session, key, value) when is_atom(key) do
    %{session | assigns: Map.put(session.assigns, key, value)}
  end

  @spec assign_new(t, key :: atom, value_fun :: (-> term)) :: t
  def assign_new(%__MODULE__{} = session, key, fun)
      when is_atom(key) and is_function(fun, 0) do
    case session.assigns do
      %{^key => _} -> session
      _ -> assign(session, key, fun.())
    end
  end

  @spec put_private(t, atom, any) :: t
  @spec put_private(t, Enumerable.t()) :: t
  def put_private(%__MODULE__{} = session, key, value) when is_atom(key) do
    %{session | private: Map.put(session.private, key, value)}
  end

  def put_private(%__MODULE__{} = session, private)
      when is_map(private) or is_list(private) do
    Enum.reduce(private, session, fn {key, value}, session ->
      put_private(session, key, value)
    end)
  end
end
