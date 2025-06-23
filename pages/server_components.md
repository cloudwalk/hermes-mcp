# MCP Server Components Guide

This guide shows you how to build Tools, Prompts, and Resources using Hermes component system.

## Tools

Tools are functions that AI assistants can call to perform actions.

### Basic Tool

```elixir
defmodule MyServer.Tools.Calculator do
  @moduledoc "Add two numbers"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field :a, :float, required: true
    field :b, :float, required: true
  end

  @impl true
  def execute(%{a: a, b: b}, frame) do
    {:reply, Response.text(Response.tool(), "Result: #{a + b}"), frame}
  end
end
```

### Schema with Field Metadata

The `field` macro allows adding JSON Schema metadata like format and description:

```elixir
defmodule MyServer.Tools.UserManager do
  @moduledoc "Manage user data"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field :email, :string, required: true, format: "email", description: "User's email address"
    field :age, {:integer, {:range, {0, 150}}}, description: "Age in years"
    field :website, :string, format: "uri"
    
    field :address, description: "Mailing address" do
      field :street, :string, required: true
      field :city, :string, required: true
      field :postal_code, :string, format: "postal-code"
      field :country, :string, description: "ISO 3166-1 alpha-2 code"
    end
  end

  @impl true
  def execute(params, frame) do
    {:reply, Response.text(Response.tool(), "User created: #{params.email}"), frame}
  end
end
```

The field metadata is included in the JSON Schema exposed to MCP clients, providing better documentation and validation hints.

### Tool with Error Handling

```elixir
defmodule MyServer.Tools.Divider do
  @moduledoc "Divide two numbers"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field :a, :float, required: true
    field :b, :float, required: true
  end

  @impl true
  def execute(%{a: a, b: 0}, frame) do    
    {:reply, Response.error(Response.tool(), "Cannot divide by zero"), frame}
  end

  def execute(%{a: a, b: b}, frame) do
    {:reply, Response.text(Response.tool(), "#{a} ÷ #{b} = #{a / b}"), frame}
  end
end
```

### Tool with JSON Response

```elixir
defmodule MyServer.Tools.SystemInfo do
  @moduledoc "Get system information"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response
  
  @impl true
  def execute(_params, frame) do  
    info = %{
      os: :os.type(),
      memory: :erlang.memory(:total),
      processes: :erlang.system_info(:process_count)
    }
        
    {:reply, Response.json(Response.tool(), info), frame}
  end
end
```

## Prompts

Prompts provide reusable message templates for AI conversations.

### Basic Prompt

```elixir
defmodule MyServer.Prompts.Assistant do
  @moduledoc "General assistant prompt"

  use Hermes.Server.Component, type: :prompt

  alias Hermes.Server.Response

  schema do
    field :style, {:enum, ["formal", "casual"]}, required: true, type: :string
  end

  @impl true
  def get_messages(%{style: "formal"}, frame) do    
    response = 
      Response.prompt()
      |> Response.system_message("You are a formal, professional assistant.")
      |> Response.user_message("Please help me with my task.")
    
    {:reply, response, frame}
  end

  def get_messages(%{style: "casual"}, frame) do
    response = 
      Response.prompt()
      |> Response.system_message("You are a friendly, casual assistant.")
      |> Response.user_message("Hey, can you help me out?")
    
    {:reply, response, frame}
  end
end
```

### Prompt with Context

```elixir
defmodule MyServer.Prompts.CodeReview do
  @moduledoc "Code review prompt"

  use Hermes.Server.Component, type: :prompt

  schema do
    field :language, :string, required: true, description: "Programming language"
  end

  @impl true
  def get_messages(%{language: lang}, frame) do
    response = 
      Response.prompt("Code review for #{lang}")
      |> Response.system_message("You are an expert #{lang} code reviewer.")
      |> Response.user_message("Please review the following #{lang} code for best practices and potential issues.")
    
    {:reply, response, frame}
  end
end
```

### Prompt with Field Metadata

When using prompts, you can add descriptions to arguments for better documentation in the MCP protocol:

