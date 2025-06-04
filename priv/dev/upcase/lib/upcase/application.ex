defmodule Upcase.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Hermes.Server.Base
  alias Hermes.Server.Transport.StreamableHTTP

  @impl true
  def start(_type, _args) do
    transport = [
      server: Upcase.MCP,
      name: Upcase.HTTP,
      registry: Upcase.Registry
    ]

    mcp_server = [
      module: Upcase.Server,
      protocol_version: "2025-03-26",
      name: Upcase.MCP,
      transport: [
        layer: StreamableHTTP,
        name: Upcase.HTTP
      ]
    ]

    children = [
      {StreamableHTTP, transport},
      {Base, mcp_server},
      {Bandit, plug: Upcase.Router}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Upcase.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
