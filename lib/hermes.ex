defmodule Hermes do
  @moduledoc false

  @doc "Checks if hermes should be compiled/used as standalone CLI or OTP library"
  def should_compile_cli? do
    Code.ensure_loaded?(Burrito) and Application.get_env(:hermes_mcp, :compile_cli?, false)
  end

  @doc """
  Validates a possible GenServer name using `peri` `:custom` type definition.
  """
  def genserver_name({:via, registry, _}) when is_atom(registry), do: :ok
  def genserver_name({:global, _}), do: :ok
  def genserver_name(name) when is_atom(name), do: :ok

  def genserver_name(val) do
    {:error, "#{inspect(val, pretty: true)} is not a valid name for a GenServer"}
  end
end