```elixir
defmodule MyServer.Prompts.DocumentAnalyzer do
  @moduledoc "Analyze and summarize documents"

  use Hermes.Server.Component, type: :prompt

  alias Hermes.Server.Response

  schema do
    field :document, :string, required: true, description: "The document text to analyze"
    field :language, :string, required: true, description: "Document language (e.g., 'en', 'es', 'fr')"
    field :analysis_type, {:enum, ["summary", "sentiment", "keywords"]}, type: :string,
          description: "Type of analysis to perform"
    field :max_length, {:integer, {:default, 500}}, 
          description: "Maximum length of the summary in characters"
  end

  @impl true
  def get_messages(params, frame) do
    %{document: doc, language: lang, analysis_type: type, max_length: max_len} = params
    
    response = 
      Response.prompt()
      |> Response.system_message("You are an expert document analyzer specializing in #{type} analysis.")
      |> Response.user_message("""
      Please analyze the following #{lang} document and provide a #{type}.
      Maximum response length: #{max_len} characters.
      
      Document:
      #{doc}
      """)
    
    {:reply, response, frame}
  end
end
```

This generates the following MCP arguments:

```json
{
  "arguments": [
    {
      "name": "document",
      "description": "The document text to analyze",
      "required": true
    },
    {
      "name": "language", 
      "description": "Document language (e.g., 'en', 'es', 'fr')",
      "required": true
    },
    {
      "name": "analysis_type",
      "description": "Type of analysis to perform",
      "required": false
    },
    {
      "name": "max_length",
      "description": "Maximum length of the summary in characters",
      "required": false
    }
  ]
}
```

## Resources

Resources provide data that AI can read, identified by URIs.

### Text Resource

```elixir
defmodule MyServer.Resources.Config do
  @moduledoc "Application configuration"

  use Hermes.Server.Component,
    type: :resource,
    uri: "config://app",
    mime_type: "application/json"

  alias Hermes.Server.Response

  @impl true
  def read(_params, frame) do
    config = %{version: "1.0.0", env: Mix.env()}
    
    {:reply, Response.json(Response.resource(), config), frame}
  end
end
```

### Binary Resource

```elixir
defmodule MyServer.Resources.Logo do
  @moduledoc "Company logo"

  use Hermes.Server.Component,
    type: :resource,
    uri: "assets://logo",
    mime_type: "image/png"

  alias Hermes.MCP.Error  
  alias Hermes.Server.Response

  @impl true
  def read(_params, frame) do
    case File.read("priv/static/logo.png") do
      {:ok, binary} ->
        {:reply, Response.blob(Response.resource(), Base.encode64(binary)), frame}
      
      {:error, reason} ->
        {:error, Error.internal_error(%{reason: reason}), frame}
    end
  end
end
```

## Response Builder

The `Hermes.Server.Response` module provides a fluent API for building responses.

### Tool Responses

```elixir
import Hermes.Server.Response

# Text response
tool() |> text("Hello!") |> build()
# => %{"content" => [%{"type" => "text", "text" => "Hello!"}], "isError" => false}

# JSON response
tool() |> json(%{status: "ok"}) |> build()
# => %{"content" => [%{"type" => "text", "text" => "{\"status\":\"ok\"}"}], "isError" => false}

# Error response
tool() |> error("Something went wrong") |> build()
# => %{"content" => [%{"type" => "text", "text" => "Something went wrong"}], "isError" => true}

# Multiple content items
tool() 
|> text("Processing complete")
|> json(%{items: 10, processed: 10})
|> build()
```

### Prompt Responses

```elixir
import Hermes.Server.Response

# Simple conversation
prompt()
|> user_message("What's the weather?")
|> assistant_message("Let me check that for you.")
|> build()
# => %{"messages" => [
#      %{"role" => "user", "content" => "What's the weather?"}, 
#      %{"role" => "assistant", "content" => "Let me check that for you."}
#    ]}

# With system context
prompt("Weather Assistant")
|> system_message("You are a helpful weather assistant.")
|> user_message("What's the forecast for tomorrow?")
|> build()
```

### Resource Responses

