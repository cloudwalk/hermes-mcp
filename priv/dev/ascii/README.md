# ASCII Art Studio with Hermes MCP

A Phoenix LiveView application that bridges interactive web experiences with programmatic MCP access, demonstrating how modern Elixir applications can serve multiple audiences through unified business logic.

## The Convergence of Web and AI

How do you build an application that's equally accessible to humans through a rich UI and to AI assistants through structured APIs? The ASCII Art Studio explores this challenge by implementing a dual-interface architecture where Phoenix LiveView powers the human experience while Hermes MCP enables programmatic access.

## Architecture Overview

The application demonstrates a clean separation between interface layers and core business logic. At its heart, the `Ascii.ArtGenerator` module handles all ASCII art generation, while two distinct interfaces—LiveView and MCP—provide access to this functionality. This pattern ensures consistency regardless of how users interact with the system.

### Core Components

**Business Logic Layer**

The `ArtGenerator` module encapsulates font rendering and banner creation logic. By keeping this separate from both web and MCP layers, we ensure that improvements to the generation algorithms benefit all consumers equally.

**Phoenix LiveView Interface**

The web interface (`AsciiWeb.AsciiLive`) provides real-time ASCII art generation with a modern, interactive experience. Users see their text transform instantly as they type, with smooth animations and a glassmorphic design that makes the technical process feel approachable.

**MCP Server Interface**

The MCP server (`Ascii.MCPServer`) exposes the same capabilities through a structured API, enabling AI assistants and automation tools to generate ASCII art programmatically.

## MCP Implementation Details

The server implements three carefully designed tools that balance simplicity with functionality:

### Tool: `text_to_ascii`

Converts text to ASCII art using various fonts. The implementation automatically persists results to the database, creating a shared history between web and MCP interfaces.

```elixir
# Generate ASCII art via MCP
{:ok, result} = Hermes.Client.call_tool(client, "text_to_ascii", %{
  text: "HELLO",
  font: "3d"  # Options: standard, slant, 3d, banner
})
```

### Tool: `list_fonts`

Returns available font options with descriptions. This meta-tool helps clients discover capabilities without hardcoding font names.

```elixir
# Discover available fonts
{:ok, %{"fonts" => fonts}} = Hermes.Client.call_tool(client, "list_fonts", %{})
```

### Tool: `generate_banner`

Creates text banners with customizable borders. The width parameter (20-100 characters) allows clients to generate banners that fit their display constraints.

```elixir
# Create a bordered banner
{:ok, banner} = Hermes.Client.call_tool(client, "generate_banner", %{
  text: "Welcome",
  width: 50
})
```

## Transport Configuration

The server uses StreamableHTTP transport, making it accessible via standard HTTP protocols:

```elixir
# Application supervisor configuration
children = [
  Hermes.Server.Registry,
  {Ascii.MCPServer, transport: {:streamable_http, []}}
]

# Router configuration exposes the endpoint
forward "/mcp", StreamableHTTP.Plug, server: Ascii.MCPServer
```

This approach enables deployment flexibility—you can run the server behind load balancers, in containers, or as part of larger Phoenix applications.

## Database Integration and Persistence

What makes this implementation particularly interesting is the shared state between interfaces. The Ecto-backed persistence layer means that:

- ASCII art generated via the web UI appears in MCP queries
- MCP-generated art shows up in the web interface's history
- Statistics reflect total usage across both interfaces

This unified data model demonstrates how MCP servers can participate in larger application ecosystems rather than existing in isolation.

## Web Interface Features

The LiveView implementation showcases modern web development patterns:

**Real-time Feedback**: As users type, they see ASCII art generate character by character. How might this immediate feedback loop enhance the creative process?

**History Management**: The sidebar displays recent creations with one-click copy functionality. What patterns could you apply to maintain history in your own tools?

**Statistics Dashboard**: Font usage statistics provide insights into user preferences. How would you use this data to inform feature development?

## Development and Deployment

### Local Development

```bash
# Setup the application
mix setup

# Start the Phoenix server
mix phx.server
```

The application runs on `http://localhost:4000` with the MCP endpoint at `/mcp`.

## Extending the Architecture

As you explore this codebase, consider these extension points:

- How would you add new ASCII art fonts to both interfaces?
- What caching strategies could improve performance for frequently requested text?
- How might you implement user-specific generation history?

The ASCII Art Studio demonstrates that MCP servers built with Hermes integrate naturally into existing Phoenix applications, enabling you to serve both human users and AI assistants from a single, well-architected codebase.
