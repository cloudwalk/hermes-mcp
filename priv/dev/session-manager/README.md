# Session Manager MCP Server

A minimal TypeScript MCP server implementation with session management using the streamable HTTP transport.

## Features

- Session-based state management
- Streamable HTTP transport with proper session handling
- Example tools demonstrating session persistence
- TypeScript with full type safety
- Built with official @modelcontextprotocol/sdk

## Installation

```bash
npm install
```

## Running the Server

```bash
# Development mode with hot reload
npm run dev

# Production build
npm run build
npm start
```

## Architecture

The server implements:

- **Session Management**: Each client connection gets a unique session ID
- **Stateful Tools**: Tools can store and retrieve session-specific data
- **Streamable HTTP Transport**: Uses Express with proper session isolation
- **Clean Lifecycle**: Automatic session cleanup on disconnect

## Tools

1. **session_info**: Get current session information
   - Returns session ID, creation time, last access time, and data size

2. **store_value**: Store a value in the session
   - Parameters: `key` (string), `value` (any JSON-serializable type)
   - Stores key-value pairs in the session

3. **get_value**: Retrieve a value from the session
   - Parameters: `key` (string)
   - Returns the stored value or indicates if not found

4. **increment_counter**: Increment a session-specific counter
   - Parameters: `counterName` (optional string, defaults to "default")
   - Maintains separate counters per session

## Testing

The server uses the MCP session ID header for session management:

```bash
# Initialize connection (will return a session ID in the response headers)
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-client","version":"1.0.0"}},"id":1}'

# Use the returned session ID for subsequent requests
SESSION_ID="<session-id-from-response>"

# List available tools
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":2}'

# Call a tool
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"session_info","arguments":{}},"id":3}'
```

## Session Lifecycle

1. **Session Creation**: Sessions are created on first `initialize` request
2. **Session Persistence**: Session data persists across requests with the same session ID
3. **Session Cleanup**: Sessions are automatically cleaned up after 30 minutes of inactivity
4. **Session Termination**: Sessions can be explicitly terminated with a DELETE request
