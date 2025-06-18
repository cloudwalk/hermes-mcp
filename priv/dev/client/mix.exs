defmodule Incomer.MixProject do
  use Mix.Project

  def project do
    [
      app: :incomer,
      version: "0.1.0",
      elixir: "~> 1.19-rc",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Incomer.Application, []}
    ]
  end

  defp deps do
    [
      {:hermes_mcp, path: "../../../"}
    ]
  end
end
