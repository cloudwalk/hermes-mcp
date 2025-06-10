# Installation

Add Hermes MCP to your Elixir project.

## Add Dependency

In `mix.exs`:

```elixir
def deps do
  [
    {:hermes_mcp, "~> 0.8"} # x-release-please-version
  ]
end
```

Then:

```shell
mix deps.get
```

## Client Setup

Add to your supervision tree:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Transport layer
      {Hermes.Transport.STDIO, [
        name: MyApp.MCPTransport,
        client: MyApp.MCPClient,
        command: "python",
        args: ["-m", "mcp.server", "my_server.py"]
      ]},

      # MCP client
      {Hermes.Client, [
        name: MyApp.MCPClient,
        transport: [
          layer: Hermes.Transport.STDIO,
          name: MyApp.MCPTransport
        ],
        client_info: %{
          "name" => "MyApp",
          "version" => "1.0.0"
        }
      ]}
    ]

    opts = [strategy: :one_for_all, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## Server Setup

For MCP servers, see [Server Quick Start](server_quickstart.md).

## Client Options

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `:name` | atom | Process name | Required |
| `:transport` | keyword | Transport config | Required |
| `:client_info` | map | Client metadata | Required |
| `:capabilities` | map | Client capabilities | `%{}` |
| `:protocol_version` | string | MCP version | `"2025-03-26"` |
| `:request_timeout` | integer | Timeout (ms) | `30_000` |

## Next Steps

- [Client Usage](client_usage.md) - Using the client
- [Transport Layer](transport.md) - Transport details
- [Server Development](server_quickstart.md) - Build servers
