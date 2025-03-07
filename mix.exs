defmodule Hermes.MixProject do
  use Mix.Project

  @version "0.2.2"
  @source_url "https://github.com/cloudwalk/hermes-mcp"

  def project do
    [
      app: :hermes_mcp,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      description: description(),
      aliases: aliases(),
      dialyzer: [plt_local_path: "priv/plts", ignore_warnings: ".dialyzerignore.exs"],
      extra_applications: [:observer, :wx]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Hermes.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:finch, "~> 0.19"},
      {:peri, "~> 0.4.0-rc2"},
      {:mox, "~> 1.2", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:ex_doc, ">= 0.0.0", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    %{
      licenses: ["MIT"],
      contributors: ["zoedsoupe"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://hexdocs.pm/hermes_mcp"
      },
      files: ~w[lib/hermes.ex lib/hermes mix.exs README.md LICENSE]
    }
  end

  defp aliases do
    [setup: ["deps.get", "compile --force"]]
  end

  defp docs do
    [
      main: "home",
      extras: [
        "pages/home.md",
        "pages/installation.md",
        "pages/client_usage.md",
        "pages/transport_options.md",
        "pages/message_handling.md",
        "pages/security.md",
        "pages/troubleshooting.md",
        "pages/examples.md",
        "pages/rfc.md",
        "README.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Guides: [
          "pages/home.md",
          "pages/installation.md",
          "pages/client_usage.md",
          "pages/transport_options.md",
          "pages/message_handling.md"
        ],
        Integration: [
          "pages/security.md"
        ],
        References: [
          "pages/troubleshooting.md",
          "pages/examples.md",
          "pages/rfc.md"
        ]
      ]
    ]
  end

  defp description do
    """
    Model Context Protocol (MCP) implementation in Elixir with Phoenix integration
    """
  end
end
