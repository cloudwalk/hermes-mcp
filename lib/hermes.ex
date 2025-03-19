defmodule Hermes do
  @moduledoc false

  def env do
    Application.get_env(:hermes_mcp, :env, :dev)
  end

  def dev_env?, do: env() == :dev
end
