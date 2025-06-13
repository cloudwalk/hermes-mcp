# Hermes MCP

[![hex.pm](https://img.shields.io/hexpm/v/hermes_mcp.svg)](https://hex.pm/packages/hermes_mcp)
[![docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/hermes_mcp)
[![ci](https://github.com/cloudwalk/hermes-mcp/actions/workflows/ci.yml/badge.svg)](https://github.com/cloudwalk/hermes-mcp/actions/workflows/ci.yml)

A high-performance Model Context Protocol (MCP) implementation in Elixir.

## Overview

Hermes MCP is a comprehensive Elixir SDK for the [Model Context Protocol](https://spec.modelcontextprotocol.io/), providing complete client and server implementations with Elixir's exceptional concurrency model and fault tolerance.

## Installation

```elixir
def deps do
  [
    {:hermes_mcp, "~> 0.9"}  # x-release-please-minor
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

  def start_link(opts) do
    Hermes.Server.start_link(__MODULE__, :ok, opts)
  end

  component MyApp.MCPServer.EchoTool

  @impl true
  def init(:ok, frame), do: {:ok, frame}
end

# Define your tool
defmodule MyApp.MCPServer.EchoTool do
  @moduledoc "THis tool echoes everything the user says to the LLM"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field :text, {:required, {:string, {:max, 500}}}, description: "The text to be echoed, max of 500 chars"
  end

  @impl true
  def execute(%{text: text}, frame) do
    {:reply, Response.text(Response.tool(), text), frame}
  end
end

# Add to your application supervisor
children = [
  Hermes.Server.Registry,
  {MyApp.MCPServer, transport: :stdio}
]
```

### Client  

```elixir
# Define a client module
defmodule MyApp.AnthropicClient do
  use Hermes.Client,
    name: "MyApp",
    version: "1.0.0",
    protocol_version: "2024-11-05",
    capabilities: [:roots, :sampling]
end

# Add to your application supervisor
children = [
  {MyApp.AnthropicClient, 
   transport: {:stdio, command: "uvx", args: ["mcp-server-anthropic"]}}
]

# Use the client
{:ok, tools} = MyApp.AnthropicClient.list_tools()
{:ok, result} = MyApp.AnthropicClient.call_tool("search", %{query: "elixir"})
```

## Why Hermes?

Named after Hermes, the Greek god of boundaries and communication, this library facilitates seamless interaction between Large Language Models and external tools - serving as a messenger between AI and data sources.

## Documentation

For detailed guides and examples, visit the [official documentation](https://hexdocs.pm/hermes_mcp).

## License

MIT License. See [LICENSE](./LICENSE) for details.
