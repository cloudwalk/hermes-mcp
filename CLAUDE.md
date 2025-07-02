# Hermes MCP Development Guide

## Build & Test Commands

```bash
# Setup dependencies
mix deps.get

# Compile code
mix compile --force --warnings-as-errors

# Run all tests
mix test --trace

# Run a single test
mix test test/path/to/test_file.exs:line_number --trace

# Format code
mix format

# Run linting
mix credo --strict

# Type checking
mix dialyzer

# Generate documentation
mix docs
```

## Core Architecture & Design Patterns

### MCP Protocol Handling

- **Message Processing**: ALWAYS use `Hermes.MCP.Message` for all MCP/JSON-RPC message encoding/decoding
  - Use `Message.decode/1` to parse incoming messages
  - Use `Message.encode_request/2`, `Message.encode_response/2`, `Message.encode_notification/1`, `Message.encode_error/2`
  - Use message guards: `is_request/1`, `is_response/1`, `is_notification/1`, `is_error/1`
- **Error Handling**: ALWAYS use `Hermes.MCP.Error` for standardized error representation
  - Use factory functions: `Error.parse_error/1`, `Error.invalid_request/1`, `Error.method_not_found/1`
  - Use `Error.transport_error/2`, `Error.client_error/2`, `Error.domain_error/1` for specialized errors
  - Convert between JSON-RPC: `Error.from_json_rpc/1`, `Error.to_json_rpc!/2`

### Transport Layer Architecture

- **Transport Behaviour**: All transports implement `Hermes.Transport.Behaviour`
  - Required callbacks: `start_link/1`, `send_message/2`, `shutdown/1`
  - Transport modules: `Hermes.Transport.STDIO`, `Hermes.Transport.SSE`, `Hermes.Transport.WebSocket`, `Hermes.Transport.StreamableHTTP`
- **Client Transport Integration**: In `Hermes.Client` use transport via state configuration
  - Store as `%{layer: TransportModule, name: process_name}`
  - Send messages via `transport.layer.send_message(transport.name, data)`

### Client Architecture Patterns

- **State Management**: Use `Hermes.Client.State` for all client state operations
  - Create state: `State.new/1`
  - Request tracking: `State.add_request_from_operation/3`, `State.remove_request/2`
  - Progress callbacks: `State.register_progress_callback/3`, `State.get_progress_callback/2`
  - Capabilities: `State.validate_capability/2`, `State.merge_capabilities/2`
- **Operation Handling**: Use `Hermes.Client.Operation` for request configuration
  - Progress tracking, timeouts, method/params encapsulation
- **Request Management**: Use `Hermes.Client.Request` for request lifecycle tracking
  - ID generation, timing, caller reference management

### Server Architecture Patterns

- **Base Server**: Use `Hermes.Server.Base` as foundation for all MCP servers
  - Implement `Hermes.Server.Behaviour` callbacks in your server module
  - Required: `init/1`, `handle_request/2`, `handle_notification/2`, `server_info/0`
  - Optional: `server_capabilities/0`
- **Server Transport Integration**: Configure transport in server options
  - `transport: [layer: TransportModule, name: process_name]`
  - Use `Hermes.Server.Transport.STDIO`, `Hermes.Server.Transport.StreamableHTTP`

### OTP Compliance & GenServer Patterns

- **Process Structure**: All core components are GenServers with proper OTP supervision
- **GenServer Naming**: Use `Hermes.genserver_name/1` validator with Peri schemas
- **State Immutability**: Always return updated state from handle\_\* callbacks
- **Hibernation**: Use `:hibernate` for reduced memory footprint in init
- **Graceful Shutdown**: Implement proper `terminate/2` callbacks with cleanup

### Validation & Schema Patterns

- **Peri Integration**: Use `import Peri` and `defschema` for all validation
- **Option Parsing**: Use `parse_options!/1` pattern for GenServer initialization
- **Schema Definitions**: Define validation schemas as module attributes
- **Custom Validators**: Use `{:custom, &validator_function/1}` for complex validation

### ID Generation & Request Tracking

- **Unique IDs**: Use `Hermes.MCP.ID` for generating request/response IDs
  - `ID.generate_request_id/0`, `ID.generate_error_id/0`
- **Timer Management**: Use `Process.send_after/3` for request timeouts
- **Request Lifecycle**: Track requests with timers, cleanup on completion/timeout

### Telemetry & Observability

- **Event Emission**: Use `Hermes.Telemetry` for consistent telemetry events
  - Client events: `event_client_init/0`, `event_client_request/0`, `event_client_response/0`
  - Server events: `event_server_init/0`, `event_server_request/0`, `event_server_response/0`
- **Logging**: Use `Hermes.Logging` for structured logging
  - `client_event/2`, `server_event/2`, `message/4` for protocol message logging

### Testing Patterns

- **MCP Framework**: Use `Hermes.MCP.Case` for comprehensive MCP protocol testing
  - Provides builders, setup functions, helpers, and domain-specific assertions
  - Reduces test boilerplate by ~90% while maintaining flexibility
  - Uses MockTransport (test double) instead of real transports like STDIO/HTTP
  - No mocking library needed - MockTransport is already a test implementation
- **Message Builders**: Use Hermes.MCP.Builders builders for consistent message construction
  - `init_request/1`, `ping_request/0`, `tools_list_request/1`, etc.
  - `build_request/2`, `build_response/2`, `build_notification/2` for custom messages
- **Setup Functions**: Use composable setup functions for test contexts
  - `setup_client/2`, `initialize_client/2`, `initialized_client/2`
  - `setup_server/2`, `initialize_server/2`, `initialized_server/2`
  - `server_with_mock_transport/2` for server without initialization
- **MCP Assertions**: Use domain-specific assertions for clear error messages
  - `assert_mcp_response/2`, `assert_mcp_error/3`, `assert_mcp_notification/2`
  - `assert_success/2`, `assert_resources/2`, `assert_tools/2`

## Code Style Guidelines

- **Code Comments**: Only add code comments if strictly necessary, avoid it generally
- **Formatting**: Follow .formatter.exs rules with Peri imports
- **Types**: Use @type/@spec for all public functions
- **Naming**: snake_case for functions, PascalCase modules
- **Imports**: Group imports at top, organize by category (Elixir stdlib, deps, project modules)
- **Documentation**: Include @moduledoc and @doc with examples
- **Error Handling**: Pattern match with {:ok, \_} and {:error, reason}
- **Testing**: Descriptive test blocks
- **Constants**: Define defaults as module attributes (@default\_\*)
- **Module Structure**: Follow pattern: moduledoc, types, constants, public API, GenServer callbacks, private helpers

### Testing Guidelines

- Always implement test helper modules in @test/support/ context, analyzing if there aren't any existing ones that could be used
