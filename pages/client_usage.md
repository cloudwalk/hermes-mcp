# Client Usage

Using the Hermes MCP client.

## Basic Setup

Once configured in your supervision tree, the client automatically:
- Connects to the server
- Negotiates protocol version
- Exchanges capabilities
- Completes handshake

## Connection Status

```elixir
case Hermes.Client.ping(client) do
  :pong -> 
    IO.puts("Server is responsive")
  
  {:error, reason} -> 
    IO.puts("Connection error: #{inspect(reason)}")
end
```

## Server Information

```elixir
# Get capabilities
capabilities = Hermes.Client.get_server_capabilities(client)

# Get server info
info = Hermes.Client.get_server_info(client)
```

## Working with Tools

### List Tools

```elixir
case Hermes.Client.list_tools(client) do
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
case Hermes.Client.call_tool(client, "calculator", %{expr: "2+2"}) do
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
  Hermes.Client.list_resources(client)

for resource <- resources do
  IO.puts("#{resource["name"]} (#{resource["uri"]})")
end
```

### Read Resource

```elixir
case Hermes.Client.read_resource(client, "file:///data.txt") do
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
{:ok, %{result: result}} = Hermes.Client.list_resources(client)
resources = result["resources"]
cursor = result["nextCursor"]

# Next page
if cursor do
  {:ok, %{result: more}} = 
    Hermes.Client.list_resources(client, cursor: cursor)
end
```

## Working with Prompts

### List Prompts

```elixir
{:ok, %{result: %{"prompts" => prompts}}} = 
  Hermes.Client.list_prompts(client)

for prompt <- prompts do
  IO.puts("#{prompt["name"]}: #{prompt["description"]}")
end
```

### Get Prompt

```elixir
args = %{"language" => "elixir", "task" => "refactor"}

case Hermes.Client.get_prompt(client, "code_review", args) do
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
Hermes.Client.call_tool(client, "slow_tool", %{}, opts)
```

Default timeout is 30 seconds.

## Autocompletion

Get completion suggestions:

```elixir
# For prompt arguments
ref = %{"type" => "ref/prompt", "name" => "code_review"}
arg = %{"name" => "language", "value" => "py"}

{:ok, response} = Hermes.Client.complete(client, ref, arg)
# => ["python", "pytorch", "pydantic"]

# For resource URIs
ref = %{"type" => "ref/resource", "uri" => "file:///"}
arg = %{"name" => "path", "value" => "doc"}

{:ok, response} = Hermes.Client.complete(client, ref, arg)
# => ["docs/", "docker-compose.yml", "documentation.md"]
```

## Error Handling

See [Error Handling](error_handling.md) for patterns.

## Graceful Shutdown

```elixir
Hermes.Client.close(client)
```

This also shuts down the transport.
