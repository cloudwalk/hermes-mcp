# Progress Tracking

Hermes MCP supports progress notifications for long-running operations as specified in the MCP protocol.

## Overview

The MCP specification includes a progress notification mechanism that allows communicating the progress of long-running operations. Progress updates are useful for:

- Providing feedback for long-running server operations
- Updating users about the status of operations that might take time to complete
- Enabling client applications to display progress indicators for better UX

## Progress Tokens

Progress is tracked using tokens that uniquely identify a specific operation. Hermes provides a helper function to generate unique tokens:

```elixir
# Generate a unique progress token
progress_token = Hermes.Message.generate_progress_token()
```

## Making Requests with Progress Tracking

Any request can include a progress token to indicate you want to track progress:

```elixir
# Make a request with progress tracking
Hermes.Client.read_resource(client, "resource-uri", 
  progress: [token: progress_token]
)
```

## Receiving Progress Updates

### Method 1: Register a Callback Function

Before making the request, register a callback function to be called when progress notifications arrive:

```elixir
# Register a callback for a specific progress token
Hermes.Client.register_progress_callback(client, progress_token, 
  fn token, progress, total ->
    percentage = if total, do: progress / total * 100, else: nil
    IO.puts("Operation #{token} progress: #{progress}/#{total || "unknown"} (#{percentage || "unknown"}%)")
  end
)
```

### Method 2: Provide a Callback with the Request

You can combine the token and callback in a single request:

```elixir
# Combined approach: request with progress token and callback
Hermes.Client.list_tools(client, 
  progress: [
    token: progress_token,
    callback: fn token, progress, total ->
      # Handle progress updates
      IO.puts("Progress: #{progress}/#{total || "unknown"}")
    end
  ]
)
```

## Sending Progress Updates (Server Implementation)

When implementing server-side functionality, you can send progress updates to clients:

```elixir
# Send a progress update to clients
Hermes.Client.send_progress(client, progress_token, 50, 100)
```

## Cleanup

To avoid memory leaks, unregister callbacks when you're no longer interested in progress updates:

```elixir
# Unregister a progress callback
Hermes.Client.unregister_progress_callback(client, progress_token)
```

## Complete Example

```elixir
defmodule MyApp.LongRunningOperation do
  def execute_with_progress(client) do
    # Generate a unique token
    progress_token = Hermes.Message.generate_progress_token()
    
    # Register a callback to handle progress updates
    Hermes.Client.register_progress_callback(client, progress_token, fn _token, progress, total ->
      if total do
        percentage = Float.round(progress / total * 100, 1)
        IO.puts("Progress: #{progress}/#{total} (#{percentage}%)")
      else
        IO.puts("Progress: #{progress}/unknown")
      end
    end)
    
    # Make the request with the progress token
    result = Hermes.Client.call_tool(client, "long-running-operation", %{}, 
      progress: [token: progress_token]
    )
    
    # Cleanup by unregistering the callback
    Hermes.Client.unregister_progress_callback(client, progress_token)
    
    # Return the result
    result
  end
end
```

## Using Progress within Phoenix LiveView

Progress tracking is particularly useful in interactive web applications:

```elixir
defmodule MyAppWeb.ProcessLive do
  use Phoenix.LiveView
  
  def mount(_params, _session, socket) do
    {:ok, assign(socket, progress: 0, total: 100, running: false)}
  end
  
  def handle_event("start_process", _params, socket) do
    token = Hermes.Message.generate_progress_token()
    
    # Register progress callback
    Hermes.Client.register_progress_callback(MyApp.Client, token, fn _token, progress, total ->
      send(self(), {:progress_update, progress, total})
    end)
    
    # Start the operation asynchronously
    Task.start(fn ->
      result = Hermes.Client.call_tool(MyApp.Client, "long-running-operation", %{},
        progress: [token: token]
      )
      Hermes.Client.unregister_progress_callback(MyApp.Client, token)
      send(self(), {:operation_complete, result})
    end)
    
    {:noreply, assign(socket, running: true)}
  end
  
  def handle_info({:progress_update, progress, total}, socket) do
    {:noreply, assign(socket, progress: progress, total: total || 100)}
  end
  
  def handle_info({:operation_complete, result}, socket) do
    {:noreply, assign(socket, running: false, result: result)}
  end
  
  def render(assigns) do
    ~H"""
    <div>
      <button :if={!@running} phx-click="start_process">Start Process</button>
      
      <div :if={@running} class="progress-bar">
        <div class="progress" style={"width: #{@progress / @total * 100}%"}></div>
        <span><%= @progress %>/<%= @total %></span>
      </div>
      
      <div :if={@result}>
        <h3>Result:</h3>
        <pre><%= inspect(@result) %></pre>
      </div>
    </div>
    """
  end
end
```

This feature enables applications to provide rich, interactive feedback during long-running operations, enhancing the user experience.