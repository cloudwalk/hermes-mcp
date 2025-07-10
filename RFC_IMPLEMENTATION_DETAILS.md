# RFC Implementation Details: Practical Refactoring

## Actual Code Analysis

Based on the real codebase structure, here's what we actually need to refactor:

### Current Code Distribution

```elixir
# Hermes.Client.Base (1,443 lines) contains:
- init/1 (lines 176-213): GenServer initialization
- handle_call for requests (lines 215-370): Request handling
- handle_call for batch (lines 372-430): Batch processing  
- handle_info for responses (lines 487-597): Response processing
- handle_info for notifications (lines 599-700): Notification handling
- Request helpers (lines 872-1039): Request creation and sending
- Timer management (lines 1200-1250): Timeout handling

# Hermes.Client.State (723 lines) already handles:
- Request tracking with Map storage
- Capability validation
- Progress callback management
- Well-designed and focused
```

### Proposed Extraction: Request Handler

**Purpose**: Extract request handling logic from Client.Base

```elixir
defmodule Hermes.Client.RequestHandler do
  @moduledoc """
  Handles request lifecycle management for the MCP client.
  Extracted from Client.Base to reduce complexity.
  """
  
  alias Hermes.Client.{State, Operation, Request}
  alias Hermes.MCP.{Message, Error, ID}
  
  # Extract these functions from Client.Base:
  
  @doc "Creates and sends a request through the transport"
  def execute_request(state, operation, transport) do
    # Currently in handle_call at lines 215-370
    # Move request creation, validation, and sending
  end
  
  @doc "Handles batch requests"
  def execute_batch(state, operations, transport) do
    # Currently at lines 372-430
    # Move batch validation and processing
  end
  
  @doc "Processes incoming response"
  def handle_response(state, response) do
    # Currently in handle_info at lines 487-597
    # Move response correlation and callback execution
  end
  
  @doc "Handles request timeout"
  def handle_timeout(state, request_id) do
    # Currently at lines 1200-1250
    # Move timeout processing
  end
end
```

**Benefits**:
- Reduces Client.Base by ~600 lines
- Focused testing of request logic
- Clear interface with State module

### Existing Module: Client.State

**Current Status**: Already well-designed and focused

```elixir
# Current Hermes.Client.State already handles:
- Request tracking (add_request, remove_request, get_request)
- Progress callbacks (register_progress_callback, etc.)
- Capability validation (validate_capability)
- Log callback management

# Only minor adjustments needed:
1. Ensure clean interface with new RequestHandler
2. Maybe extract callback execution to RequestHandler
3. Keep state management pure (no side effects)
```

**Why not change it?**
- Already follows single responsibility
- Clean functional interface
- Well-tested
- No significant issues

## Simplified Client.Base After Refactoring

```elixir
defmodule Hermes.Client.Base do
  @moduledoc """
  Simplified orchestrator after extracting request handling.
  Now ~400 lines instead of 1,443.
  """
  
  use GenServer
  
  alias Hermes.Client.{State, RequestHandler}
  alias Hermes.MCP.Message
  
  require Message  # For guards
  
  # GenServer callbacks remain but delegate work
  
  def init(config) do
    # Same initialization, using existing State module
    state = State.new(config)
    # ... transport setup ...
    {:ok, state}
  end
  
  def handle_call({:request, operation}, from, state) do
    # Delegate to RequestHandler
    case RequestHandler.execute_request(state, operation, state.transport) do
      {:ok, new_state} ->
        {:noreply, new_state}
      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end
  
  def handle_info({:mcp_message, encoded}, state) do
    # Use existing Message.decode/1
    case Message.decode(encoded) do
      {:ok, [message | _]} when Message.is_response(message) ->
        {:noreply, RequestHandler.handle_response(state, message)}
        
      {:ok, [message | _]} when Message.is_notification(message) ->
        # Existing notification handling
        {:noreply, handle_notification(state, message)}
        
      {:error, error} ->
        {:noreply, state}
    end
  end
  
  # Transport management and other orchestration stays here
end
```

## Using Existing MCP.Message Module

```elixir
# Hermes.MCP.Message already provides everything:
- encode_request/2 - Build and encode requests
- encode_response/2 - Build and encode responses
- encode_notification/1 - Build and encode notifications
- encode_error/2 - Build and encode errors
- decode/1 - Parse incoming messages
- encode_batch/1 - Batch message support
- Guards: is_request/1, is_response/1, is_notification/1, is_error/1
- Even specialized encoders like encode_progress_notification/2

# Client.Base currently:
1. Uses Message.encode_request at line 1110
2. Uses Message.decode at line 540
3. But has custom message building in some places

# Simple fix:
Replace any custom JSON encoding with Message.* functions
No new module needed!
```

## Testing Improvements

```elixir
# Current: Testing requires full GenServer + MockTransport
test "handles request timeout" do
  {:ok, client} = TestHelper.start_client()
  # Mock transport setup
  # Complex assertion on GenServer state
end

# After refactoring: Test RequestHandler directly
test "handles request timeout" do
  state = State.new(client_info: %{"name" => "test"})
  operation = Operation.new("test/method", %{}, timeout: 100)
  
  # Test timeout handling without GenServer
  {state, request_id} = RequestHandler.create_request(state, operation)
  new_state = RequestHandler.handle_timeout(state, request_id)
  
  assert State.get_request(new_state, request_id) == nil
end

# Can still do integration tests with full client
# But now also have focused unit tests
```

## Implementation Steps

### Step 1: Clean up Message Usage (No API changes)
```elixir
# 1. In Client.Base, find all JSON.encode!/decode calls
# 2. Replace with appropriate Message.encode_*/decode calls
# 3. Example changes:
   # Before:
   JSON.encode!(%{"jsonrpc" => "2.0", "method" => method, ...})
   
   # After:
   Message.encode_request(%{"method" => method, "params" => params}, id)
   
# 4. Run existing tests - all should pass
```

### Step 2: Extract RequestHandler (Internal refactoring)
```elixir
# 1. Create lib/hermes/client/request_handler.ex
# 2. Move these functions from Client.Base:
   - handle_request logic (lines 215-370)
   - handle_batch_request (lines 372-430)
   - process_response (lines 487-597)
   - timeout handling (lines 1200-1250)
   
# 3. Update Client.Base to delegate to RequestHandler
# 4. No changes to public API or State module
```

### Step 3: Test and Ship
```elixir
# 1. All existing tests must pass unchanged
# 2. Add focused unit tests for RequestHandler
# 3. Benchmark key operations (expect <1% difference)
# 4. Ship as minor version - no breaking changes
```

## Real-World Impact

### Performance
- **Message Processing**: No change (same algorithms)
- **Memory**: Negligible (same data structures)
- **Module Boundaries**: One extra function call (microseconds)

### Maintenance Benefits
- **Finding bugs**: Look in RequestHandler for request issues
- **Adding features**: Clear where to add new functionality  
- **Understanding flow**: 400-line modules vs 1,400-line module

## Summary

This practical refactoring:

1. **Reduces Complexity**: Client.Base from 1,443 to ~400 lines
2. **No New Shared Module**: MCP.Message already exists and works
3. **Improves Testing**: RequestHandler can be tested without GenServer
4. **No Breaking Changes**: Internal refactoring only
5. **Quick Implementation**: 2 weeks max (simpler without new module)

The key insight is that we don't need a new Protocol module - `Hermes.MCP.Message` already provides all the encoding/decoding we need. We just need to:
- Use it consistently everywhere
- Extract request handling to a new module
- Keep the existing, well-designed State module