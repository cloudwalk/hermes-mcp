# Error Handling

This guide explains how errors work in Hermes MCP.

## Error Types

Hermes distinguishes between:

1. **Protocol errors** - Standard JSON-RPC errors
2. **Domain errors** - Application-level errors (tool returns `isError: true`)
3. **Transport errors** - Network/connection failures

## Creating Errors

Hermes provides a fluent API for creating errors:

```elixir
# Protocol errors
Hermes.MCP.Error.protocol(:parse_error)
Hermes.MCP.Error.protocol(:method_not_found, %{method: "unknown"})

# Transport errors
Hermes.MCP.Error.transport(:connection_refused)
Hermes.MCP.Error.transport(:timeout, %{elapsed_ms: 30000})

# Resource errors
Hermes.MCP.Error.resource(:not_found, %{uri: "file:///missing.txt"})

# Execution errors
Hermes.MCP.Error.execution("Database connection failed", %{retries: 3})
```

## Error Structure

All errors have:
- `code` - JSON-RPC error code
- `reason` - Semantic atom (e.g., `:method_not_found`)
- `message` - Human-readable message
- `data` - Additional context map

## Handling Client Responses

```elixir
case MyApp.MCPClient.call_tool("search", %{query: "test"}) do
  # Success
  {:ok, %Hermes.MCP.Response{is_error: false, result: result}} ->
    IO.puts("Success: #{inspect(result)}")

  # Domain error (tool returned isError: true)
  {:ok, %Hermes.MCP.Response{is_error: true, result: result}} ->
    IO.puts("Tool error: #{result["message"]}")

  # Protocol/transport error
  {:error, %Hermes.MCP.Error{reason: reason}} ->
    IO.puts("Error: #{reason}")
end
```

## Common Error Patterns

### Timeout Handling

```elixir
# Set custom timeout (default is 30 seconds)
case MyApp.MCPClient.call_tool("slow_tool", %{}, timeout: 60_000) do
  {:error, %Hermes.MCP.Error{reason: :timeout}} ->
    IO.puts("Request timed out")
  
  other ->
    handle_response(other)
end
```

### Transport Errors

```elixir
{:error, %Hermes.MCP.Error{reason: reason}} when reason in [
  :connection_refused,
  :connection_closed,
  :timeout
] ->
  # Handle network issues
```

### Method Not Found

```elixir
{:error, %Hermes.MCP.Error{reason: :method_not_found}} ->
  # Server doesn't support this method
```

## Error Codes

Standard JSON-RPC codes:
- `-32700` - Parse error
- `-32600` - Invalid request
- `-32601` - Method not found
- `-32602` - Invalid params
- `-32603` - Internal error

MCP-specific:
- `-32002` - Resource not found
- `-32000` - Generic server error

## Debugging

Errors have clean inspect output:

```
#MCP.Error<timeout: Timeout %{elapsed_ms: 30000}>
#MCP.Error<method_not_found: Method not found>
```
