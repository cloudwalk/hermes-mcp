# Message Handling

This guide explains how Hermes MCP handles the flow of messages between clients and servers, including request/response patterns, notifications, and error handling.

## Message Types

Hermes implements all the standard JSON-RPC 2.0 message types as defined in the [MCP specification](https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/messages/):

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

Hermes automatically handles correlation between requests and responses using unique message IDs that look like this:

```
req_gdc_yngatmpd1namcqk
```

Each request is assigned a unique ID, and the client maintains a `MapSet` of pending requests:

```elixir
# Simplified example of internal state
%{
  pending_requests: %{
    "request_id_123" => {from, "method_name"},
    "request_id_456" => {from, "other_method"}
  }
}
```

When a response arrives, it's matched to the original request and forwarded to the waiting caller process.

## Timeouts and Recovery

Hermes implements automatic timeout handling for requests:

If a response isn't received within the timeout period, the client will:

1. Remove the request from the pending requests map
2. Send a cancellation notification to the server
3. Return an error to the caller

## Notification Handling

Notifications are one-way messages that don't expect a response. Generally, client and server should exchange notifications internally, without involving an explicit call from the caller process.

However, there's one exception: request cancellation. When a client cancels a request with either `Hermes.Client.cancel_request/3` or `Hermes.Client.cancel_all_requests/2`, it sends a `notifications/cancelled` notification to the server to stop processing the request.

## Protocol Message Encoding/Decoding

Hermes uses a structured approach to encode and validate protocol messages.

The `Hermes.MCP.Message` module provides robust validation of all messages against the [MCP JSON schema](https://github.com/modelcontextprotocol/specification/blob/main/schema/2024-11-05/schema.json)
