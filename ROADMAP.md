# Hermes MCP Roadmap

This document outlines the development roadmap for Hermes MCP, an Elixir implementation of the Model Context Protocol (MCP). The roadmap is organized by key milestones and development areas.

## Current Status

Hermes MCP currently provides a complete client implementation for the MCP 2024-11-05 specification with:

- Full protocol lifecycle management (initialization, operation, shutdown)
- Multiple transport options (STDIO and HTTP/SSE)
- Connection supervision and automatic recovery
- Comprehensive capability negotiation
- Progress tracking for long-running operations
- Cancellation support
- Structured logging
- Interactive test shell for development

## Upcoming Milestones

### 1. MCP 2025-03-26 Specification Support

The MCP specification was updated on 2025-03-26 with several breaking changes and new features. Our implementation plan includes:

#### Phase 1: Core Infrastructure (Q2 2025)

- Support for protocol version negotiation
- Multi-version compatibility layer
- Backward compatibility with 2024-11-05 servers

#### Phase 2: Transport Layer Updates (Q2-Q3 2025)

- Implement Streamable HTTP transport
- Maintain compatibility with HTTP+SSE for older servers
- Support session management via `Mcp-Session-Id` header
- Implement stream resumability with `Last-Event-ID`

#### Phase 3: New Protocol Features (Q3 2025)

- Support for OAuth 2.1 authorization framework
  - Server metadata discovery
  - Dynamic client registration
  - Token management and refresh
- JSON-RPC batching for improved performance
- Enhanced tool annotations
- Explicit completions capability
- Audio content type support
- Message field for progress notifications

See [protocol_upgrade_2025_03_26.md](./pages/protocol_upgrade_2025_03_26.md) for detailed information about these changes.

### 2. Server Implementation (Q3-Q4 2025)

After stabilizing the client implementation for both protocol versions, we plan to develop a complete server-side implementation:

#### Phase 1: Core Server Infrastructure

- Server-side protocol implementation
- Capability management
- Request handling framework
- Resource, prompt, and tool abstractions

#### Phase 2: Transport Implementations

- STDIO transport for local process communication
- HTTP/SSE transport for 2024-11-05 compatibility
- Streamable HTTP transport for 2025-03-26 support

#### Phase 3: Feature Implementations

- Resources management and subscription
- Tools registration and invocation
- Prompts template system
- Logging and telemetry
- Authorization framework

### 3. Sample Implementations and Integration Examples (Q4 2025+)

Once both client and server implementations are stable, we plan to provide:

- Reference server implementations
- Sample integration with Elixir ecosystem libraries
- Example applications demonstrating MCP use cases
- Integration with popular AI frameworks and platforms

## Feature Backlog

Beyond the core roadmap, we maintain a backlog of features for future consideration:

- **WebSockets Transport**: Alternative transport layer for bidirectional communication
- **Observability**: Advanced telemetry and monitoring integration
- **Rate Limiting and Quota Management**: For server implementations
- **Testing Tools**: Extended tools for protocol testing and validation

## Contributing

We welcome contributions to any part of this roadmap. See [CONTRIBUTING.md](./CONTRIBUTING.md) for details on how to get involved.

Issues are tracked in GitHub and tagged with milestone information. For current development priorities, see our [open issues](https://github.com/cloudwalk/hermes-mcp/issues).
