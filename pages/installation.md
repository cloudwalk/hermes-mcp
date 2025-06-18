# Installation

Add Hermes MCP to your Elixir project.

## Add Dependency

In `mix.exs`:

```elixir
def deps do
  [
    {:hermes_mcp, "~> 0.10.0"} # x-release-please-version
  ]
end
```

Then:

```shell
mix deps.get
```

## Client Setup

Define a client module:

```elixir
defmodule MyApp.MCPClient do
  use Hermes.Client,
    name: "MyApp",
    version: "1.0.0",
    protocol_version: "2024-11-05",
    capabilities: [:roots, :sampling]
end
```

Add to your supervision tree:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # MCP client with STDIO transport
      {MyApp.MCPClient, 
       transport: {:stdio, command: "python", args: ["-m", "mcp.server", "my_server.py"]}}
    ]

    opts = [strategy: :one_for_all, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## Server Setup

For MCP servers, see [Server Quick Start](server_quickstart.md).

## Client Module Options

When defining a client module with `use Hermes.Client`:

| Option | Type | Description | Required |
|--------|------|-------------|----------|
| `:name` | string | Client name to advertise | Yes |
| `:version` | string | Client version | Yes |
| `:protocol_version` | string | MCP protocol version | Yes |
| `:capabilities` | list | Client capabilities | Yes |

## Transport Options

When starting the client:

| Transport | Options | Example |
|-----------|---------|----------|
| STDIO | `command`, `args` | `{:stdio, command: "python", args: ["-m", "server"]}` |
| SSE | `base_url` | `{:sse, base_url: "http://localhost:8000"}` |
| WebSocket | `url` | `{:websocket, url: "ws://localhost:8000/ws"}` |
| HTTP | `url` | `{:streamable_http, url: "http://localhost:8000/mcp"}` |

## Next Steps

- [Client Usage](client_usage.md) - Using the client
- [Transport Layer](transport.md) - Transport details
- [Server Development](server_quickstart.md) - Build servers
