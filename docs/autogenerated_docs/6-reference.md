# Reference

<details>
<summary>Relevant source files</summary>

The following files were used as context for generating this wiki page:

- [lib/hermes/logging.ex](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/logging.ex)
- [lib/hermes/server.ex](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/server.ex)
- [lib/hermes/server/session.ex](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/server/session.ex)
- [lib/hermes/telemetry.ex](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/telemetry.ex)
- [test/hermes/logging_test.exs](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/test/hermes/logging_test.exs)

</details>



This page provides detailed API reference documentation for the Hermes MCP system. It covers core module interfaces, data structures, configuration formats, and protocol specifications that developers need when building with or extending Hermes.

For specific configuration options and environment variables, see [Configuration](#6.1). For logging and telemetry system details, see [Logging and Telemetry](#6.2).

## Core API Modules

The Hermes MCP system exposes several primary modules that form the foundation of client and server implementations.

### Core API Module Relationships

```mermaid
graph TB
    Server["Hermes.Server"] --> ServerBase["Hermes.Server.Base"]
    Server --> ServerSession["Hermes.Server.Session"]
    Server --> ServerComponent["Hermes.Server.Component"]
    
    Client["Hermes.Client"] --> ClientBase["Hermes.Client.Base"]
    Client --> ClientState["Hermes.Client.State"]
    
    ServerBase --> MCPMessage["Hermes.MCP.Message"]
    ClientBase --> MCPMessage
    
    ServerBase --> Logging["Hermes.Logging"]
    ClientBase --> Logging
    
    ServerBase --> Telemetry["Hermes.Telemetry"]
    ClientBase --> Telemetry
    
    ServerSession --> SessionAgent["Agent"]
    ClientState --> StateAgent["Agent"]
    
    subgraph "Core Protocol"
        MCPMessage
        MCPError["Hermes.MCP.Error"]
        MCPID["Hermes.MCP.ID"]
    end
    
    subgraph "Observability"
        Logging
        Telemetry
    end
```

Sources: [lib/hermes/server.ex:1-244](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/server.ex#L1-L244), [lib/hermes/server/session.ex:1-227](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/server/session.ex#L1-L227), [lib/hermes/telemetry.ex:1-97](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/telemetry.ex#L1-L97), [lib/hermes/logging.ex:1-183](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/logging.ex#L1-L183)

### Server API Reference

The `Hermes.Server` module provides the primary DSL for implementing MCP servers.

#### Server Configuration Options

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `:name` | `String.t()` | Server name (required) | N/A |
| `:version` | `String.t()` | Server version (required) | N/A |
| `:capabilities` | `list(atom())` | Supported capabilities | `[]` |
| `:protocol_versions` | `list(String.t())` | Supported protocol versions | `["2025-03-26", "2024-10-07", "2024-05-11"]` |

#### Supported Capabilities

```mermaid
graph LR
    subgraph "Server Capabilities"
        Prompts["prompts"]
        Tools["tools"]
        Resources["resources"]
        Logging["logging"]
    end
    
    subgraph "Capability Options"
        ResourcesSub["resources: subscribe?: boolean"]
        ResourcesChanged["resources: list_changed?: boolean"]
        PromptsChanged["prompts: list_changed?: boolean"]
        ToolsChanged["tools: list_changed?: boolean"]
    end
    
    Resources --> ResourcesSub
    Resources --> ResourcesChanged
    Prompts --> PromptsChanged
    Tools --> ToolsChanged
```

Sources: [lib/hermes/server.ex:57-58](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/server.ex#L57-L58), [lib/hermes/server.ex:168-188](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/server.ex#L168-L188)

#### Server Behaviour Callbacks

The `Hermes.Server.Behaviour` defines required callbacks:

- `init/2` - Initialize server state
- `handle_request/2` - Handle incoming MCP requests
- `handle_notification/2` - Handle incoming notifications
- `server_info/0` - Return server metadata
- `server_capabilities/0` - Return supported capabilities
- `supported_protocol_versions/0` - Return protocol versions

Sources: [lib/hermes/server.ex:16-31](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/server.ex#L16-L31), [lib/hermes/server.ex:150-163](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/server.ex#L150-L163)

## Session Management

The session system manages per-client state and request tracking for MCP servers.

### Session Data Structure

```mermaid
graph TB
    Session["Hermes.Server.Session"] --> Fields["Session Fields"]
    
    Fields --> ID["id: String.t()"]
    Fields --> Protocol["protocol_version: String.t()"]
    Fields --> Initialized["initialized: boolean()"]
    Fields --> Name["name: GenServer.name()"]
    Fields --> ClientInfo["client_info: map()"]
    Fields --> ClientCaps["client_capabilities: map()"]
    Fields --> LogLevel["log_level: String.t()"]
    Fields --> PendingReqs["pending_requests: map()"]
    
    PendingReqs --> ReqStruct["Request Info"]
    ReqStruct --> StartedAt["started_at: integer()"]
    ReqStruct --> Method["method: String.t()"]
```

Sources: [lib/hermes/server/session.ex:20-40](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/server/session.ex#L20-L40)

### Session API Functions

| Function | Parameters | Return Type | Description |
|----------|------------|-------------|-------------|
| `new/1` | `opts :: Enumerable.t()` | `t()` | Create new session |
| `get/1` | `session :: GenServer.name()` | `t()` | Get current session state |
| `mark_initialized/1` | `session :: GenServer.name()` | `:ok` | Mark session as initialized |
| `set_log_level/2` | `session, level :: String.t()` | `:ok` | Update log level |
| `track_request/3` | `session, id, method :: String.t()` | `:ok` | Track pending request |
| `complete_request/2` | `session, id :: String.t()` | `map() \| nil` | Complete request tracking |

Sources: [lib/hermes/server/session.ex:53-226](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/server/session.ex#L53-L226)

### Session Lifecycle

```mermaid
sequenceDiagram
    participant C as "Client"
    participant S as "Server"
    participant Session as "Session Agent"
    
    C->>S: initialize request
    S->>Session: new(opts)
    Session-->>S: session created
    
    S->>Session: update_from_initialization()
    S->>Session: mark_initialized()
    Session-->>S: session ready
    
    C->>S: request
    S->>Session: track_request(id, method)
    S-->>C: processing...
    S->>Session: complete_request(id)
    S-->>C: response
```

Sources: [lib/hermes/server/session.ex:116-130](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/server/session.ex#L116-L130), [lib/hermes/server/session.ex:154-189](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/server/session.ex#L154-L189)

## Logging System Reference

The logging system provides structured, configurable logging across all Hermes components.

### Log Event Types

```mermaid
graph TB
    LoggingAPI["Hermes.Logging"] --> EventTypes["Event Types"]
    
    EventTypes --> ClientEvents["client_events"]
    EventTypes --> ServerEvents["server_events"] 
    EventTypes --> TransportEvents["transport_events"]
    EventTypes --> ProtocolMessages["protocol_messages"]
    
    ClientEvents --> ClientLevel["Default: :debug"]
    ServerEvents --> ServerLevel["Default: :debug"]
    TransportEvents --> TransportLevel["Default: :debug"]
    ProtocolMessages --> ProtocolLevel["Default: :debug"]
    
    subgraph "Log Levels"
        Debug[":debug"]
        Info[":info"]
        Notice[":notice"]
        Warning[":warning"]
        Error[":error"]
        Critical[":critical"]
        Alert[":alert"]
        Emergency[":emergency"]
    end
```

Sources: [lib/hermes/logging.ex:8-22](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/logging.ex#L8-L22), [lib/hermes/logging.ex:114-122](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/logging.ex#L114-L122)

### Logging API Functions

| Function | Parameters | Description |
|----------|------------|-------------|
| `message/5` | `direction, type, id, data, metadata` | Log protocol messages |
| `client_event/3` | `event, details, metadata` | Log client lifecycle events |
| `server_event/3` | `event, details, metadata` | Log server lifecycle events |
| `transport_event/3` | `event, details, metadata` | Log transport layer events |

Sources: [lib/hermes/logging.ex:26-102](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/logging.ex#L26-L102)

## Telemetry System Reference

The telemetry system emits structured events for monitoring and observability.

### Telemetry Event Naming

All telemetry events follow the pattern: `[:hermes_mcp, component, action]`

```mermaid
graph TB
    Namespace["[:hermes_mcp]"] --> Components["Components"]
    
    Components --> Client[":client"]
    Components --> Server[":server"]
    Components --> Transport[":transport"]
    Components --> Message[":message"]
    Components --> Progress[":progress"]
    
    Client --> ClientActions["Actions"]
    Server --> ServerActions["Actions"]
    Transport --> TransportActions["Actions"]
    
    ClientActions --> CInit[":init"]
    ClientActions --> CRequest[":request"]
    ClientActions --> CResponse[":response"]
    ClientActions --> CError[":error"]
    
    ServerActions --> SInit[":init"]
    ServerActions --> SToolCall[":tool_call"]
    ServerActions --> SResourceRead[":resource_read"]
    
    TransportActions --> TConnect[":connect"]
    TransportActions --> TSend[":send"]
    TransportActions --> TReceive[":receive"]
```

Sources: [lib/hermes/telemetry.ex:8-37](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/telemetry.ex#L8-L37), [lib/hermes/telemetry.ex:53-96](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/telemetry.ex#L53-L96)

### Telemetry Event Constants

The telemetry module provides event name constants:

```elixir
# Client events
Hermes.Telemetry.event_client_init()      # [:client, :init]
Hermes.Telemetry.event_client_request()   # [:client, :request]
Hermes.Telemetry.event_client_response()  # [:client, :response]

# Server events  
Hermes.Telemetry.event_server_tool_call() # [:server, :tool_call]
Hermes.Telemetry.event_server_resource_read() # [:server, :resource_read]

# Transport events
Hermes.Telemetry.event_transport_connect() # [:transport, :connect]
Hermes.Telemetry.event_transport_send()    # [:transport, :send]
```

Sources: [lib/hermes/telemetry.ex:55-81](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/telemetry.ex#L55-L81)

## Configuration Schema

The system supports configuration through application environment variables under the `:hermes_mcp` key.

### Configuration Structure

```mermaid
graph TB
    HermesConfig[":hermes_mcp"] --> LogConfig[":log"]
    HermesConfig --> LoggingConfig[":logging"]
    
    LogConfig --> LogEnabled["true | false"]
    
    LoggingConfig --> ClientEventsLevel["client_events: log_level"]
    LoggingConfig --> ServerEventsLevel["server_events: log_level"]
    LoggingConfig --> TransportEventsLevel["transport_events: log_level"]
    LoggingConfig --> ProtocolMessagesLevel["protocol_messages: log_level"]
    
    subgraph "Log Levels"
        DebugLevel[":debug"]
        InfoLevel[":info"]
        WarningLevel[":warning"]
        ErrorLevel[":error"]
    end
```

Sources: [lib/hermes/logging.ex:8-22](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/logging.ex#L8-L22), [lib/hermes/logging.ex:112-122](https://github.com/cloudwalk/hermes-mcp/blob/8db7a927/lib/hermes/logging.ex#L112-L122)

### Global Configuration Options

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `:log` | `boolean()` | `true` | Enable/disable all Hermes logging |
| `:logging` | `keyword()` | `[]` | Per-event-type log level configuration |