# Message Handling

This guide explains how Hermes MCP handles the flow of messages between clients and servers, including request/response patterns, notifications, and error handling.

## Message Types

Hermes implements all the standard JSON-RPC 2.0 message types as defined in the MCP specification:

1. **Requests**: Messages with a method, parameters, and ID that expect a response
2. **Responses**: Successful results or errors matching a specific request ID
3. **Notifications**: One-way messages with no response expected

## Message Flow Architecture

```
┌────────────┐      ┌────────────┐      ┌────────────┐
│            │      │            │      │            │
│   Client   │<─────│  Transport │<─────│   Server   │
│            │─────>│            │─────>│            │
└────────────┘      └────────────┘      └────────────┘
```

1. The client sends requests and notifications to the transport layer
2. The transport delivers these messages to the server
3. The server processes messages and sends responses or notifications
4. The transport delivers these back to the client
5. The client correlates responses with their original requests

## Request/Response Correlation

Hermes automatically handles correlation between requests and responses using unique message IDs:

```elixir
# Inside Hermes.Client implementation
defp generate_request_id do
  binary = <<
    System.system_time(:nanosecond)::64,
    :erlang.phash2({node(), self()}, 16_777_216)::24,
    :erlang.unique_integer()::32
  >>

  Base.url_encode64(binary)
end
```

Each request is assigned a unique ID, and the client maintains a map of pending requests:

```elixir
# Simplified example of internal state
%{
  pending_requests: %{
    "request_id_123" => {from, "method_name"},
    "request_id_456" => {from, "other_method"}
  }
}
```

When a response arrives, it's matched to the original request and forwarded to the waiting process.

## Timeouts and Recovery

Hermes implements automatic timeout handling for requests:

```elixir
# Default timeout in milliseconds
@default_timeout :timer.seconds(30)
```

If a response isn't received within the timeout period, the client will:

1. Remove the request from the pending requests map
2. Send a cancellation notification to the server
3. Return an error to the caller

## Notification Handling

Notifications are one-way messages that don't expect a response. Hermes provides a simple API for sending notifications:

```elixir
# Internal implementation
defp send_notification(state, method, params \\ %{}) do
  with {:ok, notification_data} <- encode_notification(method, params) do
    send_to_transport(state.transport, notification_data)
  end
end
```

The client sends the `notifications/initialized` notification after successful initialization.

## Protocol Message Encoding/Decoding

Hermes uses a structured approach to encode and validate protocol messages.

The `Hermes.MCP.Message` module provides robust validation of all messages against the MCP schema

## Error Handling Patterns

Hermes implements standardized error handling for all message types:

### Protocol Errors

JSON-RPC protocol errors follow the standard error codes:

```elixir
# Example of handling an error response
defp handle_error(%{"error" => error, "id" => id}, id, state) do
  {{from, _method}, pending} = Map.pop(state.pending_requests, id)

  # Unblocks original caller
  GenServer.reply(from, {:error, error})

  %{state | pending_requests: pending}
end
```

### Transport Errors

Transport-level errors are wrapped in a standardized format:

```elixir
# Example of handling a transport error
defp send_to_transport(transport, data) do
  with {:error, reason} <- transport.send_message(data) do
    {:error, {:transport_error, reason}}
  end
end
```

### Application Errors

Application-level errors (e.g., in tool execution) are handled within the result structure:

```elixir
# Example result for a tool execution error
{:error, %{
  "content" => [%{"type" => "text", "text" => "Error message"}],
  "isError" => true
}}
```

## Rate Limiting Considerations

While Hermes does not impose rate limits directly, implementers should consider:

1. Batching requests when appropriate
2. Implementing backoff mechanisms for retries
3. Monitoring request volumes in production
