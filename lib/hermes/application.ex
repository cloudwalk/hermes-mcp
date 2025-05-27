defmodule Hermes.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :logger.add_handlers(:hermes_mcp)

    children = [
      {Finch, name: Hermes.Finch, pools: %{default: [size: 15]}}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hermes.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    if Hermes.should_compile_cli?() do
      with {:module, cli} <- Code.ensure_loaded(Hermes.CLI), do: cli.main()
      {:ok, pid}
    else
      {:ok, pid}
    end
  end
end
