defmodule Upcase.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    server_opts = [
      module: Upcase.Server,
      init_args: [],
      transport: [
        layer: Hermes.Server.Transport.STDIO,
        name: Upcase.ServerSTDIO
      ],
      name: Upcase.MCPServer
    ]

    children = [
      {Hermes.Server.Transport.STDIO, server: Upcase.MCPServer},
      {Hermes.Server.Base, server_opts}
    ]

    opts = [strategy: :one_for_one, name: Upcase.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
