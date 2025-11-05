# Architecture

<details>
<summary>Relevant source files</summary>

The following files were used as context for generating this wiki page:

- [CHANGELOG.md](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/CHANGELOG.md)
- [CLAUDE.md](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/CLAUDE.md)
- [lib/hermes.ex](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes.ex)
- [lib/hermes/client/state.ex](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/client/state.ex)
- [mix.exs](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/mix.exs)
- [test/support/stub_transport.ex](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/test/support/stub_transport.ex)
- [test/test_helper.exs](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/test/test_helper.exs)

</details>



This document provides a comprehensive overview of the hermes-mcp system architecture, covering the core protocol implementation, transport abstractions, client/server frameworks, and supporting infrastructure. 

For detailed information about specific architectural components, see [MCP Protocol](#3.1), [Transport Layer](#3.2), [Client Architecture](#3.3), and [Server Architecture](#3.4).

## System Overview

Hermes-mcp implements the Model Context Protocol (MCP) specification as an Elixir/OTP application. The system is designed around a layered architecture that separates protocol concerns from transport mechanisms and provides high-level abstractions for building both MCP clients and servers.

### High-Level System Architecture

```mermaid
graph TB
    subgraph "Application Layer"
        HermesClient["Hermes.Client<br/>High-level Client DSL"]
        HermesServer["Hermes.Server<br/>High-level Server DSL"]
        HermesCLI["Hermes.CLI<br/>Standalone Binary"]
    end
    
    subgraph "Core Framework"
        ClientBase["Hermes.Client.Base<br/>GenServer Implementation"]
        ServerBase["Hermes.Server.Base<br/>GenServer Implementation"]
        ClientState["Hermes.Client.State<br/>Request/Session Management"]
        ServerSession["Hermes.Server.Session<br/>Per-client State"]
    end
    
    subgraph "MCP Protocol Layer"
        MCPMessage["Hermes.MCP.Message<br/>JSON-RPC 2.0 Protocol"]
        MCPID["Hermes.MCP.ID<br/>Unique ID Generation"]
        MCPError["Hermes.MCP.Error<br/>Standardized Errors"]
    end
    
    subgraph "Transport Abstraction"
        TransportBehaviour["Hermes.Transport.Behaviour<br/>Common Interface"]
        ClientSTDIO["Hermes.Transport.STDIO"]
        ClientSSE["Hermes.Transport.SSE"]
        ClientWS["Hermes.Transport.WebSocket"]
        ClientHTTP["Hermes.Transport.StreamableHTTP"]
    end
    
    subgraph "Server Components"
        ServerComponent["Hermes.Server.Component<br/>Tools/Prompts/Resources"]
        ServerHandlers["Hermes.Server.Handlers<br/>Request Processing"]
        ServerRegistry["Hermes.Server.Registry<br/>Component Registration"]
    end
    
    subgraph "OTP Supervision"
        ClientSup["Hermes.Client.Supervisor"]
        ServerSup["Hermes.Server.Supervisor"]
        HermesApp["Hermes.Application<br/>Root Supervisor"]
    end
    
    subgraph "Observability"
        HermesTelemetry["Hermes.Telemetry<br/>Event Emission"]
        HermesLogging["Hermes.Logging<br/>Structured Logging"]
    end
    
    %% Application to Framework
    HermesClient --> ClientBase
    HermesServer --> ServerBase
    HermesCLI --> ClientBase
    HermesCLI --> ServerBase
    
    %% Framework internals
    ClientBase --> ClientState
    ServerBase --> ServerSession
    ClientBase --> MCPMessage
    ServerBase --> MCPMessage
    
    %% Protocol layer
    MCPMessage --> MCPID
    MCPMessage --> MCPError
    
    %% Transport connections
    ClientBase --> TransportBehaviour
    ServerBase --> TransportBehaviour
    TransportBehaviour --> ClientSTDIO
    TransportBehaviour --> ClientSSE
    TransportBehaviour --> ClientWS
    TransportBehaviour --> ClientHTTP
    
    %% Server components
    ServerBase --> ServerComponent
    ServerBase --> ServerHandlers
    ServerBase --> ServerRegistry
    
    %% Supervision
    ClientSup --> ClientBase
    ServerSup --> ServerBase
    HermesApp --> ClientSup
    HermesApp --> ServerSup
    
    %% Observability
    ClientBase --> HermesTelemetry
    ServerBase --> HermesTelemetry
    ClientSTDIO --> HermesLogging
    ClientSSE --> HermesLogging
```

Sources: [lib/hermes.ex:1-47](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes.ex#L1-L47), [mix.exs:1-166](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/mix.exs#L1-L166), [lib/hermes/client/state.ex:1-706](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/client/state.ex#L1-L706)

## Core Protocol Implementation

The MCP protocol implementation forms the foundation of the system, handling JSON-RPC 2.0 message encoding/decoding, unique ID generation, and standardized error handling.

### Protocol Message Flow

```mermaid
sequenceDiagram
    participant C as "Hermes.Client.Base"
    participant M as "Hermes.MCP.Message"
    participant T as "Transport Layer"
    participant S as "Hermes.Server.Base"
    
    C->>M: "Message.encode_request/2"
    M->>C: "Encoded JSON-RPC message"
    C->>T: "send_message/2"
    T->>S: "Raw message"
    S->>M: "Message.decode/1"
    M->>S: "Parsed message struct"
    S->>M: "Message.encode_response/2"
    M->>S: "Encoded response"
    S->>T: "send_message/2"
    T->>C: "Raw response"
    C->>M: "Message.decode/1"
    M->>C: "Response struct"
```

The protocol layer provides these key abstractions:
- **Message Encoding/Decoding**: `Hermes.MCP.Message` handles all JSON-RPC 2.0 serialization
- **ID Management**: `Hermes.MCP.ID` generates unique request and session identifiers
- **Error Standardization**: `Hermes.MCP.Error` provides consistent error representations

Sources: [CLAUDE.md:32-40](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/CLAUDE.md#L32-L40), [lib/hermes/client/state.ex:42-47](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/client/state.ex#L42-L47)

## Transport Abstraction Layer

The transport layer provides a common interface for different communication mechanisms while maintaining protocol independence.

### Transport Architecture

```mermaid
graph TB
    subgraph "Transport Interface"
        Behaviour["Hermes.Transport.Behaviour<br/>start_link/1<br/>send_message/2<br/>shutdown/1"]
    end
    
    subgraph "Client Transports"
        STDIO["Hermes.Transport.STDIO<br/>Process Communication"]
        SSE["Hermes.Transport.SSE<br/>HTTP + Server-Sent Events"]
        WS["Hermes.Transport.WebSocket<br/>Full-duplex Communication"]
        HTTP["Hermes.Transport.StreamableHTTP<br/>HTTP Streaming"]
    end
    
    subgraph "Server Transports"
        ServerSTDIO["Hermes.Server.Transport.STDIO"]
        ServerSSE["Hermes.Server.Transport.SSE"]
        ServerHTTP["Hermes.Server.Transport.StreamableHTTP"]
    end
    
    subgraph "Transport Configuration"
        ClientTransport["client_transport schema<br/>layer: enum<br/>name: process_name"]
        ServerTransport["server_transport schema<br/>layer: enum<br/>name: process_name"]
    end
    
    %% Interface implementations
    STDIO -.->|implements| Behaviour
    SSE -.->|implements| Behaviour
    WS -.->|implements| Behaviour
    HTTP -.->|implements| Behaviour
    
    %% Configuration
    ClientTransport --> STDIO
    ClientTransport --> SSE
    ClientTransport --> WS
    ClientTransport --> HTTP
    
    ServerTransport --> ServerSTDIO
    ServerTransport --> ServerSSE
    ServerTransport --> ServerHTTP
```

Each transport implementation provides:
- **Process Management**: OTP-compliant GenServer lifecycle
- **Message Routing**: Bidirectional communication with client/server processes
- **Connection Handling**: Transport-specific connection management and recovery

Sources: [lib/hermes.ex:21-28](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes.ex#L21-L28), [CLAUDE.md:42-48](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/CLAUDE.md#L42-L48)

## Client Framework Architecture

The client framework provides a stateful, high-level interface for MCP operations with automatic request tracking and capability validation.

### Client Component Relationships

```mermaid
graph TB
    subgraph "Client API Layer"
        HermesClient["Hermes.Client<br/>High-level DSL"]
    end
    
    subgraph "Client Core"
        ClientBase["Hermes.Client.Base<br/>GenServer<br/>handle_call/3<br/>handle_cast/2<br/>handle_info/2"]
        ClientState["Hermes.Client.State<br/>%__MODULE__{<br/>  pending_requests<br/>  server_capabilities<br/>  progress_callbacks<br/>  transport<br/>}"]
    end
    
    subgraph "Request Management"
        Operation["Hermes.Client.Operation<br/>%__MODULE__{<br/>  method<br/>  params<br/>  timeout<br/>  progress_opts<br/>}"]
        Request["Hermes.Client.Request<br/>%__MODULE__{<br/>  id<br/>  from<br/>  timer_ref<br/>  batch_id<br/>}"]
    end
    
    subgraph "OTP Supervision"
        ClientSup["Hermes.Client.Supervisor<br/>DynamicSupervisor"]
    end
    
    %% API relationships
    HermesClient --> ClientBase
    ClientBase --> ClientState
    
    %% State management
    ClientState --> Operation
    ClientState --> Request
    
    %% Request lifecycle
    ClientBase -->|"add_request_from_operation/3"| ClientState
    ClientState -->|"Process.send_after/3"| Request
    ClientBase -->|"remove_request/2"| ClientState
    
    %% Supervision
    ClientSup --> ClientBase
```

Key client framework features:
- **State Management**: `Hermes.Client.State` tracks pending requests, server capabilities, and progress callbacks
- **Request Lifecycle**: Automatic timeout handling and request correlation
- **Capability Validation**: Server capability checking before operation execution
- **Progress Tracking**: Support for MCP progress notifications with user callbacks

Sources: [lib/hermes/client/state.ex:1-706](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/client/state.ex#L1-L706), [CLAUDE.md:50-59](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/CLAUDE.md#L50-L59)

## Server Framework Architecture

The server framework provides a component-based system for implementing MCP servers with tools, prompts, and resources.

### Server Component System

```mermaid
graph TB
    subgraph "Server API Layer"
        HermesServer["Hermes.Server<br/>High-level DSL<br/>defserver/2<br/>component/2"]
    end
    
    subgraph "Server Core"
        ServerBase["Hermes.Server.Base<br/>GenServer<br/>handle_request/2<br/>handle_notification/2<br/>server_info/0"]
        ServerSession["Hermes.Server.Session<br/>Per-client State"]
    end
    
    subgraph "Component System"
        ServerComponent["Hermes.Server.Component<br/>deftool/2<br/>defprompt/2<br/>defresource/2"]
        ServerHandlers["Hermes.Server.Handlers<br/>tools_list/2<br/>tools_call/2<br/>prompts_list/2<br/>resources_list/2"]
        ServerRegistry["Hermes.Server.Registry<br/>Component Registration<br/>server/1<br/>register/2"]
    end
    
    subgraph "Component Types"
        Tool["Tool Components<br/>Executable Functions<br/>JSON Schema"]
        Prompt["Prompt Components<br/>Message Templates<br/>Arguments"]
        Resource["Resource Components<br/>Data Providers<br/>URI-based"]
    end
    
    subgraph "OTP Supervision"
        ServerSup["Hermes.Server.Supervisor<br/>DynamicSupervisor"]
    end
    
    %% API relationships
    HermesServer --> ServerBase
    ServerBase --> ServerSession
    
    %% Component system
    HermesServer --> ServerComponent
    ServerComponent --> Tool
    ServerComponent --> Prompt
    ServerComponent --> Resource
    
    %% Request handling
    ServerBase --> ServerHandlers
    ServerHandlers --> ServerRegistry
    ServerRegistry --> ServerComponent
    
    %% Supervision
    ServerSup --> ServerBase
```

Server framework capabilities:
- **Component Definition**: High-level DSL for defining tools, prompts, and resources
- **JSON Schema Generation**: Automatic schema creation for component parameters
- **Request Dispatch**: Automatic routing of MCP requests to appropriate handlers
- **Session Management**: Per-client state isolation and management

Sources: [CLAUDE.md:61-68](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/CLAUDE.md#L61-L68), [lib/hermes.ex:25-28](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes.ex#L25-L28)

## Build and Release Architecture

The system includes a comprehensive build pipeline using Nix for reproducible builds and cross-platform binary distribution.

### Build System Components

| Component | Purpose | Configuration |
|-----------|---------|---------------|
| **Nix Flake** | Reproducible development environment | Development dependencies, Elixir/Erlang versions |
| **Mix Project** | Elixir build configuration | Dependencies, releases, compilation paths |
| **Burrito** | Binary packaging | Cross-platform standalone executables |
| **GitHub Actions** | CI/CD pipeline | Testing, linting, release automation |
| **Release Please** | Automated versioning | Changelog generation, semantic versioning |

The build system supports:
- **Cross-platform Targets**: macOS (Intel/ARM), Linux, Windows
- **Standalone Binaries**: Self-contained executables via Burrito
- **Development Tools**: Interactive CLI for testing MCP implementations

Sources: [mix.exs:60-82](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/mix.exs#L60-L82), [CHANGELOG.md:1-271](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/CHANGELOG.md#L1-L271)

## Observability and Monitoring

### Telemetry Architecture

```mermaid
graph TB
    subgraph "Event Sources"
        ClientEvents["Client Events<br/>event_client_init/0<br/>event_client_request/0<br/>event_client_response/0"]
        ServerEvents["Server Events<br/>event_server_init/0<br/>event_server_request/0<br/>event_server_response/0"]
        TransportEvents["Transport Events<br/>Connection lifecycle<br/>Message routing"]
    end
    
    subgraph "Telemetry System"
        HermesTelemetry["Hermes.Telemetry<br/>Event emission<br/>execute/3"]
        TelemetryEvents[":telemetry.execute/3<br/>Standard Telemetry"]
    end
    
    subgraph "Logging System"
        HermesLogging["Hermes.Logging<br/>client_event/2<br/>server_event/2<br/>message/4"]
        ElixirLogger["Logger<br/>Structured logging"]
    end
    
    %% Event flow
    ClientEvents --> HermesTelemetry
    ServerEvents --> HermesTelemetry
    TransportEvents --> HermesLogging
    
    %% System integration
    HermesTelemetry --> TelemetryEvents
    HermesLogging --> ElixirLogger
```

The observability system provides:
- **Structured Events**: Standardized telemetry events for client/server operations
- **Request Tracing**: Correlation of requests across transport boundaries
- **Performance Metrics**: Timing and throughput measurements
- **Error Tracking**: Comprehensive error classification and reporting