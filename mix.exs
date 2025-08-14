defmodule Hermes.MixProject do
  use Mix.Project

  @version "0.14.1"
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
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      dialyzer: [
        plt_local_path: "priv/plts",
        ignore_warnings: ".dialyzerignore.exs",
        plt_add_apps: [:mix, :ex_unit]
      ],
      extra_applications: [:observer, :wx],
      releases: releases()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Hermes.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [dialyzer: :test]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:finch, "~> 0.19"},
      {:peri, "~> 0.4"},
      {:telemetry, "~> 1.2"},
      {:gun, "~> 2.2", optional: true},
      {:burrito, "~> 1.0", optional: true},
      {:plug, "~> 1.18", optional: true},
      {:mox, "~> 1.2", only: :test},
      {:mimic, "~> 1.7", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:cowboy, "~> 2.10", only: :test},
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:dev, :test], runtime: false},
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
      files: ~w[lib mix.exs README.md CHANGELOG.md LICENSE .formatter.exs]
    }
  end

  defp aliases do
    [
      setup: ["deps.get", "compile --force"],
      lint: ["format --check-formatted", "credo --strict", "dialyzer"],
      format_doc: ["cmd npx prettier -w ./**/*.md"]
    ]
  end

  defp docs do
    [
      main: "home",
      before_closing_head_tag: &before_closing_head_tag/1,
      extras: [
        "README.md",
        "pages/home.md",
        "pages/building-a-client.md",
        "pages/building-a-server.md",
        "pages/recipes.md",
        "pages/reference.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "LICENSE"
      ],
      groups_for_extras: [
        "Getting Started": [
          "README.md",
          "pages/home.md"
        ],
        "Building with Hermes": [
          "pages/building-a-client.md",
          "pages/building-a-server.md"
        ],
        "Patterns & Reference": [
          "pages/recipes.md",
          "pages/reference.md"
        ],
        "Project Info": [
          "CHANGELOG.md",
          "CONTRIBUTING.md",
          "LICENSE"
        ]
      ]
    ]
  end

  defp before_closing_head_tag(:html) do
    """
    <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
    <script>
    let initialized = false;

    window.addEventListener("exdoc:loaded", () => {
    if (!initialized) {
      mermaid.initialize({
        startOnLoad: false,
        theme: document.body.className.includes("dark") ? "dark" : "default"
      });
      initialized = true;
    }

    let id = 0;
    for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
      const preEl = codeEl.parentElement;
      const graphDefinition = codeEl.textContent;
      const graphEl = document.createElement("div");
      const graphId = "mermaid-graph-" + id++;
      mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
        graphEl.innerHTML = svg;
        bindFunctions?.(graphEl);
        preEl.insertAdjacentElement("afterend", graphEl);
        preEl.remove();
      });
    }
    });
    </script>
    """
  end

  defp before_closing_head_tag(:epub), do: ""

  defp description do
    """
    Model Context Protocol (MCP) implementation in Elixir with Phoenix integration
    """
  end
end
