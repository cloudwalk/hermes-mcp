# Logging

How does Hermes MCP handle the logging capabilities defined in the MCP protocol? Let's explore both the MCP logging features and how to configure Hermes's own internal logging.

## MCP Logging Capability

When building MCP clients, you'll often need to receive and process log messages from servers. How might you handle these structured messages in your Elixir application?

### Controlling Server Verbosity

```elixir
{:ok, _} = MyApp.MCPClient.set_log_level("info")
```

What happens behind the scenes? This sends a `logging/setLevel` request to the server, telling it to only send logs at "info" level or higher. The server will respect this preference when deciding which notifications to send your way.

### Processing Incoming Logs

Ever wondered how to handle those log notifications when they arrive? You have two approaches:

```elixir
# Register a custom handler
MyApp.MCPClient.register_log_callback(fn level, data, logger ->
  # Send to your monitoring service?
  # Transform the format?
  # Filter by logger name?
end)

# When done, clean up
MyApp.MCPClient.unregister_log_callback()
```

What's happening by default though? Hermes automatically forwards all MCP log messages to Elixir's Logger, mapping the levels appropriately. This means your existing log infrastructure just works - no additional setup required.

## Configuring Hermes Library Logs

Now, what about the logs that Hermes itself generates? How do you control the verbosity of the library's internal logging?

### Fine-Grained Control

```elixir
config :hermes_mcp, :logging,
  client_events: :info,
  server_events: :debug,
  transport_events: :warning,
  protocol_messages: :debug
```

What do these categories mean for your debugging experience?
- `client_events`: Client lifecycle and operations
- `server_events`: Server request handling and responses  
- `transport_events`: Connection and transport layer activity
- `protocol_messages`: Raw MCP message exchanges

### Global Toggle

Need to silence Hermes completely? Perhaps for performance testing or production deployments?

```elixir
config :hermes_mcp, log: false
```

This disables all library-emitted logs, regardless of individual category settings.

## MCP Server Logging

What if you're building an MCP server? How do you send logs to connected clients? Let's explore the server-side capabilities.

### Declaring Logging Support

```elixir
defmodule MyServer do
  use Hermes.Server,
    name: "my-server",
    version: "1.0.0",
    capabilities: [:logging]  # Enable logging capability
end
```

What does this capability tell clients? It signals that your server can receive `logging/setLevel` requests and will respect the client's verbosity preferences when sending log notifications.

### Sending Log Messages

How do you actually send logs from your server to clients? You have a straightforward API:

```elixir
# From within your server callbacks
send_log_message(server, "info", "Processing started", "worker")

# Or without a logger name
send_log_message(server, "error", "Connection failed")
```

What happens when you send these? They become `notifications/message` events that clients process according to their configured handlers. The client's minimum log level (set via `set_log_level/1`) filters what they receive.

### Progress Notifications

Need to report progress on long-running operations? How might this improve user experience?

```elixir
# Start an operation with progress tracking
send_progress(server, "import-123", 0, 100, "Starting import...")

# Update as you go
send_progress(server, "import-123", 45, 100, "Processing records...")

# Complete
send_progress(server, "import-123", 100, 100, "Import complete!")
```

## Practical Considerations

How might you configure logging for different environments? Consider starting with `:debug` everywhere during development, then adjusting based on what you learn:

- Keep `protocol_messages` at `:debug` unless debugging protocol issues
- Set `transport_events` to `:warning` once your transport is stable
- Use `:info` for client and server events in production

What patterns emerge from your logs? Which categories provide the most value for your use case?
