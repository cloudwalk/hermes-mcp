# Transport Layer

Connect MCP clients to servers using different transport mechanisms.

## Available Transports

| Transport | Module | Use Case |
|-----------|--------|----------|
| **STDIO** | `Hermes.Transport.STDIO` | Local subprocess servers |
| **SSE** | `Hermes.Transport.SSE` | HTTP servers with Server-Sent Events |
| **WebSocket** | `Hermes.Transport.WebSocket` | Real-time bidirectional communication |
| **StreamableHTTP** | `Hermes.Transport.StreamableHTTP` | HTTP with streaming responses |

## Transport Interface

All transports implement:

```elixir
@callback start_link(keyword()) :: GenServer.on_start()
@callback send_message(t(), message()) :: :ok | {:error, reason()}
@callback shutdown(t()) :: :ok | {:error, reason()}
```

## STDIO Transport

For local subprocess servers.

### Configuration

```elixir
{Hermes.Transport.STDIO, [
  name: MyApp.MCPTransport,
  client: MyApp.MCPClient,
  command: "python",
  args: ["-m", "mcp.server", "my_server.py"],
  env: %{"PYTHONPATH" => "/path/to/modules"},
  cwd: "/path/to/server"
]}
```

### Options

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `:name` | atom | Process name | Required |
| `:client` | pid/name | Client process | Required |
| `:command` | string | Command to run | Required |
| `:args` | list | Command arguments | `[]` |
| `:env` | map | Environment vars | System defaults |
| `:cwd` | string | Working directory | Current dir |

## SSE Transport

For HTTP servers with Server-Sent Events.

### Configuration

```elixir
{Hermes.Transport.SSE, [
  name: MyApp.HTTPTransport,
  client: MyApp.MCPClient,
  server: [
    base_url: "https://api.example.com",
    base_path: "/mcp",
    sse_path: "/sse"
  ],
  headers: [{"Authorization", "Bearer token"}]
]}
```

### Options

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `:server.base_url` | string | Server URL | Required |
| `:server.base_path` | string | Base path | `"/"` |
| `:server.sse_path` | string | SSE endpoint | `"/sse"` |
| `:headers` | list | HTTP headers | `[]` |

## WebSocket Transport

For real-time bidirectional communication.

### Configuration

```elixir
{Hermes.Transport.WebSocket, [
  name: MyApp.WSTransport,
  client: MyApp.MCPClient,
  server: [
    base_url: "wss://api.example.com",
    ws_path: "/ws"
  ]
]}
```

### Options

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `:server.base_url` | string | WebSocket URL | Required |
| `:server.ws_path` | string | WS endpoint | `"/ws"` |
| `:headers` | list | HTTP headers | `[]` |

## Custom Transport

Implement the behaviour:

```elixir
defmodule MyTransport do
  @behaviour Hermes.Transport.Behaviour
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def send_message(pid, message) do
    GenServer.call(pid, {:send, message})
  end

  def shutdown(pid) do
    GenServer.stop(pid)
  end

  # GenServer callbacks...
end
```

## Supervision

Use `:one_for_all` strategy:

```elixir
children = [
  {Hermes.Transport.STDIO, transport_opts},
  {Hermes.Client, client_opts}
]

Supervisor.start_link(children, strategy: :one_for_all)
```

Transport and client depend on each other - if one fails, restart both.

## References

See [MCP transport specification](https://spec.modelcontextprotocol.io/specification/basic/transports/)
