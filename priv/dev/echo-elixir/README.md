# Echo MCP Server

A comprehensive Phoenix-based MCP server that demonstrates Server-Sent Events transport and the full spectrum of MCP capabilities through Hermes.

## Exploring Real-time MCP Communication

What happens when you combine Phoenix's real-time capabilities with the Model Context Protocol? The Echo server answers this by implementing an SSE-based transport that enables streaming communication between clients and servers. This approach showcases how Hermes adapts to different transport mechanisms while maintaining protocol compliance.

## Transport Architecture

The server's most distinctive feature is its use of Server-Sent Events (SSE) for MCP communication. Unlike traditional request-response patterns, SSE enables the server to push updates to clients, opening possibilities for progress notifications, streaming responses, and real-time collaboration.

### SSE Configuration

```elixir
# Application configuration
transport: {:sse, base_url: "/mcp", post_path: "/message"}

# Router setup creates two endpoints
get "/mcp/sse", SSE.Plug, server: EchoMCP.Server      # Event stream
post "/mcp/message", SSE.Plug, server: EchoMCP.Server  # Message submission
```

This dual-endpoint pattern separates the persistent event stream from message submissions, allowing for efficient bidirectional communication over HTTP.

## Comprehensive MCP Capabilities

The Echo server implements all three core MCP capabilities, making it an excellent reference for understanding the protocol's full potential.

### Tools Implementation

**Echo Tool**

The foundational echo tool demonstrates stateful request handling. Each invocation increments a server-side counter, showing how Hermes servers can maintain context across requests.

```elixir
def handle_tool("echo", %{text: text}, frame) do
  new_frame = update_in(frame.assigns.counter, &(&1 + 1))
  Logger.info("Echo called #{new_frame.assigns.counter} times")
  {:reply, text, new_frame}
end
```

**Save Note Tool**

A sophisticated example featuring nested schemas with optional parameters and enumerations. This tool showcases how to build complex, validated APIs that remain developer-friendly.

```elixir
# Complex schema with nested validation
%{
  title: {:required, :string, max: 100},
  content: {:required, :string},
  metadata: {:optional, %{
    tags: {:optional, {:list, :string}},
    priority: {:optional, :string, enum: ["low", "medium", "high"], default: "medium"}
  }}
}
```

### Prompts System

The greeting prompt demonstrates dynamic content generation based on parameters. This pattern shows how MCP servers can assist LLMs with context-aware prompt construction.

```elixir
# Generates formal or casual greetings
case style do
  "formal" -> "Good day, #{name}. How may I assist you today?"
  "casual" -> "Hey #{name}! What's up?"
end
```

### Resource Management

The server exposes system information through the `file:///server/info` resource. This demonstrates how MCP servers can provide self-describing metadata, enabling clients to discover server capabilities dynamically.

## Frame-based State Management

Notice how the server uses Hermes' frame pattern for state management:

```elixir
def init(_client_info, frame) do
  {:ok, assign(frame, counter: 0)}
end
```

This approach, inspired by Phoenix LiveView's socket assigns, provides a familiar pattern for Elixir developers while ensuring proper state isolation between requests.

## Development Workflow

### Running the Server

The Echo server supports two transport modes: SSE (Server-Sent Events) and STDIO.

#### SSE Transport (default)

```bash
# Install dependencies
mix setup

# Start Phoenix server with SSE transport
mix phx.server

# Or explicitly set transport
MCP_TRANSPORT=sse mix phx.server
```

The server starts on port 4000, with the SSE endpoint accessible at `http://localhost:4000/mcp/sse`.

#### STDIO Transport

For direct STDIO communication (useful for CLI tools and testing):

```bash
# Run with STDIO transport
MCP_TRANSPORT=stdio mix run --no-halt

# Or use the just command from the project root
just echo-ex-server transport=stdio
```

In STDIO mode, the server communicates via standard input/output, making it compatible with MCP clients that expect traditional pipe-based communication.

## Extension Opportunities

As you explore this implementation, consider these enhancement possibilities:

- How would you add authentication to the SSE stream?
- What patterns would you use for broadcasting updates to multiple connected clients?
- How might you implement request queuing for rate-limited operations?

The Echo server demonstrates that with Hermes, you can build feature-rich MCP servers that leverage Phoenix's strengths while maintaining clean separation between transport, protocol, and business logic. This architecture enables you to focus on your domain-specific tools while Hermes handles the protocol complexity.
