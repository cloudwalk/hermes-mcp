# Logging

Hermes MCP supports server-to-client logging as specified in the [MCP protocol](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/utilities/logging/). This allows servers to send structured log messages to clients for debugging and operational visibility.

## Overview

The logging mechanism follows the standard syslog severity levels and provides a way for servers to emit structured log messages. Clients can control the verbosity by setting minimum log levels, and register callbacks to handle log messages for custom processing.

## Setting Log Level

Clients can specify the minimum log level they want to receive from servers:

```elixir
# Configure the client to receive logs at "info" level or higher
{:ok, _} = MyApp.MCPClient.set_log_level("info")
```

Available log levels, in order of increasing severity:
- `"debug"` - Detailed information for debugging
- `"info"` - General information messages
- `"notice"` - Normal but significant events
- `"warning"` - Warning conditions
- `"error"` - Error conditions
- `"critical"` - Critical conditions
- `"alert"` - Action must be taken immediately
- `"emergency"` - System is unusable

Setting a level will result in receiving all messages at that level and above (more severe).

## Receiving Log Messages

### Registering Callbacks

You can register a callback function to process log messages as they are received:

```elixir
# Register a callback to handle incoming log messages
MyApp.MCPClient.register_log_callback(fn level, data, logger ->
  IO.puts("[#{level}] #{if logger, do: "[#{logger}] ", else: ""}#{inspect(data)}")
end)
```

The callback function receives:
- `level` - The log level (debug, info, notice, etc.)
- `data` - The log data (any JSON-serializable value)
- `logger` - Optional string identifying the logger source

### Unregistering Callbacks

When you no longer need to process log messages, unregister the callback:

```elixir
# Unregister a previously registered callback
MyApp.MCPClient.unregister_log_callback()
# :ok
```

## Integrating with Elixir's Logger

By default, Hermes MCP automatically logs received messages to `Logger` app, mapping MCP log levels to their Elixir equivalents:

- `"debug"` → `Logger.debug/1`
- `"info"`, `"notice"` → `Logger.info/1`
- `"warning"` → `Logger.warning/1`
- `"error"`, `"critical"`, `"alert"`, `"emergency"` → `Logger.error/1`

This provides seamless integration with your existing logging setup, respecting the logger level you
define con your config.
