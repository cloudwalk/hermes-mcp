# Hermes MCP

[![hex.pm](https://img.shields.io/hexpm/v/hermes_mcp.svg)](https://hex.pm/packages/hermes_mcp)
[![docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/hermes_mcp)
[![ci](https://github.com/cloudwalk/hermes-mcp/actions/workflows/ci.yml/badge.svg)](https://github.com/cloudwalk/hermes-mcp/actions/workflows/ci.yml)
[![Hex Downloads](https://img.shields.io/hexpm/dt/hermes_mcp)](https://hex.pm/packages/hermes_mcp)

A high-performance Model Context Protocol (MCP) implementation in Elixir.

## Overview

Hermes MCP is a comprehensive Elixir SDK for the [Model Context Protocol](https://spec.modelcontextprotocol.io/), providing complete client and server implementations with Elixir's exceptional concurrency model and fault tolerance.

## Installation

```elixir
def deps do
  [
    {:hermes_mcp, "~> 0.14.1"}  # x-release-please-version
  ]
end
```

## Quick Start

### Server

```elixir
# Define a server with tools capabilities
defmodule MyApp.MCPServer do
  use Hermes.Server,
    name: "My Server",
    version: "1.0.0",
    capabilities: [:tools]

  @impl true
  # this callback will be called when the
  # MCP initialize lifecycle completes
  def init(_client_info, frame) do
    {:ok,frame
      |> assign(counter: 0)
      |> register_tool("echo",
        input_schema: %{
          text: {:required, :string, max: 150, description: "the text to be echoed"}
        },
        annotations: %{read_only: true},
        description: "echoes everything the user says to the LLM") }
  end

  @impl true
  def handle_tool("echo", %{text: text}, frame) do
    Logger.info("This tool was called #{frame.assigns.counter + 1}")
    {:reply, text, assign(frame, counter: frame.assigns.counter + 1)}
  end
end

# Add to your application supervisor
children = [
  Hermes.Server.Registry,
  {MyApp.MCPServer, transport: :streamable_http}
]

# Add to your Plug/Phoenix router (if using HTTP)
forward "/mcp", to: Hermes.Server.Transport.StreamableHTTP.Plug, init_opts: [server: MyApp.MCPServer]
```

Now you can achieve your MCP server on `http://localhost:<port>/mcp`

### Client

```elixir
# Define a client module
defmodule MyApp.MCPClient do
  use Hermes.Client,
    name: "MyApp",
    version: "1.0.0",
    protocol_version: "2025-03-26"
end

# Add to your application supervisor
children = [
  {MyApp.MCPClient,
   transport: {:streamable_http, base_url: "http://localhost:4000"}}
]

# Use the client
{:ok, result} = MyApp.MCPClient.call_tool("echo", %{text: "this will be echoed!"})
```

## Why Hermes?

Named after Hermes, the Greek god of boundaries and communication, this library facilitates seamless interaction between Large Language Models and external tools - serving as a messenger between AI and data sources.

## Documentation

For detailed guides and examples, visit the [official documentation](https://hexdocs.pm/hermes_mcp).

## Examples

We have build some elixir implementation examples using `plug` based and `phoenix` apps:

1. [upcase-server](/priv/dev/upcase/README.md): `plug` based MCP server using streamable_http
2. [echo-elixir](/priv/dev/echo-elixir/README.md): `phoenix` based MCP server using sse
3. [ascii-server](/priv/dev/ascii/README.md): `phoenix_live_view` based MCP server using streamable_http and UI

## License

MIT License. See [LICENSE](./LICENSE) for details.
