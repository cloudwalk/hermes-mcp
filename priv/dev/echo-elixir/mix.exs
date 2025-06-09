defmodule Echo.MixProject do
  use Mix.Project

  def project do
    [
      app: :echo,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Echo.Application, []},
      extra_applications: [:logger, :runtime_tools, :wx, :observer]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7.21"},
      {:bandit, "~> 1.5"},
      {:hermes_mcp, path: "../../../"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "compile --force --warning-as-errors"]
    ]
  end
end
