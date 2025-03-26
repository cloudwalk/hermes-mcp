# Troubleshooting

This guide provides solutions for common issues encountered when working with Hermes MCP.

## Connection Issues

### Client Cannot Connect to Server

**Symptoms:**
- Client initialization fails
- Timeouts during initialization
- Transport errors

**Potential Causes and Solutions:**

1. **Server Not Running**
   - Verify the server process is running
   - Check process exit codes and logs
   - Ensure the command path is correct

   ```elixir
   # Verify command can be found
   if cmd = System.find_executable("mcp") do
     IO.puts("Found MCP at: #{cmd}")
   else
     IO.puts("MCP command not found in PATH")
   end
   ```

2. **Transport Configuration**
   - Double-check transport configuration parameters
   - Verify working directory permissions
   - Check for environment variable issues

   ```elixir
   # Test transport manually
   {:ok, transport} = Hermes.Transport.STDIO.start_link(
     client: self(),
     command: "mcp",
     args: ["--version"]
   )
   
   # Should output version information
   ```

3. **Port Issues**
   - Check for port conflicts in HTTP/SSE transport
   - Verify firewall settings if connecting remotely
   - Check timeout settings in your client configuration

## Protocol Errors

### Version Negotiation Failures

**Symptoms:**
- Error like "Unsupported protocol version"
- Initialization fails after transport connects

**Solutions:**
- Verify both client and server support compatible protocol versions
- Check the server logs for supported versions
- Update your Hermes MCP client to a compatible version

```elixir
# Log initialization error for debugging
# In your error handler
Logger.error("Protocol version error: #{inspect(error)}")
```

### Capability Negotiation Issues

**Symptoms:**
- Operations fail with errors about missing capabilities
- Some features don't work as expected

**Solutions:**
- Check which capabilities are advertised by both client and server
- Make sure required capabilities are included in your client configuration
- Inspect server capabilities after initialization

```elixir
# Debug server capabilities
server_capabilities = Hermes.Client.get_server_capabilities(MyApp.MCPClient)
IO.inspect(server_capabilities, label: "Server capabilities")
```

## Message Handling Issues

### Request Timeouts

**Symptoms:**
- Operations fail with timeout errors
- Long-running operations consistently fail

**Solutions:**
- Increase the request timeout for specific operations
- Check for performance issues on the server
- Review network latency between client and server

```elixir
# Use a longer timeout for slow operations
{:ok, result} = Hermes.Client.call_tool(
  MyApp.MCPClient,
  "slow_operation",
  %{},
  timeout: 120_000  # 2 minutes
)
```

### Message Parsing Errors

**Symptoms:**
- "Failed to decode response" errors
- "Invalid message" errors

**Solutions:**
- Check for message format issues
- Verify the server is sending valid JSON-RPC 2.0 messages
- Enable verbose logging to inspect raw messages

```elixir
# Set debug logging for Hermes.MCP.Message
Logger.configure(level: :debug)
```

## Resource-Related Issues

### Resource Not Found

**Symptoms:**
- `{:error, %{"code" => -32002, "message" => "Resource not found"}}`
- Resource operations consistently fail

**Solutions:**
- Verify the resource URI is correct
- Check if the server has access to the resource
- List available resources to confirm what's accessible

```elixir
# List all available resources
{:ok, %{"resources" => resources}} = Hermes.Client.list_resources(MyApp.MCPClient)
IO.inspect(resources, label: "Available resources")
```

### Resource Content Issues

**Symptoms:**
- Resource content is corrupted or truncated
- Binary resources have encoding issues

**Solutions:**
- Check for encoding/decoding issues
- Verify resource size limits
- Try alternative resource access methods

```elixir
# Test reading a resource with explicit content type expectations
case Hermes.Client.read_resource(MyApp.MCPClient, "file:///example.txt") do
  {:ok, %{"contents" => [%{"text" => text}]}} ->
    IO.puts("Successfully read text content: #{String.slice(text, 0, 100)}...")
    
  {:ok, %{"contents" => [%{"blob" => _blob}]}} ->
    IO.puts("Successfully read binary content")
    
  error ->
    IO.inspect(error, label: "Error reading resource")
end
```

## Tool-Related Issues

### Tool Not Found

**Symptoms:**
- `{:error, %{"code" => -32601, "message" => "Method not found"}}`
- Tool calls consistently fail

**Solutions:**
- Verify the tool name is correct
- Check if the server has the tool available
- List available tools to confirm what's accessible

```elixir
# List all available tools
{:ok, %{"tools" => tools}} = Hermes.Client.list_tools(MyApp.MCPClient)
IO.inspect(tools, label: "Available tools")
```

### Tool Execution Errors

**Symptoms:**
- `{:ok, %{"content" => [...], "isError" => true}}`
- Tool returns error responses

