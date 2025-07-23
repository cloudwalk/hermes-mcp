# Building a Server

What if your Elixir application could become a capability that AI assistants can discover and use? Let's explore how to expose your application's features through MCP.

## Your First Tool

Remember our greeter from the introduction? Let's understand what's really happening:

```elixir
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
```

What makes this special? When an AI assistant connects to your server, it can:

- Discover this tool exists
- Understand what parameters it needs
- Call it with the right data
- Get a response back

The `schema` block defines what the tool expects. The `execute` function does the work. That's it.

## Creating Your Server

Now let's build a server that exposes this tool:

```elixir
defmodule MyApp.Server do
  use Hermes.Server,
    name: "my-app",
    version: "1.0.0",
    capabilities: [:tools]

  # Register our greeter tool
  component MyApp.Greeter
end
```

Add it to your supervision tree:

```elixir
children = [
  # Start with STDIO for easy testing
  {MyApp.Server, transport: :stdio}
]
```

How do you test this? Complete one file for reference:

```elixir
Mix.install([{:hermes_mcp, "~> 0.11"}])

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

defmodule MyApp.Server do
  use Hermes.Server,
    name: "my-app",
    version: "1.0.0",
    capabilities: [:tools]

  # Register our greeter tool
  component MyApp.Greeter
end

children = [Hermes.Server.Registry, {MyApp.Server, transport: :stdio}]
{:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
```

Save it to `my_app.exs` and you can test it with the helper task:

```bash
mix hermes.stdio.interactive -c elixir --args=--no-halt,my_app.exs
```

Or you can add it to claude, assuming you have `claude-code` installed:

```bash
claude mcp add my-app -- elixir --no-halt my_app.exs
```

## Building Real Tools

Let's create something more substantial. What if we built a tool that searches through your application's data?

```elixir
defmodule MyApp.ProductSearch do
  @moduledoc "Search for products in our catalog"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field :query, :string, required: true
    field :limit, :integer, default: 10
    field :category, :string
  end

  @impl true
  def execute(%{query: query} = params, frame) do
    limit = params[:limit] || 10
    category = params[:category]

    products =
      MyApp.Catalog.search(query)
      |> maybe_filter_by_category(category)
      |> Enum.take(limit)
      |> Enum.map(&format_product/1)

    {:reply, Response.json(Response.tool(), products), frame}
  end

  defp maybe_filter_by_category(products, nil), do: products
  defp maybe_filter_by_category(products, category) do
    Enum.filter(products, &(&1.category == category))
  end

  defp format_product(product) do
    %{
      id: product.id,
      name: product.name,
      price: product.price,
      description: product.description
    }
  end
end
```

Notice how we're using your existing business logic? The tool is just a thin wrapper that makes it accessible to AI.

## Adding Resources

Tools perform actions. Resources provide data. What if AI assistants could read your application's data directly?

```elixir
defmodule MyApp.ConfigResource do
  @moduledoc "Current application configuration"

  use Hermes.Server.Component,
    type: :resource,
    uri: "config://app/settings"

  alias Hermes.Server.Response

  @impl true
  def read(_params, frame) do
    config = %{
      environment: Application.get_env(:my_app, :environment),
      features: Application.get_env(:my_app, :feature_flags),
      version: Application.spec(:my_app, :vsn) |> to_string()
    }

    {:reply, Response.json(Response.resource(), config), frame}
  end
end
```

Resources have URIs. AI assistants can discover and read them:

```
Client: list_resources()
Server: [{uri: "config://app/settings", name: "Application Config", ...}]
Client: read_resource("config://app/settings")
Server: {contents: [{text: "{\n  \"environment\": \"production\",\n  ..."}]}
```

## Creating Prompts

Prompts are templates that help AI assistants interact with your users more effectively:

```elixir
defmodule MyApp.BugReportPrompt do
  @moduledoc "Generate a structured bug report"

  use Hermes.Server.Component, type: :prompt

  alias Hermes.Server.Response

  schema do
    field :title, :string, required: true
    field :severity, :string, values: ["low", "medium", "high", "critical"]
    field :steps_to_reproduce, :string
    field :expected_behavior, :string
    field :actual_behavior, :string
  end

  @impl true
  def get_messages(params, frame) do
    content = build_report_content(params)

    response =
      Response.prompt()
      |> Response.user_message(content)
      |> Response.system_message("This is the Bug report prompt, user already have the data")

    {:reply, response, frame}
  end

  defp bug_report_content(params) do
    """
    Please help me file a bug report for: #{params.title}

    Severity: #{params.severity || "not specified"}

    Steps to reproduce:
    #{params.steps_to_reproduce || "not provided"}

    Expected behavior:
    #{params.expected_behavior || "not provided"}

    Actual behavior:
    #{params.actual_behavior || "not provided"}

    Please format this as a proper bug report and suggest any missing information.
    """
  end
end
```

