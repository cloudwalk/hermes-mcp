defmodule Echo.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Echo.PubSub},
      EchoWeb.Endpoint,
      Hermes.Server.Registry,
      {EchoMCP.Server, transport: {:sse, base_url: "/mcp", post_path: "/message"}}
    ]

    opts = [strategy: :one_for_one, name: Echo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    EchoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
