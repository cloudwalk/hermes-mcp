# OAuth Example MCP Server

This example demonstrates how to implement OAuth 2.1 authorization in a Hermes MCP server.

## Features

- OAuth 2.1 Bearer token authentication
- Scope-based authorization for tools and resources
- Mock token validator for testing
- Example tools, resources, and prompts that require authentication

## Running the Server

```bash
cd priv/dev/oauth_example
mix deps.get
mix run --no-halt
```

The server will start on port 4001 with the following endpoints:
- `/mcp` - MCP server endpoint (requires authentication)
- `/health` - Health check endpoint (no auth required)
- `/.well-known/oauth-protected-resource` - OAuth metadata endpoint

## Testing with Demo Tokens

The mock validator accepts these demo tokens:

- `demo_read_token` - Read-only access (scope: "read")
- `demo_write_token` - Read and write access (scope: "read write")
- `demo_admin_token` - Full admin access (scope: "read write admin")

### Example: Testing without authentication

```bash
# This will return a 401 Unauthorized
curl -X POST http://localhost:4001/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2025-03-26",
      "capabilities": {},
      "clientInfo": {
        "name": "test-client",
        "version": "1.0.0"
      }
    }
  }'
```

### Example: Testing with authentication

```bash
# Initialize with read-only token
curl -X POST http://localhost:4001/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer demo_read_token" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2025-03-26",
      "capabilities": {},
      "clientInfo": {
        "name": "test-client",
        "version": "1.0.0"
      }
    }
  }'
```

### Example: OAuth metadata discovery

```bash
# Get OAuth protected resource metadata
curl http://localhost:4001/.well-known/oauth-protected-resource
```

## Components

### Tools

- **secure_operation** - Demonstrates scope-based authorization
  - `read_data` - Requires authentication
  - `write_data` - Requires "write" scope
  - `admin_action` - Requires "admin" scope

### Resources

- **oauth://profile** - Returns authenticated user's profile (requires authentication)

### Prompts

- **auth_info** - Provides information about authentication status

## Real-World Implementation

To use this in a production environment:

1. Replace `MockValidator` with a real validator:
   - Use `Hermes.Server.Authorization.JWTValidator` for JWT tokens
   - Use `Hermes.Server.Authorization.IntrospectionValidator` for token introspection
   - Implement a custom validator for your auth system

2. Configure real authorization servers:
   ```elixir
   auth_config = [
     authorization_servers: ["https://your-auth-server.com"],
     jwks_uri: "https://your-auth-server.com/.well-known/jwks.json",
     audience: "https://your-api.com"
   ]
   ```

3. Implement proper error handling and logging

4. Add rate limiting and other security measures

