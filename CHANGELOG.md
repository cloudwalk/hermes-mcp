# Changelog

All notable changes to this project are documented in this file.

## [0.10.1](https://github.com/cloudwalk/hermes-mcp/compare/v0.10.0...v0.10.1) (2025-06-21)


### Bug Fixes

* client should send both sse/json headers on POST requests ([#134](https://github.com/cloudwalk/hermes-mcp/issues/134)) ([e906b7f](https://github.com/cloudwalk/hermes-mcp/commit/e906b7f02bf390faecc2b6bd39aab05ef9c500b1))
* correctly allows macro-based/callback-based server implementations ([#131](https://github.com/cloudwalk/hermes-mcp/issues/131)) ([d7bfc75](https://github.com/cloudwalk/hermes-mcp/commit/d7bfc7541a8c381573f1a20ebc37d4a7dbaaa139))
* remove last uses of hard-coded Hermes.Server.Registry ([cc0ffd9](https://github.com/cloudwalk/hermes-mcp/commit/cc0ffd95fce771a9c861c6859124dcedb6ceb88e))

## [0.10.0](https://github.com/cloudwalk/hermes-mcp/compare/v0.9.1...v0.10.0) (2025-06-18)


### Features

* batch operations on server-side ([#125](https://github.com/cloudwalk/hermes-mcp/issues/125)) ([28eea7c](https://github.com/cloudwalk/hermes-mcp/commit/28eea7cd15f72c4effccc8475e6b301b2cd9745c))
* missing notifications handlers ([#129](https://github.com/cloudwalk/hermes-mcp/issues/129)) ([34d5934](https://github.com/cloudwalk/hermes-mcp/commit/34d593499fdd846f430b93b4c52ca986f345646d))
* support batch operations on client side ([#101](https://github.com/cloudwalk/hermes-mcp/issues/101)) ([fadf28d](https://github.com/cloudwalk/hermes-mcp/commit/fadf28d80068f3f1e77835fd46a276338048f0bc))
* tools annotations ([#127](https://github.com/cloudwalk/hermes-mcp/issues/127)) ([c83e8f1](https://github.com/cloudwalk/hermes-mcp/commit/c83e8f1b0e721b1a03960ac67cdd0774337675dc))


### Miscellaneous Chores

* release please correct version on readme ([#128](https://github.com/cloudwalk/hermes-mcp/issues/128)) ([d0125c6](https://github.com/cloudwalk/hermes-mcp/commit/d0125c664b5190b560bb988ff01d17cbdba814bd))
* update peri ([#126](https://github.com/cloudwalk/hermes-mcp/issues/126)) ([7292615](https://github.com/cloudwalk/hermes-mcp/commit/7292615cf57da0185006df2f6221f8ab93aacd30))

## [0.9.1](https://github.com/cloudwalk/hermes-mcp/compare/v0.9.0...v0.9.1) (2025-06-13)


### Bug Fixes

* allow enum specific type on json-schema ([#121](https://github.com/cloudwalk/hermes-mcp/issues/121)) ([23c9ce2](https://github.com/cloudwalk/hermes-mcp/commit/23c9ce2081ed1099ce1f3afbd9318c8a02480039)), closes [#114](https://github.com/cloudwalk/hermes-mcp/issues/114)
* correctly escape quoted expressions ([#119](https://github.com/cloudwalk/hermes-mcp/issues/119)) ([0c469c5](https://github.com/cloudwalk/hermes-mcp/commit/0c469c552d8d5fd2498706b4b1f41100e8561e2f)), closes [#118](https://github.com/cloudwalk/hermes-mcp/issues/118)

## [0.9.0](https://github.com/cloudwalk/hermes-mcp/compare/v0.8.2...v0.9.0) (2025-06-12)


### Features

* add independently configurable logs ([#113](https://github.com/cloudwalk/hermes-mcp/issues/113)) ([bb0be27](https://github.com/cloudwalk/hermes-mcp/commit/bb0be2716ac41bf43814a16497b209fa55cc811b))


### Bug Fixes

* allow registering a name for the client supervisor ([#117](https://github.com/cloudwalk/hermes-mcp/issues/117)) ([d356511](https://github.com/cloudwalk/hermes-mcp/commit/d356511e2fbcf47b6a85ed733671e96d800ac693))

## [0.8.2](https://github.com/cloudwalk/hermes-mcp/compare/v0.8.1...v0.8.2) (2025-06-11)


### Code Refactoring

* higher-level client implementation ([#111](https://github.com/cloudwalk/hermes-mcp/issues/111)) ([5de2162](https://github.com/cloudwalk/hermes-mcp/commit/5de2162b166e390b4dacfd7b9960fab59c81b4d7))

## [0.8.1](https://github.com/cloudwalk/hermes-mcp/compare/v0.8.0...v0.8.1) (2025-06-10)


### Bug Fixes

* hermes should respect mix releases startup ([#109](https://github.com/cloudwalk/hermes-mcp/issues/109)) ([f42d476](https://github.com/cloudwalk/hermes-mcp/commit/f42d476e1dc05c57479170bd58aaca9028ef1e66))

## [0.8.0](https://github.com/cloudwalk/hermes-mcp/compare/v0.7.0...v0.8.0) (2025-06-10)


### Features

* inject user and transport data on mcp server frame ([#106](https://github.com/cloudwalk/hermes-mcp/issues/106)) ([feb2ce3](https://github.com/cloudwalk/hermes-mcp/commit/feb2ce308e9fd0cde4118b294dd47ce64d8db18f))
* legacy sse server transport ([#102](https://github.com/cloudwalk/hermes-mcp/issues/102)) ([4a71088](https://github.com/cloudwalk/hermes-mcp/commit/4a71088713071a726bde03bf1385c3c794d2134b))


### Bug Fixes

* allow empty capabilities on incoming JSON-RPC messages ([#105](https://github.com/cloudwalk/hermes-mcp/issues/105)) ([f0ad4cf](https://github.com/cloudwalk/hermes-mcp/commit/f0ad4cf1a5a85cc8a56baed875d2d2d200bb5860)), closes [#96](https://github.com/cloudwalk/hermes-mcp/issues/96)


### Miscellaneous Chores

* release please should include all files ([#108](https://github.com/cloudwalk/hermes-mcp/issues/108)) ([d0a25b9](https://github.com/cloudwalk/hermes-mcp/commit/d0a25b968c83ae1023ffffc8ee07b5b490122c03))

## [0.7.0](https://github.com/cloudwalk/hermes-mcp/compare/v0.6.0...v0.7.0) (2025-06-09)


### Features

* allow json schema fields on tools/prompts definition ([#99](https://github.com/cloudwalk/hermes-mcp/issues/99)) ([0345f12](https://github.com/cloudwalk/hermes-mcp/commit/0345f122484a0169645c5da07e50c2d64fd6c5f5))

## [0.6.0](https://github.com/cloudwalk/hermes-mcp/compare/v0.5.0...v0.6.0) (2025-06-09)


### Features

* allow customize server registry impl ([#94](https://github.com/cloudwalk/hermes-mcp/issues/94)) ([f3ac087](https://github.com/cloudwalk/hermes-mcp/commit/f3ac08749a7c361466a7a619f9782e8d8706a7b6))
* mcp high level server components definition ([#91](https://github.com/cloudwalk/hermes-mcp/issues/91)) ([007f41d](https://github.com/cloudwalk/hermes-mcp/commit/007f41d33874fd9f1b5e340ecbe16317dc3576b7))
* mcp server handlers refactored ([#92](https://github.com/cloudwalk/hermes-mcp/issues/92)) ([e213e04](https://github.com/cloudwalk/hermes-mcp/commit/e213e046b1360b24ff9e42835cdf80f5fe2ae4fa))


### Bug Fixes

* correctly handle mcp requests on phoenix apps ([#88](https://github.com/cloudwalk/hermes-mcp/issues/88)) ([09f4235](https://github.com/cloudwalk/hermes-mcp/commit/09f42359f0daac694013f0be4f6a74de2be7f4ff)), closes [#86](https://github.com/cloudwalk/hermes-mcp/issues/86)


### Miscellaneous Chores

* upcate automatic version ([#98](https://github.com/cloudwalk/hermes-mcp/issues/98)) ([0c08233](https://github.com/cloudwalk/hermes-mcp/commit/0c08233371338af24ea66047b4e1a8e9fa5cb055))


### Code Refactoring

* tests ([#93](https://github.com/cloudwalk/hermes-mcp/issues/93)) ([ca31feb](https://github.com/cloudwalk/hermes-mcp/commit/ca31febee7aec1d45dcb32398b33228d1399ae39))

## [0.5.0](https://github.com/cloudwalk/hermes-mcp/compare/v0.4.1...v0.5.0) (2025-06-05)


### Features

* client support new mcp spec ([#83](https://github.com/cloudwalk/hermes-mcp/issues/83)) ([73d14f7](https://github.com/cloudwalk/hermes-mcp/commit/73d14f77522cef0f7212230c05cdac23ee2d93e2))
* enable log disabling ([#78](https://github.com/cloudwalk/hermes-mcp/issues/78)) ([fa1453f](https://github.com/cloudwalk/hermes-mcp/commit/fa1453fee9b015c0ad7f9ac223749a9c9f1fcf6a))
* low level genservy mcp server implementation (stdio + stremable http) ([#77](https://github.com/cloudwalk/hermes-mcp/issues/77)) ([e6606b4](https://github.com/cloudwalk/hermes-mcp/commit/e6606b4d66a2d7ddeb6c32e0041c22d4f0036ac5))
* mvp higher level mcp server definition ([#84](https://github.com/cloudwalk/hermes-mcp/issues/84)) ([a5fec1c](https://github.com/cloudwalk/hermes-mcp/commit/a5fec1c976595c3363d4eec83e0cbc382eac9207))


### Code Refactoring

* base mcp server implementation correctly uses streamable http ([#85](https://github.com/cloudwalk/hermes-mcp/issues/85)) ([29060fd](https://github.com/cloudwalk/hermes-mcp/commit/29060fd2d2e383c58c727a9085b30162c6b8179a))

## [0.4.0](https://github.com/cloudwalk/hermes-mcp) - 2025-05-06

### Added
- Implemented WebSocket transport (#70)
- Emit `telemetry` events (#54)
- Implement client feature `completion` request (#72)
- Implement client feature roots, server requests (#73)

## [0.3.12](https://github.com/cloudwalk/hermes-mcp) - 2025-04-24

### Fixed
- Correctly handles "nested" timeouts (genserver vs MCP) (#71)

## [0.3.11](https://github.com/cloudwalk/hermes-mcp) - 2025-04-17

### Added
- Improved core library logging and added verbosity level on interactive/CLI (#68)

## [0.3.10](https://github.com/cloudwalk/hermes-mcp) - 2025-04-17

### Fixed
- Handle SSE ping and reconnect events from server (#65)

## [0.3.9](https://github.com/cloudwalk/hermes-mcp) - 2025-04-15

### Fixed
- Improved and simplified SSE endpoint event URI merging (#64)

### Added
- Added internal client/transport state inspection on CLI/mix tasks (#61)

## [0.3.8](https://github.com/cloudwalk/hermes-mcp) - 2025-04-10

### Added
- Created `Operation` struct to standardize client API calls (#56)
- Fixed ERTS version to avoid release errors

### Fixed
- Resolved client timeout confusion by standardizing timeout handling (#42)

## [0.3.7](https://github.com/cloudwalk/hermes-mcp) - 2025-04-01

### Fixed
- Client reinitialization from interactive CLI (#55)

## [0.3.6](https://github.com/cloudwalk/hermes-mcp) - 2025-03-28

### Added
- New roadmap and protocol update proposal (#53)
- Added documentation for the 2025-03-26 protocol update

## [0.3.5](https://github.com/cloudwalk/hermes-mcp) - 2025-03-25

### Documentation
- Added Roadmap to README (#47)

## [0.3.4](https://github.com/cloudwalk/hermes-mcp) - 2025-03-20

### Added
- `help` command and flag on the interactive CLI (#37)
- improve SSE connection status on interactive task/cli (#37)

## [0.3.3](https://github.com/cloudwalk/hermes-mcp) - 2025-03-20

### Added
- Client request cancellation support (#35)
- Improved URI path handling for SSE transport (#36)
- Enhanced interactive mix tasks for testing MCP servers (#34)

## [0.3.2](https://github.com/cloudwalk/hermes-mcp) - 2025-03-19

### Added
- Ship static binaries to use hermes-mcp as standalone application

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
