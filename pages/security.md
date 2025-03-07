# Security Considerations

This guide covers security best practices and implementation strategies for authentication and authorization with Hermes MCP.

## MCP Security Overview

The Model Context Protocol itself does not define specific authentication or authorization mechanisms. However, securing your MCP connections is essential, particularly when:

1. Exposing MCP services over a network
2. Handling sensitive data or operations
3. Integrating with LLMs that have access to tools
4. Operating in multi-user environments

## Transport Security

### STDIO Transport Security

When using the STDIO transport for local processes:

1. **Process Isolation**: Ensure the spawned process runs with appropriate permissions
2. **Environment Variables**: Securely manage sensitive environment variables
3. **Working Directory**: Set appropriate working directory permissions
4. **Command Validation**: Validate the command and arguments before execution

Example of secure STDIO transport configuration:

```elixir
# Secure STDIO transport configuration
{Hermes.Transport.STDIO, [
  name: MyApp.MCPTransport,
  client: MyApp.MCPClient,
  command: "mcp", # full path validation internally
  args: ["run", path], # Validate path
  env: %{"SECRET_KEY" => System.fetch_env!("MCP_SECRET_KEY")},
  cwd: Application.app_dir(:my_app, "priv/mcp_server")
]}
```

### HTTP/SSE Transport Security (Planned)

For HTTP/SSE transports (planned for future releases):

1. **TLS/SSL**: Always use HTTPS with proper certificate validation
2. **CORS**: Configure appropriate Cross-Origin Resource Sharing policies
3. **Rate Limiting**: Implement rate limiting to prevent abuse
4. **Request Validation**: Validate all incoming requests

Example of future HTTP transport configuration:

```elixir
# Future HTTP transport configuration
{Hermes.Transport.HTTP, [
  name: MyApp.HTTPTransport,
  client: MyApp.MCPClient,
  server: [base_url: "https://example.com", base_path: "/mcp"],
  headers: [{"Authorization", "Bearer #{token}"}],
  transport_opts: [
    verify: :verify_peer,
    cacertfile: CAStore.file_path(),
    depth: 3,
    verify_fun: :public_key.pkix_verify_hostname_match_fun(:https)
  ]
]}
```

## Authentication Implementation Strategies

While Hermes MCP doesn't include built-in authentication, here are several approaches to implement your own:

### 1. Transport-Level Authentication

Add authentication at the transport level by including credentials in the transport configuration:

```elixir
# Example with future HTTP transport
{Hermes.Transport.HTTP, [
  # ... other options
  headers: [
    {"Authorization", "Bearer #{token}"},
    {"X-API-Key", api_key}
  ]
]}
```

### 2. Initialization Authentication

Extend the client capabilities to include authentication information during initialization:

```elixir
# Add authentication data to client initialization
client_capabilities = %{
  "resources" => %{},
  "tools" => %{},
  "experimental" => %{
    "auth" => %{
      "type" => "bearer",
      "token" => System.fetch_env!("MCP_AUTH_TOKEN")
    }
  }
}

{Hermes.Client, [
  # ... other options
  capabilities: client_capabilities
]}
```

The server would then validate these credentials during the initialization handshake.

### 3. Custom Middleware Authentication

Implement a custom authentication middleware that wraps the transport:

```elixir
defmodule MyApp.Transport.AuthMiddleware do
  @behaviour Hermes.Transport.Behaviour
  
  defstruct [:inner_transport, :auth_token]
  
  def new(inner_transport, auth_token) do
    %__MODULE__{
      inner_transport: inner_transport,
      auth_token: auth_token
    }
  end
  
  @impl true
  def start_link(opts) do
    inner_transport = opts[:inner_transport]
    auth_token = opts[:auth_token]
    
    with {:ok, transport} <- inner_transport.start_link(opts) do
      {:ok, new(transport, auth_token)}
    end
  end
  
  @impl true
  def send_message(%__MODULE__{} = transport, message) do
    # Add authentication to outgoing JSON-RPC messages
    case Jason.decode(message) do
      {:ok, decoded} ->
        authenticated = add_auth_meta(decoded, transport.auth_token)
        case Jason.encode(authenticated) do
          {:ok, json} -> transport.inner_transport.send_message(json)
          error -> error
        end
      
      error -> error
    end
  end
  
  defp add_auth_meta(%{"method" => _} = request, token) do
    # Add auth metadata to the request
    meta = %{"_meta" => %{"auth" => %{"token" => token}}}
    request
    |> Map.update("params", meta, fn params -> Map.merge(params, meta) end)
  end
  
  defp add_auth_meta(message, _token), do: message
end
```

