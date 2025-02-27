# Installation & Setup

Setting up Hermes MCP for your Elixir project involves a few straightforward steps.

## Adding the Dependency

Add Hermes MCP to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hermes_mcp, "~> 0.2.0"}
  ]
end
```

Then run:

```shell
mix deps.get
```

## Supervision Tree Integration

Hermes MCP is designed to be integrated into your application's supervision tree. This provides robust lifecycle management and automatic recovery in case of failures.

### Basic Integration Example

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
        args: ["run", "path/to/server.py"]
      ]},
      
      # Start the MCP client using the transport
      {Hermes.Client, [
        name: MyApp.MCPClient,
        transport: MyApp.MCPTransport,
        client_info: %{
          "name" => "MyApp",
          "version" => "1.0.0"
        },
        capabilities: %{
          "resources" => %{},
          "tools" => %{},
          "prompts" => %{}
        }
      ]}
      
      # Your other application services
      # ...
    ]
    
    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
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
| `:transport` | module or pid | The transport module or process | Required |
| `:client_info` | map | Information about the client | Required |
| `:capabilities` | map | Client capabilities to advertise | `%{"resources" => %{}, "tools" => %{}}` |
| `:protocol_version` | string | Protocol version to use | `"2024-11-05"` |
| `:request_timeout` | integer | Default timeout for requests in milliseconds | 30000 |

### Transport Configuration

The `Hermes.Transport.STDIO` accepts the following options:

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `:name` | atom | Registration name for the transport process | `__MODULE__` |
| `:client` | atom or pid | The client process that will receive messages | Required |
| `:command` | string | The command to execute | Required |
| `:args` | list | Command line arguments | `nil` |
| `:env` | map | Environment variables | System defaults |
| `:cwd` | string | Working directory | Current directory |

## Environment Requirements

- Elixir 1.18 or later
- Erlang/OTP 26 or later
