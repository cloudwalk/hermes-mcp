# ASCII Art Studio with Hermes MCP

A Phoenix LiveView application that generates ASCII art and exposes it via MCP (Model Context Protocol) using Hermes MCP.

## Features

- Generate ASCII art from text using 4 different fonts (Standard, Slant, 3D, Banner)
- Create simple text banners with borders
- Save generation history to database
- Delete unwanted art from history
- Copy ASCII art to clipboard
- Real-time generation stats
- MCP server integration for programmatic access

## Setup

```bash
mix deps.get
mix ecto.setup
mix phx.server
```

Visit http://localhost:4000 to use the web interface.

## MCP Integration

The app includes an MCP server that exposes ASCII art generation as a tool:

```elixir
# Start the MCP server
{:ok, _pid} = Ascii.MCPServer.start_link(transport: [layer: Hermes.Transport.STDIO])
```

Available MCP tools:
- `generate_ascii_art` - Generate ASCII art with specified text and font
- `list_fonts` - Get available font options

## Usage Example

```elixir
# Via MCP client
{:ok, client} = Hermes.Client.start_link(transport: [layer: Hermes.Transport.STDIO])
{:ok, result} = Hermes.Client.call_tool(client, "generate_ascii_art", %{
  text: "HELLO",
  font: "standard"
})
```

Built with Phoenix LiveView and Hermes MCP.