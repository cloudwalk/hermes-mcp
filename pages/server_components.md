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
    %{
      a: {:required, :number},
      b: {:required, :number}
    }
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
    field :email, {:required, :string}, format: "email", description: "User's email address"
    field :age, {:integer, {:range, {0, 150}}}, description: "Age in years"
    field :website, :string, format: "uri"
    
    field :address, description: "Mailing address" do
      field :street, {:required, :string}
      field :city, {:required, :string}
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
    %{
      a: {:required, :number},
      b: {:required, :number}
    }
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
    %{style: {:required, {:enum, ["formal", "casual"]}}}
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
    %{language: {:required, :string}}
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
    field :document, {:required, :string}, description: "The document text to analyze"
    field :language, {:required, :string}, description: "Document language (e.g., 'en', 'es', 'fr')"
    field :analysis_type, {:enum, ["summary", "sentiment", "keywords"]}, 
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
  field :email, {:required, :string}, format: "email", description: "Contact email"
  field :phone, :string, format: "phone"
  field :birth_date, :string, format: "date", description: "YYYY-MM-DD"
  
  field :preferences do
    field :theme, {:enum, ["light", "dark"]}, description: "UI theme"
    field :notifications, :boolean, description: "Email notifications"
  end
end
```

Supported metadata options:
- `format`: JSON Schema format hint (email, uri, date, date-time, phone, etc.)
- `description`: Human-readable field description

Both schema styles work together - choose based on whether you need JSON Schema metadata.

## Next Steps

- Configure [Transport Options](server_transport.md) for different connection types
