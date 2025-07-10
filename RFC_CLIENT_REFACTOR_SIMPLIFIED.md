# RFC: Hermes MCP Client Architecture Refactor - Practical Approach

## Executive Summary

This RFC proposes a practical refactoring of the Hermes MCP client to improve maintainability while preserving the existing API. The current implementation has grown organically to 1,443 lines in `Client.Base` and 723 lines in `Client.State`, making it difficult to understand and modify. We propose a focused refactoring that extracts clear responsibilities without over-engineering.

## Current State Analysis

### Actual Architecture

Based on code analysis:

```
Module                    | Actual Lines | Core Responsibilities
-------------------------|--------------|------------------------
Hermes.Client.Base       |        1,443 | GenServer, message routing, transport handling
Hermes.Client.State      |          723 | State management, request tracking, capabilities
Hermes.Client.Operation  |          100 | Request configuration wrapper
Hermes.Client.Request    |           44 | Simple request data structure
```

### Key Issues Identified

1. **Mixed Concerns in Base**: The Base module handles:
   - GenServer lifecycle (init, handle_call, handle_info)
   - Message encoding/decoding
   - Request timeout management
   - Progress callback coordination
   - Batch request processing
   - Transport interaction

2. **Complex State Management**: The State module manages:
   - Request tracking with timeouts
   - Progress callbacks with type checking
   - Capability validation
   - Request/response correlation

3. **Duplication with Server**: Both client and server:
   - Implement similar message encoding/decoding
   - Handle timeouts independently
   - Manage capabilities separately

## Proposed Solution

### Design Principles

1. **Incremental Refactoring**: Extract one concern at a time
2. **Preserve Public API**: No breaking changes to existing clients
3. **Leverage Existing Patterns**: Follow Elixir/OTP conventions
4. **Practical Over Perfect**: Ship improvements iteratively

### Simplified Architecture

```
┌─────────────────────────────────────────┐
│         Public API (unchanged)          │
│    Hermes.Client (macro-based DSL)      │
└─────────────────────────────────────────┘
                    │
┌─────────────────────────────────────────┐
│    Client.Base (~400 lines)             │
│    - GenServer orchestration            │
│    - Transport coordination             │
└─────────────────────────────────────────┘
         ╱              │              ╲
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ MCP.Message  │ │    State     │ │   Request    │
│  (existing)  │ │   Manager    │ │   Handler    │
│              │ │  (existing)  │ │    (new)     │
└──────────────┘ └──────────────┘ └──────────────┘
```

### Key Changes

1. **Use MCP.Message Consistently**
   - Client.Base already imports and uses MCP.Message
   - Just need to remove any custom encoding/decoding
   - Ensure all message building uses the existing module

2. **Extract Request Handler** (New Module)
   - Move request lifecycle management from Base
   - Handle timeouts, retries, and correlation
   - Simplify Base to ~400 lines

3. **Keep Existing Modules**
   - State module is already well-designed
   - MCP.Message already handles all protocol needs
   - No new shared module needed

### Module Specifications

#### 1. Consistent Use of MCP.Message (No New Module)
**Purpose**: Ensure both client and server use the existing module

```elixir
# Already exists: Hermes.MCP.Message
- encode_request/2
- encode_response/2
- encode_notification/1
- encode_error/2
- decode/1
- Guards: is_request/1, is_response/1, etc.
- Batch support: encode_batch/1

# Client.Base changes needed:
- Remove any custom message building
- Use Message.encode_* consistently
- Use Message.decode/1 for all parsing
```

**Benefits**:
- No new module to create
- Already tested and working
- Just need to use it consistently

#### 2. Request Handler (New)
**Purpose**: Extract request lifecycle from Client.Base

```elixir
defmodule Hermes.Client.RequestHandler do
  # Extract from Client.Base:
  - handle_request/3 (lines 872-978)
  - handle_batch_request/2 (lines 980-1039)
  - Timer management (lines 1200-1250)
  - Response correlation logic
  
  # Work with existing State module
  # No new data structures needed
end
```

#### 3. Client.Base (Simplified)
**Purpose**: Pure orchestration and GenServer logic

```elixir
defmodule Hermes.Client.Base do
  # Remaining responsibilities:
  - GenServer callbacks (init, handle_call, handle_info)
  - Transport coordination
  - Delegate to RequestHandler for requests
  - Delegate to State for state management
  - Delegate to Protocol for encoding/decoding
end
```

## Implementation Strategy

### Phase 1: Message Module Cleanup (3 days)
1. Audit Client.Base for custom message handling
2. Replace with calls to MCP.Message functions
3. Remove any duplicate encoding/decoding logic
4. Run tests to ensure no regressions

### Phase 2: Extract Request Handler (1 week)
1. Create `Hermes.Client.RequestHandler` module
2. Move request-specific functions from Base
3. Update Base to delegate to RequestHandler
4. Existing State module remains unchanged

### Phase 3: Testing & Validation (1 week)
1. Ensure all existing tests pass
2. Add focused tests for new modules
3. Benchmark performance (expect < 1% difference)
4. No user-visible changes

## Practical Benefits

### Immediate Improvements

1. **Reduced Complexity**:
   - Client.Base: 1,443 → ~400 lines
   - Clear separation of concerns
   - Easier to find and fix bugs

2. **Better Protocol Usage**:
   - Consistent use of MCP.Message
   - No custom encoding/decoding
   - Single source of truth for messages

3. **Better Testing**:
   - Can test request handling in isolation
   - Protocol logic testable without GenServer
   - Existing tests remain unchanged

### Long-term Benefits

1. **Maintainability**:
   - New contributors understand modules faster
   - Changes less likely to cause regressions
   - Clear boundaries for future features

2. **Evolution**:
   - Easy to add new protocol versions
   - Transport changes isolated to Base
   - State management already well-isolated

## Risk Mitigation

1. **No Breaking Changes**: Internal refactoring only
2. **Incremental Approach**: One module at a time
3. **Extensive Testing**: All existing tests must pass
4. **Performance Monitoring**: Benchmark critical paths

## Why This Approach?

### What We're NOT Doing
- No complex architectural patterns
- No new abstractions to learn
- No API changes
- No feature flags needed

### What We ARE Doing
- Moving code to logical modules
- Sharing obvious duplications
- Making the codebase easier to navigate
- Keeping it simple and Elixir-idiomatic

## Conclusion

This practical refactoring takes the existing 1,443-line Client.Base module and breaks it into manageable pieces:

1. **Shared Protocol Layer**: Eliminates ~300 lines of duplication
2. **Request Handler**: Extracts ~600 lines of request management
3. **Simplified Base**: Reduces to ~400 lines of pure orchestration

The approach is incremental, maintains all existing APIs, and can be completed in 3 weeks. Most importantly, it makes the codebase more maintainable without introducing unnecessary complexity.

## Next Steps

1. Review actual code excerpts identified
2. Confirm no API breakage
3. Plan incremental extraction
4. Begin with protocol consolidation