```elixir
import Hermes.Server.Response

# Text resource
resource() |> text("File contents here") |> build()
# => %{"text" => "File contents here"}

# Binary resource  
resource() |> blob(base64_data) |> build()
# => %{"blob" => base64_data}

# With metadata
resource()
|> text("Config data")
|> name("Application Config")
|> description("Current app configuration")
|> build()
```

## Registering Components

In your server module:

```elixir
defmodule MyServer do
  use Hermes.Server,
    name: "My Server",
    version: "1.0.0",
    capabilities: [:tools, :prompts, :resources]

  # Register components
  component MyServer.Tools.Calculator
  component MyServer.Tools.Divider
  component MyServer.Prompts.Assistant
  component MyServer.Resources.Config
  
  @impl true
  def init(_arg, frame) do
    {:ok, frame}
  end
end
```

## Using Frame State

The `frame` parameter carries state through requests:

```elixir
defmodule MyServer.Tools.Counter do
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    %{increment: {:optional, :integer, default: 1}}
  end

  @impl true
  def execute(%{increment: inc}, frame) do
    # Get current count
    count = frame.assigns[:count] || 0
    new_count = count + inc
    
    # Update frame
    new_frame = assign(frame, :count, new_count)
    
    {:reply, Response.text(Response.tool(), "Count: #{new_count}"), new_frame}
  end
end
```

## Frame and Authorization

For HTTP transports, `frame.assigns` inherits from `Plug.Conn.assigns`. Users are responsible for populating it with authentication data through their own Plug pipeline:

```elixir
# In your Phoenix/Plug pipeline
pipeline :authenticated_api do
  plug MyApp.AuthPlug        # Sets conn.assigns[:current_user]
  plug MyApp.PermissionsPlug # Sets conn.assigns[:permissions]
end

# In your MCP component
defmodule MyServer.Tools.SecureTool do
  use Hermes.Server.Component, type: :tool

  @impl true
  def execute(params, frame) do
    # Access auth data populated by your plugs
    current_user = frame.assigns[:current_user]
    permissions = frame.assigns[:permissions]
    
    if authorized?(current_user, permissions) do
      # Tool logic here
    else
      {:error, "Unauthorized", frame}
    end
  end
end
```

The Frame provides access to:
- `assigns` - User data from `conn.assigns` (authentication, business context)
- `transport` - Request metadata (headers, query params, IP address)
- `private` - MCP session data (session ID, client info, protocol version)
- `request` - Current MCP request being processed

## Return Types

All component callbacks must return one of:

- `{:reply, response, frame}` - Success with response
- `{:noreply, frame}` - Success without response or delayed response
- `{:error, error, frame}` - Error response

Where:
- `response` is built using `Hermes.Server.Response`
- `error` can be a string or `Hermes.MCP.Error`
- `frame` is the updated frame state

## Schema Definition

### Traditional Peri Schema

You can use standard Peri schema syntax:

```elixir
schema do
  %{
    name: {:required, :string},
    age: {:integer, {:default, 25}},
    tags: {:list, :string}
  }
end
```

### Field Macro with Metadata

For richer JSON Schema output, use the `field` macro:

```elixir
schema do
  field :email, :string, required: true, format: "email", description: "Contact email"
  field :phone, :string, format: "phone"
  field :birth_date, :date, required: true, description: "Date of birth"
  
  field :preferences do
    field :theme, {:enum, ["light", "dark"]}, type: :string, description: "UI theme"
    field :notifications, :boolean, description: "Email notifications"
  end
end
```

### Enum Fields with Type

When using enum fields, you can specify the underlying type for proper JSON Schema generation:

```elixir
schema do
  field :weight, :integer, required: true
  field :unit, {:enum, ["kg", "lb"]}, required: true, type: :string
  field :status, {:enum, ["active", "inactive", "pending"]}, type: :string, description: "Current status"
end
```

This generates the following JSON Schema:

```json
{
  "properties": {
    "weight": {"type": "integer"},
    "unit": {
      "type": "string",
      "enum": ["kg", "lb"]
    },
    "status": {
      "type": "string", 
      "enum": ["active", "inactive", "pending"],
      "description": "Current status"
    }
  },
  "required": ["weight", "unit"]
}
```

Supported metadata options:
- `format`: JSON Schema format hint (email, uri, date, date-time, phone, etc.)
- `description`: Human-readable field description
- `type`: Explicit type for enum fields (string, integer, etc.)
- `required`: Boolean indicating if field is required (cleaner than `{:required, type}`)

Both schema styles work together - choose based on whether you need JSON Schema metadata.

## Supported Types

Hermes provides automatic type conversion between JSON and Elixir types through its schema system.

### Basic Types

| Type | JSON Input | Elixir Output | Example |
|------|------------|---------------|---------|
| `:string` | `"hello"` | `"hello"` | Basic string |
| `:integer` | `42` | `42` | Number without decimals |
| `:float` | `3.14` | `3.14` | Number with decimals |
| `:boolean` | `true` | `true` | Boolean value |
| `:any` | Any valid JSON | As-is | Accepts any value |

### Date and Time Types

Hermes automatically parses ISO 8601 formatted strings into Elixir date/time structs:

| Type | JSON Input | Elixir Output | Example |
|------|------------|---------------|---------|
| `:date` | `"2024-01-15"` | `~D[2024-01-15]` | ISO 8601 date |
| `:time` | `"14:30:00"` | `~T[14:30:00]` | ISO 8601 time |
| `:datetime` | `"2024-01-15T14:30:00Z"` | `~U[2024-01-15 14:30:00Z]` | ISO 8601 datetime with timezone |
| `:naive_datetime` | `"2024-01-15T14:30:00"` | `~N[2024-01-15 14:30:00]` | ISO 8601 datetime without timezone |

Example usage:

```elixir
defmodule MyServer.Tools.EventScheduler do
  use Hermes.Server.Component, type: :tool

  schema do
    field :event_date, :date, required: true, description: "Date of the event"
    field :start_time, :time, required: true, description: "Event start time"
    field :created_at, :datetime, description: "When the event was created"
  end

  @impl true
  def execute(%{event_date: date, start_time: time} = params, frame) do
    # date is already a Date struct: ~D[2024-01-15]
    # time is already a Time struct: ~T[14:30:00]
    
    {:reply, Response.text(Response.tool(), "Event scheduled for #{date} at #{time}"), frame}
  end
end
```

### Collection Types

| Type | JSON Input | Elixir Output | Example |
|------|------------|---------------|---------|
| `{:list, type}` | `[...]` | `[...]` | List of specified type |
| `{:map, type}` | `{...}` | `%{...}` | Map with string keys |

### Constraint Types

| Type | Description | Example |
|------|-------------|---------|
| `{:enum, choices}` | Value must be one of the choices | `{:enum, ["active", "inactive"]}` * |
| `{:string, {:min, n}}` | String with minimum length | `{:string, {:min, 3}}` |
| `{:string, {:max, n}}` | String with maximum length | `{:string, {:max, 100}}` |
| `{:integer, {:min, n}}` | Integer >= n | `{:integer, {:min, 0}}` |
| `{:integer, {:max, n}}` | Integer <= n | `{:integer, {:max, 100}}` |
| `{:integer, {:range, {min, max}}}` | Integer in range | `{:integer, {:range, {1, 100}}}` |

\* Note: When using enum with the field macro, add `type: :string` for proper JSON Schema generation.

### Error Handling

When validation fails, Hermes provides clear error messages:

- Invalid date format: `"invalid ISO 8601 date format"`
- Missing required field: `"is required"`
- Type mismatch: Detailed error with expected type

### Best Practices

1. Use specific types (`:date`, `:datetime`) instead of generic `:string` when dealing with temporal data
2. Add descriptions to fields for better API documentation
3. Use the `required: true` option instead of wrapping types with `{:required, type}`
4. Leverage enums for fields with known valid values
5. Use appropriate format hints for strings (email, uri, etc.)

## Next Steps

- Configure [Transport Options](server_transport.md) for different connection types
