# MCP Server Quick Start Guide

This guide will help you create your first MCP server using Hermes in under 5 minutes.

## What is an MCP Server?

An MCP (Model Context Protocol) server provides tools, prompts, and resources to AI assistants. Think of it as an API that AI models can interact with to perform actions or retrieve information.

## Basic Server Setup

### Step 1: Define Your Server Module

Create a new Elixir module that uses `Hermes.Server`:

```elixir
defmodule MyApp.MCPServer do
  use Hermes.Server,
    name: "My First MCP Server",
    version: "1.0.0",
    capabilities: [:tools]

  def start_link(opts) do
    Hermes.Server.start_link(__MODULE__, :ok, opts)
  end

  @impl Hermes.Server.Behaviour
  def init(:ok, frame) do
    {:ok, frame}
  end
end
```

### Step 2: Add to Your Application Supervisor

In your `application.ex`:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Registry to handle processes names
      Hermes.Server.Registry,
      # Start with STDIO transport (for local tests)
      {MyApp.MCPServer, transport: :stdio}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Step 3: Create Your First Tool

Tools are functions that AI assistants can call:

```elixir
defmodule MyApp.MCPServer.Tools.Greeter do
  @moduledoc "Greet someone by name"

  use Hermes.Server.Component, type: :tool

  schema do
    %{name: {:required, :string}}
  end

  @impl true
  def execute(%{name: name}, frame) do
    {:ok, "Hello, #{name}! Welcome to MCP!", frame}
  end
end
```

### Step 4: Register the Tool

Update your server module to include the tool:

```elixir
defmodule MyApp.MCPServer do
  use Hermes.Server,
    name: "My First MCP Server",
    version: "1.0.0",
    capabilities: [:tools]

  def start_link(opts) do
    Hermes.Server.start_link(__MODULE__, :ok, opts)
  end

  # Register your tool
  component MyApp.MCPServer.Tools.Greeter

  @impl Hermes.Server.Behaviour
  def init(_arg, frame) do
    {:ok, frame}
  end
end
```

## Testing Your Server

### Using the Interactive Shell

Hermes provides interactive mix tasks for testing:

```bash
# Test with STDIO transport
mix help hermes.stdio.interactive

# Test with HTTP transport
mix help hermes.streamable_http.interactive
```

## Next Steps

- Explore the [Component System](server_components.md) for building tools, prompts, and resources
- Configure different [Transport Options](server_transport.md)
