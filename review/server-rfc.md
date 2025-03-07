# RFC: Server-Side Implementation for Hermes MCP

## 1. Introduction

This RFC proposes a comprehensive server-side implementation for Hermes MCP, complementing the existing client functionality. The server implementation will follow Elixir/OTP best practices and Phoenix conventions while maintaining full compliance with the Model Context Protocol specification.

## 2. Server Architecture

We propose organizing the server-side implementation following Phoenix-inspired patterns for clarity and maintainability. This approach will leverage familiar design patterns while adapting them specifically for MCP server requirements.

### 2.1. Module Structure

```
lib/
  hermes/
    server/
      # Core server functionality
      application.ex       # Server application supervisor
      config.ex            # Server configuration management
      context.ex           # Execution context for requests
      endpoint.ex          # HTTP endpoint configuration
      handler.ex           # Base handler behavior
      registry.ex          # Registry for handlers
      session.ex           # Session management
      supervisor.ex        # Server supervision tree
      
      handlers/            # Specific capability handlers
        resources.ex       # Resources capability handlers
        prompts.ex         # Prompts capability handlers  
        tools.ex           # Tools capability handlers
        logging.ex         # Logging capability handlers
      
      transports/          # Server transport implementations
        http.ex            # HTTP transport
        sse.ex             # SSE transport
        
      phoenix/             # Phoenix integration
        controllers/
          mcp_controller.ex # HTTP JSON-RPC controller
        channels/
          mcp_channel.ex   # WebSocket channel (future)
        plugs/
          mcp_plug.ex      # Pipeline for MCP request handling
```

### 2.2. Server Core Components

#### Server Module

```elixir
defmodule Hermes.Server do
  @moduledoc """
  The main server module for Hermes MCP.
  
  This module provides the primary API for configuring and starting
  an MCP server, registering handlers, and managing server lifecycle.
  """
  
  @type server_option ::
    {:name, atom()} |
    {:port, pos_integer()} |
    {:server_info, map()} |
    {:capabilities, map()} |
    {:protocol_version, String.t()} |
    {:handlers, list(module())}
  
  @doc """
  Starts a new MCP server with the given options.
  
  ## Options
  
    * `:name` - Optional name to register the server (default: Hermes.Server)
    * `:port` - The port to listen on for HTTP requests (default: 4000)
    * `:server_info` - Information about the server (required)
    * `:capabilities` - Server capabilities to advertise (default: empty)
    * `:protocol_version` - Protocol version to use (default: "2024-11-05")
    * `:handlers` - List of handler modules to register
  """
  @spec start_link([server_option()]) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    # Implementation
  end
  
  @doc """
  Registers a handler module with the server.
  
  Handler modules implement the Hermes.Server.Handler behavior
  and provide the implementation for specific MCP methods.
  """
  @spec register_handler(server :: atom(), handler :: module()) :: :ok | {:error, term()}
  def register_handler(server, handler) do
    # Implementation
  end
  
  @doc """
  Returns the current server configuration.
  """
  @spec config(server :: atom()) :: map()
  def config(server) do
    # Implementation
  end
  
  @doc """
  Stops the server.
  """
  @spec stop(server :: atom()) :: :ok
  def stop(server) do
    # Implementation
  end
end
```

#### Handler Behavior

```elixir
defmodule Hermes.Server.Handler do
  @moduledoc """
  Behavior for implementing MCP method handlers.
  
  Handlers provide implementations for specific MCP methods,
  such as resource management, tool execution, etc.
  """
  
  @type context :: Hermes.Server.Context.t()
  @type method :: String.t()
  @type params :: map()
  @type result :: {:ok, map()} | {:error, map()} | {:async, pid()}
  
  @doc """
  Returns a list of methods that this handler supports.
  """
  @callback methods() :: [method()]
  
  @doc """
  Handles an MCP method call.
  
  The context contains information about the client session,
  request metadata, and utilities for responding.
  
  Returns:
  - `{:ok, result}` for successful synchronous responses
  - `{:error, error}` for error responses
  - `{:async, pid}` for long-running operations that will respond later
  """
  @callback handle(context(), method(), params()) :: result()
end
```

#### Context Module

```elixir
defmodule Hermes.Server.Context do
  @moduledoc """
  Provides context for handling MCP requests.
  
  The context contains information about the client session,
  request metadata, and utilities for responding to requests.
  """
  
  @type t :: %__MODULE__{
    client_id: String.t(),
    request_id: String.t(),
    client_info: map(),
    client_capabilities: map(),
    meta: map(),
    session: pid()
  }
  
  defstruct [
    :client_id,
    :request_id,
    :client_info,
    :client_capabilities,
    meta: %{},
    session: nil
  ]
  
  @doc """
  Sends a progress notification to the client.
  """
  @spec send_progress(t(), String.t(), number(), number() | nil) :: :ok | {:error, term()}
  def send_progress(context, token, progress, total \\ nil) do
    # Implementation
  end
  
  @doc """
  Sends a log message to the client.
  """
  @spec send_log(t(), String.t(), term(), String.t() | nil) :: :ok | {:error, term()}
  def send_log(context, level, data, logger \\ nil) do
    # Implementation
  end
  
  @doc """
  Cancels a request.
  """
  @spec cancel_request(t(), String.t(), String.t()) :: :ok | {:error, term()}
  def cancel_request(context, request_id, reason) do
    # Implementation
  end
end
```

