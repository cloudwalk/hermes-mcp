# API Reference

A quick reference for the most commonly used functions. Looking for more detailed examples? Check out our guides.

## Client API

### Module Definition

```elixir
use Hermes.Client, options
```

**Required Options:**

- `name` - Your client name (string)
- `version` - Your client version (string)
- `protocol_version` - MCP protocol version (string)
- `capabilities` - List of capabilities (atoms or tuples)

### Starting a Client

```elixir
{MyApp.Client, transport: transport_config}
```

**Transport Options:**

- `{:stdio, command: "cmd", args: ["arg1", "arg2"]}`
- `{:streamable_http, url: "http://localhost:8000/mcp"}`
- `{:websocket, url: "ws://localhost:8000/ws"}`
- `{:sse, base_url: "http://localhost:8000"}`

### Client Functions

All functions accept an optional process name as the first argument:

```elixir
# Default process
MyApp.Client.ping()

# Named process
MyApp.Client.ping(:my_client)
```

**Connection Management:**

- `ping/0,1` - Check if server is responsive
- `close/0,1` - Close the connection gracefully

**Discovery:**

- `get_server_info/0,1` - Get server information
- `get_server_capabilities/0,1` - Get server capabilities

**Tools:**

- `list_tools/0,1` - List available tools
- `call_tool/2,3,4` - Call a tool with arguments

**Resources:**

- `list_resources/0,1,2` - List available resources (supports pagination)
- `read_resource/1,2` - Read a specific resource

**Prompts:**

- `list_prompts/0,1,2` - List available prompts (supports pagination)
- `get_prompt/2,3` - Get a prompt with arguments

**Autocompletion:**

- `complete/2,3` - Get completion suggestions

### Options

Functions that make requests accept options:

- `timeout: milliseconds` - Request timeout (default: 30_000)

## Server API

### Module Definition

```elixir
use Hermes.Server, options
```

**Required Options:**

- `name` - Your server name (string)
- `version` - Your server version (string)
- `capabilities` - List of capabilities to expose

### Starting a Server

```elixir
{MyApp.Server, transport: transport_config}
```

**Transport Options:**

- `:stdio` - Standard input/output
- `{:streamable_http, port: 8080}` - HTTP server
- `:none` - No transport (for embedding)

### Server Callbacks

```elixir
@behaviour Hermes.Server.Behaviour

# Optional initialization
def init(arg, frame) do
  {:ok, frame}
end

# Handle incoming requests (optional)
def handle_request(request, frame) do
  {:reply, result, frame}
end

# Handle notifications (optional)
def handle_notification(notification, frame) do
  {:noreply, frame}
end
```

### Component Definition

#### Tools

```elixir
use Hermes.Server.Component, type: :tool

# Schema definition
schema do
  field :name, :string, required: true
  field :age, :integer, min: 0
end

# Execution callback
def execute(params, frame) do
  {:ok, result}  # or {:error, reason}
end
```

#### Resources

```elixir
use Hermes.Server.Component,
  type: :resource,
  uri: "resource://type/name"

# Read callback
def read(params, frame) do
  {:ok, content}  # or {:error, reason}
end
```

#### Prompts

```elixir
use Hermes.Server.Component, type: :prompt

# Schema for arguments
schema do
  field :context, :string
end

# Get messages callback
def get_messages(params, frame) do
  {:ok, [%{role: "user", content: "..."}]}
end
```

### Component Registration

```elixir
defmodule MyApp.Server do
  use Hermes.Server, ...

  # Register components
  component MyApp.MyTool
  component MyApp.MyResource
  component MyApp.MyPrompt
end
```

## Schema DSL

Available field types and validations:

```elixir
schema do
  field :string_field, :string,
    required: true,
    min_length: 1,
    max_length: 100,
    format: ~r/pattern/

  field :number_field, :number,
    min: 0,
    max: 100

  field :integer_field, :integer,
    min: 0

  field :boolean_field, :boolean,
    default: false

  field :enum_field, :string,
    values: ["option1", "option2"]

  field :array_field, {:array, :string},
    min_items: 1,
    max_items: 10

  field :map_field, :map
end
```

## Return Values

### Client Returns

Most client functions return:

- `{:ok, %{result: data}}` - Successful response
- `{:ok, %{is_error: true, result: error}}` - Tool-level error
- `{:error, reason}` - Protocol or connection error

### Server Returns

Component callbacks should return:

- `{:ok, result}` - Success with result
- `{:error, message}` - Error with message

Server callbacks return:

- `{:reply, result, frame}` - Reply with result
- `{:noreply, frame}` - No reply
- `{:stop, reason, frame}` - Stop the server

## Error Handling

Errors are automatically formatted according to MCP protocol. You can return:

- String error messages
- Error tuples
- Exceptions (will be caught and formatted)

## Useful Mix Tasks

**Interactive Testing:**

- `mix hermes.stdio.interactive Module` - Test with STDIO
- `mix hermes.streamable_http.interactive Module` - Test with HTTP

**Development:**

- `mix compile --force` - Recompile all components
- `mix test` - Run tests

## Need More?

This reference covers the essential API. For detailed examples and patterns:

- [Building a Client](building-a-client.md)
- [Building a Server](building-a-server.md)
- [Recipes](recipes.md)

Remember: the protocol complexity is handled for you. Focus on what your application does best.
