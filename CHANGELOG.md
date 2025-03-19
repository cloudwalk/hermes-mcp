# Changelog

All notable changes to this project are documented in this file.

## [0.3.2](https://github.com/cloudwalk/hermes-mcp) - 2025-03-19

### Added
- Ship static binaries to use hermes-mcp as standlone application

## [0.3.1](https://github.com/cloudwalk/hermes-mcp) - 2025-03-19

### Added
- Ship interactive mix tasks `stdio.interactive` and `sse.interactive` to test MCP servers

## [0.3.0](https://github.com/cloudwalk/hermes-mcp) - 2025-03-18

### Added
- Structured server-client logging support (#27)
- Progress notification tracking (#26)
- MCP domain model implementation (#28)
- Comprehensive SSE unit tests (#20)
- Centralized state management (#31)
- Standardized error response handling (#32)

### Fixed
- Improved domain error handling (#33)

## [0.2.3](https://github.com/cloudwalk/hermes-mcp) - 2025-03-12

### Added
- Enhanced SSE transport with graceful shutdown capabilities (#25)
- Improved SSE streaming with automatic reconnection handling (#25)

## [0.2.2](https://github.com/cloudwalk/hermes-mcp) - 2025-03-05

### Added
- Support for multiple concurrent client <> transport pairs (#24)
- Improved client resource management

## [0.2.1](https://github.com/cloudwalk/hermes-mcp) - 2025-02-28

### Added
- Support for custom base and SSE paths in HTTP/SSE client (#19)
- Enhanced configuration options for SSE endpoints

## [0.2.0](https://github.com/cloudwalk/hermes-mcp) - 2025-02-27

### Added
- Implemented HTTP/SSE transport (#7)
  - Support for server-sent events communication
  - HTTP client integration for MCP protocol
  - Streaming response handling

### Documentation
- Extensive guides and documentation improvements

## [0.1.0](https://github.com/cloudwalk/hermes-mcp) - 2025-02-26

### Added
- Implemented STDIO transport (#1) for MCP communication
  - Support for bidirectional communication via standard I/O
  - Automatic process monitoring and recovery
  - Environment variable handling for cross-platform support
  - Integration test utilities in Mix tasks

- Created stateful client interface (#6)
  - Robust GenServer implementation for MCP client
  - Automatic initialization and protocol handshake
  - Synchronous-feeling API over asynchronous transport
  - Support for all MCP operations (ping, resources, prompts, tools)
  - Proper error handling and logging
  - Capability negotiation and management

- Developed JSON-RPC message parsing (#5)
  - Schema-based validation of MCP messages
  - Support for requests, responses, notifications, and errors
  - Comprehensive test suite for message handling
  - Encoding/decoding functions with proper validation

- Established core architecture and client API
  - MCP protocol implementation following specification
  - Client struct for maintaining connection state
  - Request/response correlation with unique IDs
  - Initial transport abstraction layer

### Documentation
- Added detailed RFC document describing the library architecture
- Enhanced README with project overview and installation instructions