### 2.3. Phoenix Integration

#### Controller Module

```elixir
defmodule Hermes.Server.Phoenix.MCPController do
  @moduledoc """
  Phoenix controller for handling MCP JSON-RPC requests.
  """
  
  use Phoenix.Controller
  
  @doc """
  Handles incoming JSON-RPC requests.
  """
  def handle(conn, _params) do
    # Implementation
  end
  
  @doc """
  Establishes an SSE connection.
  """
  def sse(conn, _params) do
    # Implementation
  end
end
```

#### Plug Pipeline

```elixir
defmodule Hermes.Server.Phoenix.MCPPlug do
  @moduledoc """
  Plug pipeline for processing MCP requests.
  """
  
  use Plug.Router
  
  plug :match
  plug :dispatch
  
  # Match the MCP JSON-RPC endpoint
  post "/mcp" do
    # Implementation
  end
  
  # Match the SSE endpoint
  get "/mcp/stream" do
    # Implementation
  end
  
  # Fallback for all other requests
  match _ do
    send_resp(conn, 404, "Not found")
  end
end
```

### 2.4. Handler Implementations

The following modules would implement the `Hermes.Server.Handler` behavior for different capability areas:

#### Resources Handler

```elixir
defmodule Hermes.Server.Handlers.Resources do
  @moduledoc """
  Handler for resource-related MCP methods.
  """
  
  @behaviour Hermes.Server.Handler
  
  @impl true
  def methods do
    ["resources/list", "resources/read"]
  end
  
  @impl true
  def handle(context, "resources/list", params) do
    # Implementation
  end
  
  @impl true
  def handle(context, "resources/read", %{"uri" => uri}) do
    # Implementation
  end
end
```

Similar handler modules would be implemented for prompts, tools, and logging capabilities.

## 3. Server DSL for Implementation

To make implementing MCP servers easier, we propose a DSL that follows Phoenix-inspired patterns but is specifically tailored for MCP:

```elixir
defmodule MyApp.MCPServer do
  use Hermes.Server, otp_app: :my_app

  # Configure the server
  config server_info: %{
    "name" => "MyApp MCP Server",
    "version" => "1.0.0"
  }
  
  # Define resources
  resources do
    resource "document/main", MyApp.Resources.MainDocument
    resource "database/:id", MyApp.Resources.Database
  end
  
  # Define prompts
  prompts do
    prompt "summarize", MyApp.Prompts.Summarize
    prompt "categorize", MyApp.Prompts.Categorize
  end
  
  # Define tools
  tools do
    tool "search", MyApp.Tools.Search
    tool "calculate", MyApp.Tools.Calculate
  end
  
  # Protocol lifecycle hooks
  on_initialize fn context ->
    # Custom initialization logic
    {:ok, extra_capabilities()}
  end
  
  on_terminate fn context ->
    # Custom termination logic
    :ok
  end
  
  # Plug pipeline for HTTP integration
  pipeline :mcp do
    plug :validate_json
    plug :authenticate
  end
  
  # HTTP endpoint configuration
  scope "/" do
    pipe_through :mcp
    
    mcp_endpoint "/api/mcp"
    sse_endpoint "/api/mcp/stream"
  end
end
```

### 3.1. Resource Implementation

Resources would be implemented using a module-based approach:

```elixir
defmodule MyApp.Resources.MainDocument do
  use Hermes.Server.Resource
  
  @impl true
  def get(_params) do
    # Return the resource content
    {:ok, %{
      "content" => [
        %{
          "type" => "text",
          "text" => "Main document content"
        }
      ]
    }}
  end
end
```

### 3.2. Prompt Implementation

```elixir
defmodule MyApp.Prompts.Summarize do
  use Hermes.Server.Prompt
  
  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "text" => %{
          "type" => "string",
          "description" => "Text to summarize"
        }
      },
      "required" => ["text"]
    }
  end
  
  @impl true
  def execute(params, context) do
    # Implement prompt logic
    text = params["text"]
    summary = generate_summary(text)
    
    {:ok, %{
      "summary" => summary
    }}
  end
  
  defp generate_summary(text) do
    # Implementation
  end
end
```

### 3.3. Tool Implementation

