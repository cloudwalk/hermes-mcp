defmodule Hermes.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Finch, name: Hermes.Finch, pools: %{default: [size: 15]}}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hermes.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    if Hermes.env() == :prod do
      Hermes.CLI.main()
      {:ok, pid}
    else
      {:ok, pid}
    end
  end
end
