# Message Handling

How Hermes handles MCP protocol messages.

## Message Types

MCP uses JSON-RPC 2.0 with three message types:

1. **Requests** - Expect a response (have ID)
2. **Responses** - Reply to requests (match ID)
3. **Notifications** - One-way messages (no ID)

## Message Flow

```
Client ──request──> Transport ──> Server
       <─response── Transport <── 
```

## Message Encoding

Use `Hermes.MCP.Message` for all message operations:

```elixir
# Encode request
{:ok, encoded} = Message.encode_request(%{
  method: "tools/call",
  params: %{name: "calculator", arguments: %{}}
}, "req_123")

# Encode response
{:ok, encoded} = Message.encode_response(%{
  result: %{answer: 42}
}, "req_123")

# Encode notification
{:ok, encoded} = Message.encode_notification(%{
  method: "cancelled",
  params: %{requestId: "req_123"}
})

# Decode any message
{:ok, [decoded]} = Message.decode(json_string)
```

## Message Guards

Check message types:

```elixir
case decoded do
  msg when Message.is_request(msg) ->
    handle_request(msg)
  
  msg when Message.is_response(msg) ->
    handle_response(msg)
    
  msg when Message.is_notification(msg) ->
    handle_notification(msg)
end
```

## Request IDs

Hermes generates unique request IDs:

```elixir
id = Hermes.MCP.ID.generate_request_id()
# => "req_hyp_abcd1234efgh5678"
```

## Timeouts

Requests timeout after 30 seconds by default:

```elixir
# Custom timeout
Hermes.Client.call_tool(client, "slow_tool", %{}, timeout: 60_000)
```

On timeout:
1. Request removed from pending
2. Cancellation sent to server
3. Error returned to caller

## Common Patterns

### Client Side

```elixir
# The client handles correlation automatically
{:ok, response} = Hermes.Client.call_tool(client, "tool", %{})
```

### Server Side

```elixir
def handle_request(%{"method" => method, "id" => id}, frame) do
  result = process_method(method)
  {:reply, result, frame}
end

def handle_notification(%{"method" => "cancelled"}, frame) do
  # Cancel any running operation
  {:noreply, frame}
end
```