```elixir
defmodule MyApp.Tools.Search do
  use Hermes.Server.Tool
  
  @impl true
  def description do
    "Search for information"
  end
  
  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "query" => %{
          "type" => "string",
          "description" => "Search query"
        }
      },
      "required" => ["query"]
    }
  end
  
  @impl true
  def execute(params, context) do
    query = params["query"]
    
    # For long-running operations, use async response
    {:async, fn ->
      # Report progress
      context |> Hermes.Server.Context.send_progress(context.meta["progressToken"], 0, 100)
      
      # Perform search
      results = perform_search(query)
      
      # Report completion
      context |> Hermes.Server.Context.send_progress(context.meta["progressToken"], 100, 100)
      
      # Return results
      {:ok, %{
        "results" => results
      }}
    end}
  end
  
  defp perform_search(query) do
    # Implementation
  end
end
```

## 4. Session Management

### 4.1. Session Supervisors

Sessions would be managed using dynamic supervision:

```elixir
defmodule Hermes.Server.SessionSupervisor do
  @moduledoc """
  Supervisor for client sessions.
  """
  
  use DynamicSupervisor
  
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
  
  @doc """
  Starts a new session for a client.
  """
  @spec start_session(supervisor :: atom(), map()) :: {:ok, pid()} | {:error, term()}
  def start_session(supervisor, client_info) do
    DynamicSupervisor.start_child(supervisor, {Hermes.Server.Session, client_info})
  end
end
```

### 4.2. Session Implementation

```elixir
defmodule Hermes.Server.Session do
  @moduledoc """
  GenServer representing a client session.
  
  Maintains state for a client connection, including client info,
  capabilities, and active requests.
  """
  
  use GenServer
  
  @impl true
  def init(client_info) do
    {:ok, %{
      client_id: generate_client_id(),
      client_info: client_info,
      client_capabilities: %{},
      active_requests: %{},
      subscriptions: %{}
    }}
  end
  
  # Additional GenServer callbacks
end
```

## 5. Transport Handling

The transport layer would be responsible for handling the communication with clients:

### 5.1. HTTP/SSE Transport

```elixir
defmodule Hermes.Server.Transports.SSE do
  @moduledoc """
  Server-side SSE transport implementation.
  
  Handles establishing SSE connections and sending/receiving messages.
  """
  
  @doc """
  Establishes an SSE connection with a client.
  """
  @spec establish_connection(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def establish_connection(conn, session_info) do
    # Implementation
  end
  
  @doc """
  Sends a message to a client over the SSE connection.
  """
  @spec send_message(pid(), String.t()) :: :ok | {:error, term()}
  def send_message(session, message) do
    # Implementation
  end
end
```

## 6. Telemetry Integration

The server implementation would include comprehensive telemetry support:

```elixir
defmodule Hermes.Server.Telemetry do
  @moduledoc """
  Telemetry integration for Hermes MCP server.
  """
  
  @prefix [:hermes, :mcp, :server]
  
  @doc """
  Emits a telemetry event.
  """
  @spec emit(atom() | list(atom()), map(), map()) :: :ok
  def emit(event, measurements \\ %{}, metadata \\ %{}) do
    :telemetry.execute(@prefix ++ List.wrap(event), measurements, metadata)
  end
  
  @doc """
  Wraps a function with start/stop telemetry events.
  """
  @spec span(atom() | list(atom()), map(), (() -> any())) :: any()
  def span(event, metadata \\ %{}, fun) do
    # Implementation similar to client-side span
  end
end
```

## 7. Implementation Roadmap

### Phase 1: Core Server Structure

1. Define the core server modules and behaviors
2. Implement basic session management
3. Create the registry for MCP method handlers

### Phase 2: Transport and Phoenix Integration

1. Implement HTTP transport with SSE support
2. Create Phoenix controller and plug pipeline
3. Integrate with Phoenix router

### Phase 3: Handler Implementation

1. Implement resource handlers
2. Implement prompt handlers
3. Implement tool handlers
4. Implement logging handlers

### Phase 4: Server DSL

1. Define macros for server configuration
2. Create DSL for resources, prompts, and tools
3. Implement pipeline and endpoint configuration

### Phase 5: Testing and Documentation

1. Create comprehensive tests for all components
2. Document the API and provide usage examples
3. Create integration examples with Phoenix applications

## 8. Conclusion

This RFC proposes a comprehensive server-side implementation for Hermes MCP that follows both Elixir/OTP best practices and Phoenix conventions. The implementation provides a clear and maintainable structure for building MCP servers, with a DSL that makes it easy to define resources, prompts, and tools.

The proposed architecture leverages Phoenix's strengths for HTTP integration while maintaining the flexibility to support other transport mechanisms. The module structure clearly separates concerns while providing a cohesive API for server implementation.

By implementing this proposal, Hermes MCP will provide a complete solution for building both MCP clients and servers in Elixir, making it an ideal choice for MCP-based applications in the ecosystem.