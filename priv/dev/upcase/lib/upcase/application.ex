defmodule Upcase.Application do
  @moduledoc false

  use Application

  alias Hermes.Server.Transport.StreamableHTTP.Supervisor, as: StreamableSupervisor

  @impl true
  def start(_type, _args) do
    # STDIO server configuration
    stdio_server_opts = [
      module: Upcase.Server,
      init_args: [],
      transport: [
        layer: Hermes.Server.Transport.STDIO,
        name: Upcase.ServerSTDIO
      ],
      name: Upcase.MCPServer
    ]

    # HTTP server configuration
    http_server_opts = [
      module: Upcase.Server,
      init_args: [],
      transport: [
        layer: Hermes.Server.Transport.StreamableHTTP,
        name: Upcase.ServerHTTP,
        registry: Upcase.SessionRegistry
      ],
      name: Upcase.MCPHTTPServer
    ]

    children = [
      # STDIO transport and server
      # {Hermes.Server.Transport.STDIO, server: Upcase.MCPServer, name: Upcase.ServerSTDIO},
      # Supervisor.child_spec({Hermes.Server.Base, stdio_server_opts}, id: :stdio),

      # HTTP transport supervisor
      {StreamableSupervisor,
       [
         server: Upcase.MCPHTTPServer,
         transport_name: Upcase.ServerHTTP,
         registry_name: Upcase.SessionRegistry
       ]},
      # HTTP server
      Supervisor.child_spec({Hermes.Server.Base, http_server_opts}, id: :http),

      # HTTP endpoint
      {Bandit, plug: Upcase.HTTP, scheme: :http, port: 4000}
    ]

    opts = [strategy: :one_for_one, name: Upcase.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
