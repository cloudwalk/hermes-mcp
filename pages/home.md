# Welcome to Hermes MCP

Let's explore how Hermes helps you build bridges between AI assistants and your Elixir applications. Have you ever wished your AI could directly interact with your code? That's exactly what we're enabling here.

## What's This All About?

Hermes implements the Model Context Protocol (MCP) - think of it as a secure conversation channel between AI assistants and your applications. Your AI can discover what your app offers and interact with it safely.

Three minutes. That's all we need to show you something working.

## Your First Connection

What if we started by connecting to an existing MCP server? Let's see how this feels:

```elixir
# In your mix.exs
{:hermes_mcp, "~> 0.11.2"} # x-release-please-version
```

Now, let's define a client that can talk to Claude's own MCP server:

```elixir
defmodule MyApp.ClaudeClient do
  use Hermes.Client,
    name: "MyApp",
    version: "1.0.0",
    protocol_version: "2024-11-05",
    capabilities: [:roots]
end
```

Add it to your application:

```elixir
# considering you have `claude-code` installed
children = [
  {MyApp.ClaudeClient,
   transport: {:stdio, command: "claude", args: ["mcp", "serve"]}}
]
```

What can your client do now? Let's explore:

```elixir
# Is anyone there?
MyApp.ClaudeClient.ping()
# => :pong

# What tools are available?
{:ok, response} = MyApp.ClaudeClient.list_tools()
# => Discover web search, news, and more...

# Let's search for something
{:ok, result} = MyApp.ClaudeClient.call_tool("search", %{query: "elixir lang"})
```

How does that feel? In just a few lines, you've connected your Elixir app to Claude's capabilities.

## Building Your Own Server

What if you want to expose your own functionality to AI assistants? Let's create a simple server:

```elixir
defmodule MyApp.Server do
  use Hermes.Server,
    name: "my-app",
    version: "1.0.0",
    capabilities: [:tools]

  component MyApp.Greeter
end

defmodule MyApp.Greeter do
  @moduledoc "Greet someone warmly"

  use Hermes.Server.Component, type: :tool

  schema do
    field :name, :string, required: true
  end

  def execute(%{name: name}, _frame) do
    {:ok, "Hello #{name}! Welcome to the MCP world!"}
  end
end

# on your application.ex
children = [
  Hermes.Server.Registry,
  {MyApp.Greeter, transport: :stdio}
]
```

Start your server and any AI assistant can now discover and use your greeter. Interesting, right?

## Where to Go Next?

What interests you most?

- **[Building a Client](building-a-client.md)** - Connect to any MCP server and leverage its capabilities
- **[Building a Server](building-a-server.md)** - Expose your Elixir application's features to AI assistants
- **[Recipes](recipes.md)** - Real-world patterns we've discovered along the way

The protocol handles all the complexity - transport negotiation, capability exchange, error handling. You just focus on what your application does best.

Ready to explore further?