**Solutions:**
- Check tool arguments for correctness
- Review server logs for detailed error information
- Test with simplified arguments to isolate the issue

```elixir
# Step through tool execution with simple arguments
case Hermes.Client.call_tool(MyApp.MCPClient, "problematic_tool", %{"simple" => "value"}) do
  {:ok, %{"content" => content, "isError" => true}} ->
    IO.puts("Tool execution error:")
    Enum.each(content, fn
      %{"type" => "text", "text" => text} -> IO.puts("  #{text}")
      _ -> nil
    end)
    
  {:ok, result} ->
    IO.puts("Tool executed successfully")
    
  error ->
    IO.inspect(error, label: "Error calling tool")
end
```

## Prompt-Related Issues

### Prompt Template Errors

**Symptoms:**
- Prompt retrieval fails with parameter errors
- Unexpected prompt content

**Solutions:**
- Verify required arguments are provided
- Check argument format and types
- Inspect the prompt template requirements

```elixir
# List prompt arguments
{:ok, %{"prompts" => prompts}} = Hermes.Client.list_prompts(MyApp.MCPClient)
prompt = Enum.find(prompts, & &1["name"] == "target_prompt")
IO.inspect(prompt["arguments"], label: "Required arguments")
```

## Supervision and Lifecycle Issues

### Process Crashes

**Symptoms:**
- Client or transport processes terminate unexpectedly
- Supervisor restarts processes frequently

**Solutions:**
- Review process crash reasons in logs
- Check for resource leaks or memory issues
- Consider adjusting supervision strategy

```elixir
# Check process state
case Process.whereis(MyApp.MCPClient) do
  nil ->
    IO.puts("Client process not running!")
    
  pid ->
    IO.puts("Client is running with PID: #{inspect(pid)}")
    Process.info(pid, :message_queue_len)
    |> IO.inspect(label: "Message queue length")
end
```

### Memory Usage Issues

**Symptoms:**
- Growing memory usage
- Slow performance over time

**Solutions:**
- Check for message or state accumulation
- Review resource cleanup procedures
- Consider implementing periodic restarts for long-running processes

## Debugging Techniques

### Enabling Verbose Logging

Increase logging detail for better diagnostics:

```elixir
# In your config/dev.exs or at runtime
Logger.configure(level: :debug)
```

### Inspecting Message Flow

To debug message flow between client and server:

```elixir
# Create a custom logger transport
defmodule MyApp.DebugTransport do
  @behaviour Hermes.Transport.Behaviour
  
  defstruct [:inner_transport]
  
  def new(inner_transport) do
    %__MODULE__{inner_transport: inner_transport}
  end
  
  def start_link(opts) do
    inner_transport_module = opts[:inner_transport_module]
    inner_opts = Keyword.delete(opts, :inner_transport_module)
    
    with {:ok, transport} <- inner_transport_module.start_link(inner_opts) do
      {:ok, new(transport)}
    end
  end
  
  def send_message(%__MODULE__{} = transport, message) do
    Logger.debug(">> OUTGOING: #{inspect(message)}")
    transport.inner_transport.send_message(message)
  end
  
  def send_message(pid, message) when is_pid(pid) do
    Logger.debug(">> OUTGOING: #{inspect(message)}")
    transport = :sys.get_state(pid)
    send_message(transport, message)
  end
end

# Then use it in your setup
{MyApp.DebugTransport, [
  name: MyApp.DebugMCPTransport,
  inner_transport_module: Hermes.Transport.STDIO,
  client: MyApp.MCPClient,
  command: "mcp",
  args: ["run", "server.py"]
]}
```

### Testing Connection in Isolation

To test the transport separately:

```elixir
# In IEx console
iex> {:ok, transport} = Hermes.Transport.STDIO.start_link(
...>   client: self(),
...>   command: "mcp",
...>   args: ["run", "echo_server.py"]
...> )
iex> transport.send_message("{\"jsonrpc\":\"2.0\",\"method\":\"ping\",\"id\":1}\n")
iex> flush()  # Should see the response
```

## Performance Considerations

### Optimizing Request Handling

For better performance:

1. **Batch Requests When Possible**
   - Group related operations together
   - Minimize round-trips for small operations

2. **Consider Resource Size**
   - Be cautious with large resources
   - Use pagination for large collections

3. **Connection Management**
   - Keep long-lived connections when appropriate
   - Implement connection pooling for multi-user scenarios

## Getting Additional Help

If you're still experiencing issues:

1. Check the [GitHub Issues](https://github.com/cloudwalk/hermes-mcp/issues) for similar problems
2. Look for known issues in the [MCP Specification](https://spec.modelcontextprotocol.io/)
3. Join the Elixir community channels to ask for help
