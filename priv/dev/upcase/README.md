# Upcase MCP Server

A simple MCP server that converts text to uppercase using the Hermes MCP library for both client and server.

## Description

This server provides a tool called `upcase` which takes a string parameter `text` and returns the uppercase version of that text.

## Building

```bash
cd priv/dev/upcase && mix assemble
```

## Running (needs Erlang on PATH)

```bash
./upcase
```

## Example client code

```elixir
# Initialize the client
{:ok, client} = Hermes.Client.start_link(transport: :stdio)

# List available tools
{:ok, %{"tools" => tools}} = Hermes.Client.list_tools(client)

# Call the upcase tool
{:ok, %{"content" => [%{"text" => result}]}} = 
  Hermes.Client.call_tool(client, "upcase", %{text: "Hello, World!"})

# Output: "HELLO, WORLD!"
IO.puts(result)
```
