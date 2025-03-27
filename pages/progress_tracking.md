# Progress Tracking

Hermes MCP supports progress notifications for long-running operations as specified in the [MCP protocol](https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/utilities/progress/).

## Overview

The MCP specification includes a progress notification mechanism that allows communicating the progress of long-running operations. Progress updates are useful for:

- Providing feedback for long-running server operations
- Updating users about the status of operations that might take time to complete
- Enabling client applications to display progress indicators for better UX

## Progress Tokens

Progress is tracked using tokens that uniquely identify a specific operation. Hermes provides a helper function to generate unique tokens:

```elixir
# Generate a unique progress token
progress_token = Hermes.MCP.ID.generate_progress_token()
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

You can combine the token and callback in a single request:

```elixir
token = Hermes.MCP.ID.generate_progress_token()

callback = fn ^token, progress, total ->
  IO.puts("Progress: #{progress}/#{total || "unknown"}")
end

Hermes.Client.list_tools(client, progress: [token: token, callback: callback])
```
