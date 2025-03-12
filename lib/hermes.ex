defmodule Hermes do
  @moduledoc false

  def dev_env? do
    if env = Application.get_env(:hermes_mcp, :env) do
      env == :dev
    else
      false
    end
  end
end
