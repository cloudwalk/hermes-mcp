# MCPTest Framework Guide

The MCPTest framework provides a comprehensive testing toolkit for MCP (Model Context Protocol) implementations in Elixir. It reduces test boilerplate by ~90% while maintaining flexibility and clarity.

## Overview

MCPTest consists of several modules that work together:

- **MCPTest.Case** - Test case template with common imports and setup
- **MCPTest.Builders** - Message builders for consistent test data
- **MCPTest.Helpers** - High-level request/response cycle helpers
- **MCPTest.Setup** - Composable setup functions for test contexts
- **MCPTest.Assertions** - Domain-specific assertions for MCP
- **MCPTest.MockTransport** - Mock transport implementation for testing

## Getting Started

### Basic Test Structure

```elixir
defmodule MyMCPTest do
  use MCPTest.Case
  
  describe "my feature" do
    setup :initialized_client
    
    test "handles resources", %{client: client} do
      resources = [%{"uri" => "test://resource", "name" => "Test"}]
      result = request_with_resources_response(client, resources)
      
      assert_success(result, fn response ->
        assert response.result["resources"] == resources
      end)
    end
  end
end
```

### Using MCPTest.Case

MCPTest.Case automatically imports all necessary modules and sets up common test configuration:

```elixir
use MCPTest.Case                    # Sync tests
use MCPTest.Case, async: true       # Async tests (default: false)
```

This gives you access to:
- All builder functions
- All helper functions  
- All assertion functions
- Common aliases (Error, Message, Response)
- Automatic log capture

## Message Builders

Builders create consistent MCP messages for testing:

### Request Builders

```elixir
# Basic requests
ping_request()                      # {"method" => "ping", "params" => {}}
init_request(opts \\ [])           # Initialize request with options
tools_list_request(params \\ %{})  # List tools request

# Response builders  
ping_response(request_id)
init_response(request_id, opts \\ [])
tools_list_response(request_id, tools, opts \\ [])
resources_list_response(request_id, resources, opts \\ [])

# Error responses
error_response(request_id, code \\ -32601, message \\ "Method not found")

# Notifications
initialized_notification()
progress_notification(token, progress \\ 50, total \\ 100)
cancelled_notification(request_id, reason \\ "cancelled")
```

### Custom Messages

For messages not covered by specific builders:

```elixir
# Build any request
build_request("custom/method", %{"param" => "value"})

# Build any response  
build_response(%{"custom" => "result"}, request_id)

# Build any notification
build_notification("custom/notification", %{"data" => "value"})
```

## Helper Functions

### Request/Response Cycles

The most common pattern - send a request and handle the response:

```elixir
# Generic cycle
result = request_response_cycle(
  client,
  "method/name",
  %{"params" => "here"},
  fn request_id -> 
    # Build response with the request_id
    build_response(%{"result" => "data"}, request_id)
  end
)

# Shortcuts for common patterns
result = request_with_resources_response(client, resources)
result = request_with_tools_response(client, tools)
result = request_with_prompts_response(client, prompts)
```

### Manual Request Handling

For more control over timing:

```elixir
# Send request and get ID
request_id = send_request(client, "tools/call", %{"name" => "my_tool"})

# Do other setup...

# Send response
send_response(client, tools_call_response(request_id, content))

# Get result
result = await_request_result()
```

### Progress and Notifications

```elixir
# Send progress updates
send_progress(client, request_id, 50, 100)

# Send cancellation
send_cancellation(client, request_id, "user cancelled")

# Send log notification
send_log(client, "error", "Something went wrong", "my-logger")
```

## Setup Functions

### Client Setup

```elixir
# Basic client setup with initialization
describe "my tests" do
  setup :initialized_client
  
  test "example", %{client: client} do
    # Client is ready to use
  end
end

# Manual setup for more control
test "manual setup" do
  ctx = %{}
  |> setup_client()
  |> initialize_client()
  
  client = ctx.client
end

# With custom configuration
setup do
  initialized_client(
    client_info: %{"name" => "CustomClient"},
    capabilities: %{"roots" => %{}}
  )
end
```

### Server Setup

```elixir
# Basic server setup
describe "server tests" do
  setup :initialized_server
  
  test "handles request", %{server: server} do
    # Server is ready
  end
end

# Server without initialization
setup do
  server_with_mock_transport()
end
```

### Context Helpers

```elixir
# Add capabilities to context
ctx = with_capabilities(ctx, 
  %{"roots" => %{"listChanged" => true}},    # Client capabilities
  %{"tools" => %{}}                          # Server capabilities  
)

# Add info to context
ctx = with_info(ctx,
  %{"name" => "MyClient", "version" => "1.0"}, # Client info
  %{"name" => "MyServer", "version" => "2.0"}  # Server info
)
```

## Assertions

Domain-specific assertions provide better error messages:

