# MCP Protocol Upgrade Guide: 2024-11-05 to 2025-03-26

This guide documents the major changes between MCP specification versions 2024-11-05 and 2025-03-26, 
and outlines a roadmap for upgrading Hermes MCP to support the new version while maintaining 
backward compatibility.

## Protocol Version Comparison

### Major Changes

| Feature | 2024-11-05 | 2025-03-26 | Impact |
|---------|------------|------------|--------|
| Authorization | Not present | Comprehensive OAuth 2.1 based framework | Major addition |
| HTTP Transport | HTTP+SSE (separate endpoints) | Streamable HTTP (single endpoint) | Breaking change |
| Batching | Not supported | JSON-RPC batching supported | New capability |
| Tool Annotations | Basic metadata | Comprehensive annotations (read-only, destructive, etc.) | Enhancement |
| Audio Content | Not supported | Supported alongside text and image | New capability |
| Progress Updates | Basic progress info | Added descriptive message field | Enhancement |
| Completions | Implicit | Explicit capability | Enhancement |

### Breaking Changes Details

#### 1. Authorization Framework

The 2025-03-26 specification introduces a comprehensive OAuth 2.1 based authorization framework including:

- Server Metadata Discovery (RFC8414)
- Dynamic Client Registration Protocol (RFC7591)
- Session management via headers
- Support for different OAuth grant types

This primarily impacts HTTP-based transports and doesn't apply to STDIO connections.

#### 2. Streamable HTTP Transport

The new transport replaces separate SSE and HTTP endpoints with a single "MCP endpoint" that supports:

- Both GET and POST methods
- Response content negotiation
- Session management via `Mcp-Session-Id` header
- Stream resumability with the `Last-Event-ID` header

This is a significant change to the transport layer architecture and requires careful implementation to maintain backward compatibility.

#### 3. JSON-RPC Batching

The 2025-03-26 specification adds support for JSON-RPC batching, allowing multiple requests to be sent and received in a single operation. This affects:

- Message encoding/decoding
- Request tracking
- Error handling

## Upgrading Roadmap

### Phase 1: Preparation and Compatibility Layer

1. **Implement Protocol Version Detection and Negotiation**
   - Enhance `Hermes.Client` to handle multiple protocol versions
   - Implement version-specific capabilities handling

2. **Transport Layer Compatibility**
   - Maintain `Hermes.Transport.SSE` for 2024-11-05
   - Create new transport for 2025-03-26 Streamable HTTP protocol
   - Ensure graceful backwards compatibility

3. **Message Handling Updates**
   - Update message handling to support both protocol versions
   - Add structures to handle version-specific features

### Phase 2: Core Feature Implementation

1. **Implement Streamable HTTP Transport**
   - Develop new transport implementation based on the spec
   - Support both content types (application/json and text/event-stream)
   - Implement session management
   - Add stream resumability

2. **Add Authorization Support**
   - Implement OAuth 2.1 support for HTTP transport
   - Add Server Metadata Discovery
   - Support Dynamic Client Registration
   - Handle token management and refresh

3. **Add JSON-RPC Batching**
   - Enhance Message module to handle batched messages
   - Update client API to support batched operations
   - Implement state tracking for batched requests

4. **Implement Tool Annotations**
   - Update tool handling to support detailed annotations
   - Add helper functions for checking tool properties

### Phase 3: API Enhancements and Documentation

1. **Enhance Client API**
   - Add explicit completions support
   - Update progress notifications to include message field
   - Support audio content type

2. **Refine Backward Compatibility**
   - Ensure seamless operation with both protocol versions
   - Implement auto-detection where possible
   - Add migration helpers

3. **Update Documentation**
   - Document new features and API changes
   - Provide migration guides for users

## API Impact Analysis

### Minimal-Impact Changes

These changes should have little or no impact on the existing API:

- Tool annotations
- Audio content
- Message field for progress
- Completions capability

### Potential Breaking Changes

#### Authorization

The authorization flow will require new parameters and client setup:

```elixir
# Current client initialization
Hermes.Client.start_link(
  name: :mcp_client,
  transport: [layer: Hermes.Transport.SSE],
  client_info: %{"name" => "MyClient", "version" => "1.0.0"}
)

# With authorization (conceptual)
Hermes.Client.start_link(
  name: :mcp_client,
  transport: [
    layer: Hermes.Transport.HTTP,
    auth: [
      client_id: "client_id",
      redirect_uri: "http://localhost:8000/callback",
      auth_callback: &MyApp.handle_auth_flow/1
    ]
  ],
  client_info: %{"name" => "MyClient", "version" => "1.0.0"}
)
```

#### Transport Layer

Users explicitly using `Hermes.Transport.SSE` will need to update to the new transport or use a compatibility mechanism.

### Backward Compatibility Considerations

1. **Protocol Version Negotiation**
   - Allow clients to specify preferred protocol versions
   - Automatically negotiate based on server capabilities
   - Fallback gracefully to supported versions

2. **Transport Abstraction**
   - Keep transport implementation details internal where possible
   - Use polymorphic behavior through protocols or behaviors

3. **Gradual Deprecation Path**
   - Mark 2024-11-05 specific features as deprecated
   - Provide clear migration path in documentation
   - Eventually remove deprecated features in a future major version

## Conclusion

The upgrade to MCP 2025-03-26 introduces significant changes, particularly around transport and authorization. 
By using a phased approach with careful abstractions, we can implement these changes while maintaining 
backward compatibility.

The most challenging aspects will be:

1. Supporting both transport models simultaneously
2. Implementing the OAuth flow in a user-friendly way
3. Managing the increased complexity of version-specific code paths

This document will be updated as implementation progresses with more specific details and examples.