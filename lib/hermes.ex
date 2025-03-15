defmodule Hermes do
  @moduledoc false

  def env do
    Application.get_env(:hermes_mcp, :env, :dev)
  end

  def dev_env? do
    if env = Application.get_env(:hermes_mcp, :env) do
      env == :dev
    else
      false
    end
  end

  def genserver_name({:via, registry, _}) when is_atom(registry), do: :ok
  def genserver_name(name) when is_atom(name), do: :ok
  def genserver_name(pid) when is_pid(pid), do: :ok
  def genserver_name(val), do: {:error, "#{val} is not a valid name for a GenServer"}
end