```elixir
# Assert successful response with specific result
assert_mcp_response(decoded, %{
  "protocolVersion" => "2024-11-05",
  "serverInfo" => %{"name" => "TestServer"}
})

# Assert error response
assert_mcp_error(decoded, -32601)  # By error code
assert_mcp_error(decoded, -32601, "Method not found")  # With message

# Assert notification
assert_mcp_notification(decoded, "notifications/initialized")

# Higher-level assertions
assert_success(result, fn response ->
  # Additional assertions on successful response
end)

assert_resources(result, expected_resources)
assert_tools(result, expected_tools)
assert_prompts(result, expected_prompts)
```

## MockTransport

The mock transport can operate in two modes:

### Recording Mode (default)

Records all messages sent through it:

```elixir
{:ok, transport} = MCPTest.MockTransport.start_link(name: :my_transport)

# Send messages...

messages = MCPTest.MockTransport.get_messages(:my_transport)
MCPTest.MockTransport.clear_messages(:my_transport)
```

### Mocking Mode

Set up expectations for specific methods:

```elixir
{:ok, transport} = MCPTest.MockTransport.start_link(
  name: :my_transport,
  mode: :mocking
)

# Expect a ping request
MCPTest.MockTransport.expect_method(:my_transport, "ping", nil, fn -> 
  {:error, :connection_closed}
end)

# Verify expectations were met
:ok = MCPTest.MockTransport.verify_expectations(:my_transport)
```

### Utility Functions

```elixir
# Get message count
count = MCPTest.MockTransport.message_count(:my_transport)

# Get last message  
last = MCPTest.MockTransport.last_message(:my_transport)

# Find specific messages
pings = MCPTest.MockTransport.find_messages(:my_transport, 
  method: "ping"
)

# Assert method was called
MCPTest.MockTransport.assert_method_called(:my_transport, "tools/list")
```

## Common Patterns

### Testing with @tag

Use tags to configure test-specific settings:

```elixir
@tag server_capabilities: %{"prompts" => %{}}
test "tools not supported", %{client: client} do
  result = Hermes.Client.list_tools(client)
  assert {:error, %{reason: :method_not_found}} = result
end

@tag client_capabilities: %{"roots" => %{"listChanged" => true}}
test "sends roots notification", %{client: client} do
  # Test notification behavior
end
```

### Testing Error Cases

```elixir
test "handles transport error" do
  transport = start_supervised!({MCPTest.MockTransport, 
    name: :error_transport,
    mode: :mocking
  })
  
  MCPTest.MockTransport.expect_method(:error_transport, "ping", nil, fn ->
    {:error, :connection_closed}
  end)
  
  client = setup_client_with_transport(:error_transport)
  
  assert {:error, %{reason: :send_failure}} = Hermes.Client.ping(client)
end
```

### Testing Cancellation

```elixir
test "cancels request", %{client: client} do
  task = Task.async(fn -> 
    Hermes.Client.list_resources(client, timeout: 5000)
  end)
  
  Process.sleep(50)
  request_id = get_request_id(client, "resources/list")
  
  :ok = Hermes.Client.cancel_request(client, request_id)
  
  assert {:error, %{reason: :request_cancelled}} = Task.await(task)
end
```

## Best Practices

1. **Use MCPTest.Case** for all MCP tests to get consistent setup and imports

2. **Prefer helper functions** over manual message construction:
   ```elixir
   # Good
   result = request_with_resources_response(client, resources)
   
   # Avoid when possible
   task = Task.async(fn -> Hermes.Client.list_resources(client) end)
   # ... manual response handling ...
   ```

3. **Use domain assertions** for better error messages:
   ```elixir
   # Good - clear failure message
   assert_mcp_response(decoded, %{"protocolVersion" => "2024-11-05"})
   
   # Okay - generic assertion
   assert decoded["result"]["protocolVersion"] == "2024-11-05"
   ```

4. **Test both success and error paths**:
   ```elixir
   test "successful response", %{client: client} do
     # Test happy path
   end
   
   test "error response", %{client: client} do  
     # Test error handling
   end
   ```

5. **Use builders for consistency**:
   ```elixir
   # Good - uses tested builder
   response = tools_call_response(request_id, content, is_error: true)
   
   # Avoid - manual construction prone to errors
   response = %{
     "result" => %{"content" => content, "isError" => true},
     "id" => request_id
   }
   ```

## Debugging Tips

1. **Check transport messages**:
   ```elixir
   messages = MCPTest.MockTransport.get_messages(transport_name)
   IO.inspect(messages, label: "Messages sent")
   ```

2. **Verify client state**:
   ```elixir
   state = :sys.get_state(client)
   IO.inspect(state.pending_requests, label: "Pending requests")
   ```

3. **Use IEx.pry() in tests**:
   ```elixir
   require IEx
   
   test "debugging example" do
     # Setup...
     IEx.pry()  # Drops into interactive shell
     # Continue testing...
   end
   ```

4. **Enable debug logging**:
   ```elixir
   @moduletag capture_log: false  # Show logs during test
   ```