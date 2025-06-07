# Server Transport Configuration

Hermes MCP servers support multiple transport mechanisms to accept connections from clients. This page covers the available options and how to configure them.

## Available Transports

| Transport | Module | Use Case | Multi-Client |
|-----------|--------|----------|--------------|
| **STDIO** | `Hermes.Server.Transport.STDIO` | CLI tools, local scripts | No |
| **StreamableHTTP** | `Hermes.Server.Transport.StreamableHTTP` | Web apps, HTTP APIs | Yes |

## STDIO Transport

The STDIO transport enables communication through standard input/output streams. It's suitable for local integrations and CLI tools.

### Configuration

```elixir
# Start server with STDIO transport
{MyServer, transport: :stdio}

# With explicit configuration
{MyServer, transport: {:stdio, name: :my_stdio_server}}
```

### Example: CLI Tool Server

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {MyApp.MCPServer, transport: :stdio}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## StreamableHTTP Transport

The StreamableHTTP transport enables communication over HTTP using Server-Sent Events (SSE) for responses. It supports multiple concurrent clients.

### Configuration

```elixir
# Basic configuration
{MyServer, transport: :streamable_http}

# With port configuration
{MyServer, transport: {:streamable_http, port: 8080}}

# Full configuration
{MyServer, transport: {:streamable_http,
  port: 8080,
  path: "/mcp",
  start: true  # Force start even without HTTP server
}}
```

### Configuration Options

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `:port` | integer | Port number for HTTP server | `8080` |
| `:path` | string | URL path for MCP endpoint | `"/mcp"` |
| `:start` | boolean/`:auto` | Start behavior | `:auto` |

### Conditional Startup

StreamableHTTP transport has smart startup behavior:

```elixir
# Auto-detect (default) - starts only if HTTP server is running
{MyServer, transport: :streamable_http}

# Force start - always start HTTP server
{MyServer, transport: {:streamable_http, start: true}}

# Prevent start - never start, useful for tests
{MyServer, transport: {:streamable_http, start: false}}
```

### Integration with Phoenix

If you're using Phoenix, you can integrate the MCP server with your existing endpoint:

```elixir
# In lib/my_app_web/endpoint.ex
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app

  # Add the MCP plug
  plug Hermes.Server.Transport.StreamableHTTP.Plug,
    server: MyApp.MCPServer,
    path: "/mcp"
  
  # Other plugs...
end
```

## Transport Selection

### Use STDIO when:
- Building CLI tools
- Local development and testing
- Single-client scenarios
- Subprocess communication

### Use StreamableHTTP when:
- Building web applications
- Need multiple concurrent clients
- Integrating with existing HTTP services
- Production deployments

## Supervision

Transports are supervised as part of the server supervision tree:

```elixir
# The server supervisor handles both the server and transport
children = [
  {MyApp.MCPServer, transport: :stdio}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

## Custom Transport Options

For advanced configurations, you can specify the transport module directly:

```elixir
{MyServer, transport: [
  layer: Hermes.Server.Transport.STDIO,
  name: :custom_stdio
  # Additional options...
]}
```

## References

For more information about MCP transport layers, see the official [MCP specification](https://spec.modelcontextprotocol.io/specification/basic/transports/)