## Transport Options

How do clients connect to your server? Let's explore your options:

### STDIO (Development & CLIs)

Perfect for CLI tools and development:

```elixir
{MyApp.Server, transport: :stdio}
```

Your server communicates through standard input/output. Great for:

- Command-line tools
- Development and testing
- Subprocess isolation

### HTTP (Web Applications)

For web services that multiple clients connect to:

```elixir
{MyApp.Server, transport: {:streamable_http, port: 8080}}
```

This creates an HTTP endpoint at `http://localhost:8080/mcp`. Each client gets its own session.

### Integration with Phoenix

Already have a Phoenix app? Integrate MCP as a route:

```elixir
# In your Phoenix endpoint (lib/my_app_web/endpoint.ex)
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app

  # Add the MCP plug before your router
  plug Hermes.Server.Transport.StreamableHTTP.Plug,
    server: MyApp.Server,
    path: "/mcp"

  # Your other plugs...
  plug MyAppWeb.Router
end

# In your application supervisor
children = [
  MyAppWeb.Endpoint,
  Hermes.Server.Registry,
  {MyApp.Server, transport: :streamable_http}
]
```

Now your MCP server is available at `http://localhost:4000/mcp`.

## Error Handling

What happens when things go wrong? Let's handle errors gracefully:

```elixir
defmodule MyApp.DatabaseQuery do
  @moduledoc "Query the database"

  use Hermes.Server.Component, type: :tool

  schema do
    field :query, :string, required: true
  end

  @impl true
  def execute(%{query: query}, frame) do
    case MyApp.Repo.query(query) do
      {:ok, result} ->
        {:reply, Response.json(Response.tool(), format_result(result)), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Query failed: #{to_string(reason)}")}
    end
  end
end
```

Hermes automatically formats your error responses according to the MCP protocol.

## Stateful Operations

Need to maintain state across calls? The frame provides context:

```elixir
defmodule MyApp.Conversation do
  @moduledoc "Continue a conversation"

  use Hermes.Server.Component, type: :tool

  schema do
    field :message, :string, required: true
  end

  @impl true
  def execute(%{message: message}, frame) do
    session_id = frame.private.session_id
    history = ConversationStore.get_history(session_id)

    new_history = history ++ [message]
    ConversationStore.save_history(session_id, new_history)

    content = generate_response(new_history)

    {:reply, Response.text(Response.tool(), content), frame}
  end
end
```

## Tool Annotations

Need to add extra metadata to your tools? Annotations provide additional context:

```elixir
defmodule MyApp.DatabaseQuery do
  @moduledoc "Query the application database"

  use Hermes.Server.Component,
    type: :tool,
    annotations: %{
      "x-api-version" => "2.0",
      "x-rate-limit" => "10/minute",
      "x-auth-required" => true
    }

  schema do
    field :query, :string, required: true
  end

  @impl true
  def execute(params, frame) do
    # Implementation...
  end
end
```

These annotations are exposed in the tool definition, helping clients understand additional constraints or requirements.

## Testing Your Server

How do you know your server works correctly? Let's explore interactive testing first:

### Interactive CLI Testing

Hermes provides interactive `Mix` tasks for different transports if you need quick testing:

```bash
# Test STDIO server
mix hermes.stdio.interactive --command elixir --args=--no-halt,my_app.exs

# Test HTTP server
mix hermes.streamable_http.interactive --base-url=http://localhost:8080 --header 'authorization: Bearer 123'

# With verbose logging
mix hermes.stdio.sse --base-url=http//:localhost:4000 -vvv
```

In the interactive session:

```
mcp> ping
pong

mcp> list_tools
Available tools:
- greeter: Greet someone warmly
- product_search: Search for products in our catalog

mcp> call_tool
Tool name: greeter
Tool arguments (JSON): {"name": "Alice"}
Result: Hello Alice! Welcome to the MCP world!

mcp> show_state
Client State:
  Protocol: 2024-11-05
  Initialized: true
  ...
```

### Unit Testing

Now let's write some tests:

```elixir
defmodule MyApp.ServerTest do
  use ExUnit.Case

  alias Hermes.Server.Frame

  test "greeter tool works correctly" do
    frame = %Frame{}

    assert {:reply, resp, ^frame} = Greeter.execute(%{name: "joe"}, frame)
    assert {:ok, %{"result" => %{"content" => content}}} = JSON.decode(resp)
    assert [%{"text" => "Hello joe! Welcome to the MCP world!"}] = content
  end
end
```

## What's Next?

You've seen how to expose your Elixir application's capabilities to AI assistants. What patterns interest you most?

- Complex multi-step workflows?
- Authentication and authorization?
- Real-time updates and notifications?

The server abstraction handles all the protocol complexity. You just focus on what your application does best.
