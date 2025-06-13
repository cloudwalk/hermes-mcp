# Client Usage

Using the Hermes MCP client with the new DSL.

## Basic Setup

Once your client module is defined and added to the supervision tree, it automatically:
- Connects to the server
- Negotiates protocol version
- Exchanges capabilities
- Completes handshake

## Connection Status

```elixir
# Using your client module directly
case MyApp.MCPClient.ping() do
  :pong -> 
    IO.puts("Server is responsive")
  
  {:error, reason} -> 
    IO.puts("Connection error: #{inspect(reason)}")
end
```

## Server Information

```elixir
# Get capabilities
capabilities = MyApp.MCPClient.get_server_capabilities()

# Get server info
info = MyApp.MCPClient.get_server_info()
```

## Working with Tools

### List Tools

```elixir
case MyApp.MCPClient.list_tools() do
  {:ok, %{result: %{"tools" => tools}}} ->
    for tool <- tools do
      IO.puts("#{tool["name"]}: #{tool["description"]}")
    end

  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end
```

### Call Tool

```elixir
case MyApp.MCPClient.call_tool("calculator", %{expr: "2+2"}) do
  {:ok, %{is_error: false, result: result}} ->
    IO.puts("Result: #{inspect(result)}")

  {:ok, %{is_error: true, result: error}} ->
    IO.puts("Tool error: #{error["message"]}")

  {:error, error} ->
    IO.puts("Protocol error: #{inspect(error)}")
end
```

## Working with Resources

### List Resources

```elixir
{:ok, %{result: %{"resources" => resources}}} = 
  MyApp.MCPClient.list_resources()

for resource <- resources do
  IO.puts("#{resource["name"]} (#{resource["uri"]})")
end
```

### Read Resource

```elixir
case MyApp.MCPClient.read_resource("file:///data.txt") do
  {:ok, %{result: %{"contents" => contents}}} ->
    for content <- contents do
      case content do
        %{"text" => text} -> IO.puts(text)
        %{"blob" => blob} -> IO.puts("Binary: #{byte_size(blob)} bytes")
      end
    end

  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end
```

### Pagination

```elixir
# First page
{:ok, %{result: result}} = MyApp.MCPClient.list_resources()
resources = result["resources"]
cursor = result["nextCursor"]

# Next page
if cursor do
  {:ok, %{result: more}} = 
    MyApp.MCPClient.list_resources(cursor: cursor)
end
```

## Working with Prompts

### List Prompts

```elixir
{:ok, %{result: %{"prompts" => prompts}}} = 
  MyApp.MCPClient.list_prompts()

for prompt <- prompts do
  IO.puts("#{prompt["name"]}: #{prompt["description"]}")
end
```

### Get Prompt

```elixir
args = %{"language" => "elixir", "task" => "refactor"}

case MyApp.MCPClient.get_prompt("code_review", args) do
  {:ok, %{result: %{"messages" => messages}}} ->
    for msg <- messages do
      IO.puts("#{msg["role"]}: #{msg["content"]}")
    end

  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end
```

## Timeouts

Set custom timeouts per operation:

```elixir
# 60 second timeout
opts = [timeout: 60_000]
MyApp.MCPClient.call_tool("slow_tool", %{}, opts)
```

Default timeout is 30 seconds.

## Autocompletion

Get completion suggestions:

```elixir
# For prompt arguments
ref = %{"type" => "ref/prompt", "name" => "code_review"}
arg = %{"name" => "language", "value" => "py"}

{:ok, response} = MyApp.MCPClient.complete(ref, arg)
# => ["python", "pytorch", "pydantic"]

# For resource URIs
ref = %{"type" => "ref/resource", "uri" => "file:///"}
arg = %{"name" => "path", "value" => "doc"}

{:ok, response} = MyApp.MCPClient.complete(ref, arg)
# => ["docs/", "docker-compose.yml", "documentation.md"]
```

## Error Handling

See [Error Handling](error_handling.md) for patterns.

## Graceful Shutdown

```elixir
MyApp.MCPClient.close()
```

This also shuts down the transport.

## Advanced Usage

### Multiple Client Instances

You can run multiple instances of the same client with different names:

```elixir
# In your supervision tree
children = [
  {MyApp.MCPClient, 
   name: :client_one,
   transport: {:stdio, command: "server1", args: []}},
  {MyApp.MCPClient, 
   name: :client_two,
   transport: {:stdio, command: "server2", args: []}}
]

# Use specific instances
MyApp.MCPClient.ping(:client_one)
MyApp.MCPClient.ping(:client_two)
```

### Custom Process Naming

For distributed systems using registries like Horde:

```elixir
{MyApp.MCPClient,
 name: {:via, Horde.Registry, {MyCluster, "client_1"}},
 transport_name: {:via, Horde.Registry, {MyCluster, "transport_1"}},
 transport: {:stdio, command: "server", args: []}}
```

### Manual Client Setup (Advanced)

For advanced use cases, you can manually start the client base and transport:

```elixir
# Start client first (it will hibernate waiting for transport)
{:ok, client_pid} = Hermes.Client.Base.start_link(
  name: :my_client,
  transport: [
    layer: Hermes.Transport.STDIO,
    name: :my_transport
  ],
  client_info: %{
    "name" => "MyApp",
    "version" => "1.0.0"
  },
  capabilities: %{
    "roots" => %{"listChanged" => true},
    "sampling" => %{}
  },
  protocol_version: "2024-11-05"
)

# Then start the transport (it will send :initialize to the client)
{:ok, transport_pid} = Hermes.Transport.STDIO.start_link(
  name: :my_transport,
  client: :my_client,
  command: "python",
  args: ["-m", "mcp.server"]
)

# Use the client
:pong = Hermes.Client.Base.ping(:my_client)
{:ok, tools} = Hermes.Client.Base.list_tools(:my_client)
```

> #### Important {: .warning}
>
> The client must be started before the transport. The client process will hibernate 
> waiting for the `:initialize` message from the transport process. The client name 
> in the transport configuration must match the actual client process name.
