defmodule Upcase.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Hermes.Server.Registry,
      {Upcase.Server, transport: {:streamable_http, start: true}},
      {Bandit, plug: Upcase.Router}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Upcase.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
