# Installation & Setup

Setting up Hermes MCP for your Elixir project involves a few straightforward steps.

## Adding the Dependency

Add Hermes MCP to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hermes_mcp, "~> 0.3"}
  ]
end
```

Then run:

```shell
mix deps.get
```

## Supervision Tree Integration

Hermes MCP is designed to be integrated into your application's supervision tree. This provides robust lifecycle management and automatic recovery in case of failures.

### Basic Integration Example (stdio)

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Start the MCP transport
      {Hermes.Transport.STDIO, [
        name: MyApp.MCPTransport,
        client: MyApp.MCPClient,
        command: "mcp",
        args: ["run", "path/to/server.py"],
        env: %{"HOME" => "/Users/my-user"}
      ]},

      # Start the MCP client using the transport
      {Hermes.Client, [
        name: MyApp.MCPClient,
        transport: [
          # layer is required
          layer: Hermes.Transport.STDIO,
          # you can give a custom name
          name: MyApp.MCPTransport
        ],
        client_info: %{
          "name" => "MyApp",
          "version" => "1.0.0"
        },
        capabilities: %{
          "roots" => %{"listChanged" => true},
          "sampling" => %{}
        }
      ]}

      # Your other application services
      # ...
    ]

    opts = [strategy: :one_for_all, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## Configuration Options

### Client Configuration

The `Hermes.Client` accepts the following options:

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `:name` | atom | Registration name for the client process | `__MODULE__` |
| `:transport` | enumerable | The transport options | Required |
| `:transport.layer` | module | The transport layer, currently only `Hermes.Transport.STDIO` or `Hermes.Transport.SSE` | Required |
| `:transport.name` | [GenServer.server](https://hexdocs.pm/elixir/GenServer.html#t:server/0) | An optional custom transport process name | The transport module |
| `:client_info` | map | Information about the client | Required |
| `:capabilities` | map | Client capabilities to advertise | `%{"roots" => %{"listChanged" => true}, "sampling" => %{}}` |
| `:protocol_version` | string | Protocol version to use | `"2024-11-05"` |
| `:request_timeout` | integer | Default timeout for requests in milliseconds | 30s |
