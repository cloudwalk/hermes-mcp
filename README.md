# Hermes MCP

> [!WARNING]
>
> This library is under active development, may expect breaking changes

A high-performance Model Context Protocol (MCP) implementation in Elixir with first-class Phoenix support.

## Overview

Hermes MCP provides a unified solution for building both MCP clients and servers in Elixir, leveraging the language's exceptional concurrency model and fault tolerance capabilities. The library offers seamless integration with Phoenix for HTTP/SSE transport while maintaining support for standard stdio communication.

## Features

The library implements the full [Model Context Protocol specification](https://spec.modelcontextprotocol.io/specification/2024-11-05/), providing:

- Complete client and server implementations with protocol lifecycle management 
- First-class Phoenix integration for HTTP/SSE transport
- Robust stdio transport for local process communication
- Built-in connection supervision and automatic recovery
- Comprehensive capability negotiation
- Progress notification support for tracking long-running operations

## Installation

Add Hermes MCP to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hermes_mcp, "~> 0.2"}
  ]
end
```

Based on the provided documents, I'll create a section for the README that demonstrates a minimal usage example of the Hermes client interface and transport with supervision tree integration.

## Usage Example

### Creating a Supervised Client

The following example shows how to integrate Hermes MCP into your application's supervision tree for robust client management:

> [!NOTE]
> We recommend to start an isolated Supervisor for each pair of client <> transport using the `:one_for_all` strategy, since both processes depends on each other

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
          "roots" => %{},
          "sampling" => %{},
        }
      ]}
      
      # Your other application services
      # ...
    ]
    
    opts = [strategy: :one_for_all, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Making Client Requests

Once your client is running, you can interact with the MCP server:

```elixir
# List available resources
{:ok, %{"resources" => resources}} = Hermes.Client.list_resources(MyApp.MCPClient)

# Read a specific resource
{:ok, resource} = Hermes.Client.read_resource(MyApp.MCPClient, "file:///example.txt")

# List available tools
{:ok, %{"tools" => tools}} = Hermes.Client.list_tools(MyApp.MCPClient)

# Call a tool
{:ok, result} = Hermes.Client.call_tool(MyApp.MCPClient, "example_tool", %{"param" => "value"})
  
# List available prompts
{:ok, %{"prompts" => prompts}} = Hermes.Client.list_prompts(MyApp.MCPClient)

# Get a prompt with arguments
{:ok, prompt} = Hermes.Client.get_prompt(MyApp.MCPClient, "example_prompt", %{"arg" => "value"})

# Example with progress tracking
progress_token = Hermes.Message.generate_progress_token()
{:ok, result} = Hermes.Client.call_tool(MyApp.MCPClient, "long_running_tool", %{},
  progress: [
    token: progress_token,
    callback: fn token, progress, total ->
      percentage = if total, do: Float.round(progress / total * 100, 1), else: nil
      IO.puts("Progress: #{progress}/#{total || "unknown"} (#{percentage || "calculating..."}%)")
    end
  ]
)
```

For more details on progress tracking, see the [Progress Tracking](./pages/progress_tracking.md) documentation.

### Logging

`hermes-mcp` follows the [Logger](https://hexdocs.pm/logger) standards and also provide additional metadata:
- `mcp_client`: the current `Hermes.MCP.Client` process
- `mcp_transport`: the current `Hermes.Transport` layer being used by the client, either `STDIO` or `SSE`

### Error Handling

Hermes provides standardized error handling:

```elixir
case Hermes.Client.call_tool(MyApp.MCPClient, "unavailable_tool", %{}) do
  {:ok, result} ->
    # Handle successful result
    IO.inspect(result)
    
  {:error, error} ->
    # Handle error response
    IO.puts("Error: #{error["message"]} (Code: #{error["code"]})")
end
```

The client automatically manages the connection lifecycle, including initial handshake, capability negotiation, and message correlation.

## Architecture

The library is structured around several core components:

- Protocol Layer: Handles message framing, request/response correlation, and lifecycle management
- Transport Layer: Provides pluggable transports for stdio and HTTP/SSE communication
- Server Components: Implements server-side protocol operations with Phoenix integration
- Client Components: Manages client-side operations and capability negotiation
- Supervision Trees: Ensures fault tolerance and automatic recovery

Check out our technical [RFC](./pages/rfc.md) that describe each component more in deep.

## Development Status

Hermes MCP is currently under active development. The initial release will focus on providing stable protocol implementation focused into client interface to existing MCP servers. The API is subject to change as we refine the design based on real-world usage patterns.

We encourage you to star the repository and watch for updates as we progress toward our first stable release.

## Contributing

We welcome contributions to Hermes MCP! The project is in its early stages, and we're particularly interested in feedback on the design and architecture. Please check our [Issues](https://github.com/cloudwalk/hermes-mcp/issues) page for ways to contribute.

## License

Hermes MCP is released under the MIT License. See [LICENSE](LICENSE) for details.

## Why Hermes?

The library is named after Hermes, the Greek god of boundaries, communication, and commerce. This namesake reflects the core purpose of the Model Context Protocol: to establish standardized communication between AI applications and external tools. Like Hermes who served as a messenger between gods and mortals, this library facilitates seamless interaction between Large Language Models and various data sources or tools.

Furthermore, Hermes was known for his speed and reliability in delivering messages, which aligns with our implementation's focus on high performance and fault tolerance in the Elixir ecosystem. The name also draws inspiration from the Hermetic tradition of bridging different domains of knowledge, much like how MCP bridges the gap between AI models and external capabilities.
