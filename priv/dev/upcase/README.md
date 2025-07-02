# Upcase MCP Server

A component-based MCP server that demonstrates how Hermes enables modular, extensible tool development through clean architectural patterns.

## Overview

What if your MCP server could grow beyond a single tool? The Upcase server explores this question by implementing a complete component system that separates tools, prompts, and resources into reusable modules. This approach shows how Hermes makes it straightforward to build servers that scale with your needs.

## Core Architecture

The server leverages Hermes' component system to organize functionality into distinct, composable units. Each component implements the `Hermes.Server.Component` behavior, ensuring consistent interfaces across tools, prompts, and resources. This design pattern enables teams to develop and test components independently while maintaining a cohesive server implementation.

### Available Tools

**Text Transformation (`upcase`)**

The foundational tool accepts text input and returns its uppercase transformation. While simple in concept, the implementation demonstrates proper schema validation and response formatting patterns.

```elixir
# Tool invocation
{:ok, result} = Hermes.Client.call_tool(client, "upcase", %{text: "hello world"})
# Returns: "HELLO WORLD"
```

**Text Analysis (`analyze_text`)**

A more sophisticated tool that showcases complex response structures. Given any text input, it returns comprehensive statistics including character counts, word analysis, and multiple transformations. This tool illustrates how to build rich, structured responses while maintaining clean separation between analysis logic and MCP protocol handling.

```elixir
# Returns detailed JSON with statistics and transformations
{:ok, analysis} = Hermes.Client.call_tool(client, "analyze_text", %{text: "Hello MCP!"})
```

### Prompt Support

The server includes a `text_transform` prompt component that generates context-aware prompts for LLMs. This feature demonstrates how MCP servers can assist AI systems in understanding and executing transformation tasks. The prompt system supports configurable transformation types, allowing dynamic adaptation to different use cases.

### Resource Management

Through the `upcase://examples` resource provider, the server exposes sample texts for testing and demonstration. This pattern shows how MCP servers can serve static or dynamic content alongside their tool capabilities, creating self-documenting systems.

## Transport and Deployment

The server uses StreamableHTTP transport through Bandit, exposing the MCP endpoint at `/mcp`. This HTTP-based approach enables straightforward deployment in containerized environments or behind load balancers. The Plug-based routing keeps the HTTP layer thin, focusing complexity in the MCP protocol implementation where it belongs.

### Running the Server

```bash
# Development mode
cd priv/dev/upcase
mix deps.get
mix run --no-halt
```

The server runs on port 4000 by default, configurable through environment variables or application configuration.

## Next Steps

This server provides a foundation for exploring advanced MCP patterns. You might consider:

- How would you add authentication to specific tools?
- What patterns would you use for tools that require external API calls?
- How might you implement rate limiting at the component level?

The Upcase server demonstrates that with Hermes, building sophisticated MCP servers becomes an exercise in clean architecture rather than protocol complexity.