## Authorization Implementation Strategies

Authorization determines what operations a client can perform. Here are approaches to implement authorization:

### 1. Resource URI Validation

Validate resource URIs against allowed patterns:

```elixir
defmodule MyApp.ResourceValidator do
  def validate_access(uri, user) do
    case URI.parse(uri) do
      %URI{scheme: "file"} = parsed ->
        validate_file_access(parsed.path, user)
        
      %URI{scheme: "db"} ->
        validate_db_access(uri, user)
        
      _ ->
        {:error, :invalid_uri_scheme}
    end
  end
  
  defp validate_file_access(path, user) do
    allowed_paths = user.allowed_paths
    
    if Enum.any?(allowed_paths, &String.starts_with?(path, &1)) do
      :ok
    else
      {:error, :unauthorized_path}
    end
  end
  
  defp validate_db_access(uri, user) do
    # Database-specific validation
    # ...
  end
end
```

### 2. Tool Permission Management

Implement permission checks for tool execution:

```elixir
defmodule MyApp.ToolAuthorizer do
  def authorize(tool_name, arguments, user) do
    tool_permissions = user.tool_permissions || %{}
    
    case Map.get(tool_permissions, tool_name) do
      nil ->
        {:error, :tool_not_authorized}
        
      permissions ->
        validate_arguments(tool_name, arguments, permissions)
    end
  end
  
  defp validate_arguments("file_write", %{"path" => path}, permissions) do
    allowed_paths = permissions.allowed_write_paths || []
    
    if Enum.any?(allowed_paths, &String.starts_with?(path, &1)) do
      :ok
    else
      {:error, :path_not_authorized}
    end
  end
  
  # Additional validation rules for other tools
end
```

### 3. Capability-Based Security

Implement capability-based security by only exposing specific capabilities to each client:

```elixir
# Create custom capabilities based on user permissions
defmodule MyApp.CapabilityGenerator do
  def generate_for_user(user) do
    %{
      "resources" => generate_resource_capabilities(user),
      "tools" => generate_tool_capabilities(user)
    }
  end
  
  defp generate_resource_capabilities(user) do
    if user.can_access_resources do
      %{"subscribe" => user.can_subscribe_resources}
    else
      nil
    end
  end
  
  defp generate_tool_capabilities(user) do
    if length(user.allowed_tools) > 0 do
      %{}
    else
      nil
    end
  end
end
```

Then use these capabilities when initializing the client:

```elixir
user = MyApp.Accounts.get_user!(user_id)
capabilities = MyApp.CapabilityGenerator.generate_for_user(user)

{Hermes.Client, [
  # ... other options
  capabilities: capabilities
]}
```

## Best Practices for Secure MCP Implementation

1. **Principle of Least Privilege**: Only grant the minimum necessary permissions
2. **Input Validation**: Validate all user inputs, especially resource URIs and tool arguments
3. **Audit Logging**: Log all MCP operations for security monitoring and compliance
4. **Rate Limiting**: Implement rate limiting to prevent abuse
5. **Secure Defaults**: Use secure defaults and require explicit opt-in for sensitive operations

## Security with LLM Integration

When integrating MCP with Language Models, additional considerations apply:

1. **Tool Sandboxing**: Sandbox tool execution to prevent unintended consequences
2. **Prompt Isolation**: Ensure prompts cannot access unauthorized information
3. **User Confirmation**: Require user confirmation for sensitive operations
4. **Context Boundaries**: Maintain strict boundaries between different LLM conversations
5. **Output Filtering**: Filter LLM outputs to prevent sensitive data leakage
