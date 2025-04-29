defmodule Hermes.MixProject do
  use Mix.Project

  @version "0.3.12"
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
      dialyzer: [
        plt_local_path: "priv/plts",
        ignore_warnings: ".dialyzerignore.exs",
        plt_add_apps: [:mix]
      ],
      extra_applications: [:observer, :wx],
      releases: releases()
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
      {:peri, "~> 0.3.2"},
      {:gun, "~> 2.2"},
      {:burrito, "~> 1.0", optional: true},
      {:mox, "~> 1.2", only: :test},
      {:mimic, "~> 1.7", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:cowboy, "~> 2.10", only: :test},
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false}
    ]
  end

  # Define releases for standalone binaries
  def releases do
    [
      hermes_mcp: [
        steps: [:assemble, &Burrito.wrap/1],
        applications: [
          hermes_mcp: :permanent
        ],
        include_executables_for: [:unix, :windows],
        burrito: [
          targets: [
            macos_intel: [os: :darwin, cpu: :x86_64],
            macos_arm: [os: :darwin, cpu: :aarch64],
            linux: [os: :linux, cpu: :x86_64],
            windows: [os: :windows, cpu: :x86_64]
          ]
        ],
        # Set the CLI module as the main entry point
        default_release: true,
        main_module: Hermes.CLI
      ]
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
      files: ~w[lib mix.exs README.md CHANGELOG.md LICENSE]
    }
  end

  defp aliases do
    [
      setup: ["deps.get", "compile --force"],
      lint: ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end

  defp docs do
    [
      main: "home",
      extras: [
        "pages/home.md",
        "pages/installation.md",
        "pages/transport.md",
        "pages/client_usage.md",
        "pages/message_handling.md",
        "pages/rfc.md",
        "pages/progress_tracking.md",
        "pages/logging.md",
        "pages/error_handling.md",
        "pages/protocol_upgrade_2025_03_26.md",
        "pages/cli_usage.md",
        "README.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "ROADMAP.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Guides: [
          "pages/home.md",
          "pages/installation.md",
          "pages/transport.md",
          "pages/client_usage.md",
          "pages/message_handling.md",
          "pages/error_handling.md",
          "pages/progress_tracking.md",
          "pages/logging.md",
          "pages/cli_usage.md"
        ],
        References: [
          "pages/rfc.md",
          "ROADMAP.md",
          "pages/protocol_upgrade_2025_03_26.md"
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
