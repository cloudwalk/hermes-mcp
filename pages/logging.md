# Logging

Hermes MCP supports server-to-client logging as specified in the MCP protocol. This allows servers to send structured log messages to clients for debugging and operational visibility.

## Overview

The logging mechanism follows the standard syslog severity levels and provides a way for servers to emit structured log messages. Clients can control the verbosity by setting minimum log levels, and register callbacks to handle log messages for custom processing.

## Setting Log Level

Clients can specify the minimum log level they want to receive from servers:

```elixir
# Configure the client to receive logs at "info" level or higher
{:ok, _} = Hermes.Client.set_log_level(client, "info")
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
Hermes.Client.register_log_callback(client, fn level, data, logger ->
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
Hermes.Client.unregister_log_callback(client, callback_function)
```

## Integrating with Elixir's Logger

By default, Hermes MCP automatically logs received messages to Elixir's Logger system, mapping MCP log levels to their Elixir equivalents:

- `"debug"` → `Logger.debug/1`
- `"info"`, `"notice"` → `Logger.info/1`
- `"warning"` → `Logger.warning/1`
- `"error"`, `"critical"`, `"alert"`, `"emergency"` → `Logger.error/1`

This provides seamless integration with your existing logging setup.

## Example Use Case: LiveView Integration

Here's an example of using logging in a Phoenix LiveView application:

```elixir
defmodule MyAppWeb.LogsLive do
  use Phoenix.LiveView
  
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Register a callback to handle log messages
      Hermes.Client.register_log_callback(MyApp.Client, &handle_log/3)
    end
    
    # Set a higher log level initially
    Hermes.Client.set_log_level(MyApp.Client, "info")
    
    {:ok, assign(socket, logs: [], log_level: "info")}
  end
  
  def handle_event("set_log_level", %{"level" => level}, socket) do
    # Change the logging level based on user selection
    Hermes.Client.set_log_level(MyApp.Client, level)
    
    {:noreply, assign(socket, log_level: level)}
  end
  
  # Callback for log messages
  defp handle_log(level, data, logger) do
    send(self(), {:new_log, level, data, logger, DateTime.utc_now()})
  end
  
  def handle_info({:new_log, level, data, logger, timestamp}, socket) do
    log_entry = %{
      level: level,
      data: data,
      logger: logger,
      timestamp: timestamp
    }
    
    # Keep the most recent 100 logs
    logs = [log_entry | socket.assigns.logs] |> Enum.take(100)
    
    {:noreply, assign(socket, logs: logs)}
  end
  
  def render(assigns) do
    ~H"""
    <div>
      <div class="controls">
        <form phx-change="set_log_level">
          <label>Log Level:</label>
          <select name="level">
            <option value="debug" selected={@log_level == "debug"}>Debug</option>
            <option value="info" selected={@log_level == "info"}>Info</option>
            <option value="warning" selected={@log_level == "warning"}>Warning</option>
            <option value="error" selected={@log_level == "error"}>Error</option>
            <option value="critical" selected={@log_level == "critical"}>Critical</option>
          </select>
        </form>
      </div>
      
      <div class="log-container">
        <table>
          <thead>
            <tr>
              <th>Time</th>
              <th>Level</th>
              <th>Source</th>
              <th>Message</th>
            </tr>
          </thead>
          <tbody>
            <%= for log <- @logs do %>
              <tr class={"log-level-#{log.level}"}>
                <td><%= Calendar.strftime(log.timestamp, "%H:%M:%S") %></td>
                <td><%= log.level %></td>
                <td><%= log.logger || "-" %></td>
                <td><%= inspect(log.data) %></td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
  
  def terminate(_reason, _socket) do
    # Clean up by unregistering the callback
    Hermes.Client.unregister_log_callback(MyApp.Client, &handle_log/3)
    :ok
  end
end
```

This example demonstrates:
1. Setting an initial log level
2. Allowing users to change the log level
3. Receiving and displaying logs in real-time
4. Properly cleaning up when the LiveView terminates

## Server-side Recommendations

For developers implementing MCP servers, the MCP specification recommends:

1. **Rate limiting** - Limit the volume of log messages to avoid overwhelming clients
2. **Structured context** - Include relevant context in the data field
3. **Consistent naming** - Use consistent logger names for categorization
4. **Sensitive information** - Never include credentials, PII, or security-sensitive information in logs

## Security Considerations

When implementing MCP clients and servers, be careful about logging sensitive information. The MCP specification explicitly recommends against including credentials, PII, or sensitive system details in log messages.