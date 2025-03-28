# Hermes MCP

[![hex.pm](https://img.shields.io/hexpm/v/hermes_mcp.svg)](https://hex.pm/packages/hermes_mcp)
[![docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/hermes_mcp)
[![ci](https://github.com/cloudwalk/hermes-mcp/actions/workflows/ci.yml/badge.svg)](https://github.com/cloudwalk/hermes-mcp/actions/workflows/ci.yml)

> [!WARNING]
>
> This library is under active development, may expect breaking changes

A high-performance Model Context Protocol (MCP) implementation in Elixir.

## Overview

Hermes MCP provides a robust client implementation for the [Model Context Protocol](https://spec.modelcontextprotocol.io/specification/2024-11-05/), leveraging Elixir's exceptional concurrency model and fault tolerance capabilities.

## Features

- Complete client implementation with protocol lifecycle management
- Multiple transport options (STDIO and HTTP/SSE)
- Built-in connection supervision and automatic recovery
- Comprehensive capability negotiation
- Progress notification support for tracking long-running operations
- Structured logging system with log level control

## Installation

### Library Usage

Add Hermes MCP to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hermes_mcp, "~> 0.3"}
  ]
end
```

### Standalone CLI Installation

Download the appropriate binary for your platform from the [GitHub releases page](https://github.com/cloudwalk/hermes-mcp/releases).

```bash
# Make it executable (Linux/macOS)
# or hermes_cli-macos-intel, hermes_cli-macos-arm
mv hermes_mcp_linux hermes-mcp && chmod +x hermes-mcp

# Run it
./hermes-mcp --transport sse --base-url="http://localhost:8000"
```

## Quick Start

### Interactive Testing

Hermes MCP provides interactive tools for testing MCP servers with a user-friendly CLI.

#### Using the CLI Binary:

```bash
# Test an SSE server
hermes_cli --transport sse --base-url="http://localhost:8000" --base-path="/mcp"

# Test a local process via STDIO
hermes_cli --transport stdio --command="mcp" --args="run,path/to/server.py"
```

#### Using Mix Tasks (For Elixir Developers):

```bash
# Test an SSE server
mix hermes.sse.interactive --base-url="http://localhost:8000" --base-path="/mcp"

# Test a local process via STDIO
mix hermes.stdio.interactive --command="mcp" --args="run,path/to/server.py"
```

These interactive shells provide commands for listing and calling tools, exploring prompts, and accessing resources.

### Setting up a Client

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Start the MCP transport
      {Hermes.Transport.STDIO, [
        name: MyApp.MCPTransport,
        client: MyApp.MCPClient, 
        command: "mcp",
        args: ["run", "path/to/server.py"]
      ]},
      
      # Start the MCP client using the transport
      {Hermes.Client, [
        name: MyApp.MCPClient,
        transport: [layer: Hermes.Transport.STDIO, name: MyApp.MCPTransport],
        client_info: %{
          "name" => "MyApp",
          "version" => "1.0.0"
        },
        capabilities: %{
          "roots" => %{"listChanged" => true},
          "sampling" => %{}
        }
      ]}
    ]
    
    opts = [strategy: :one_for_all, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Making Client Requests

```elixir
# Call a tool
{:ok, result} = Hermes.Client.call_tool(MyApp.MCPClient, "example_tool", %{"param" => "value"})

# Handle errors properly
case Hermes.Client.call_tool(MyApp.MCPClient, "unavailable_tool", %{}) do
  {:ok, %Hermes.MCP.Response{}} ->
    # Handle successful result
    
  {:error, %Hermes.MCP.Error{} = err} ->
    # Handle error response
    IO.puts(inspect(err, pretty: true))
end
```

## Documentation

For detailed guides and examples, visit the [official documentation](https://hexdocs.pm/hermes_mcp)

## Why Hermes?

The library is named after Hermes, the Greek god of boundaries, communication, and commerce. This namesake reflects the core purpose of the Model Context Protocol: to establish standardized communication between AI applications and external tools.

Like Hermes who served as a messenger between gods and mortals, this library facilitates seamless interaction between Large Language Models and various data sources or tools.

## Local Development

```bash
# Setup the project
mix setup

# Run tests
mix test

# Code quality
mix lint

# Start development MCP servers
# Echo server (Python)
just echo-server
# Calculator server (Go)
just calculator-server
```

The MCP servers in `priv/dev` require:
- Python 3.11+ with uv (for echo server)
- Go 1.21+ (for calculator server)

See [CONTRIBUTING.md](./CONTRIBUTING.md) for detailed contribution guidelines.

## License

Hermes MCP is released under the MIT License. See [LICENSE](./LICENSE) for details.
