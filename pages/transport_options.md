# Transport Options

Hermes MCP supports multiple transport mechanisms to connect clients with servers. This page covers the available options and how to configure them.

## Transport Behavior

All transports in Hermes implement the `Hermes.Transport.Behaviour` behavior, which defines the interface for sending and receiving messages:

```elixir
defmodule Hermes.Transport.Behaviour do
  @type t :: pid() | atom()

  @typedoc "encoded JSON-RPC message"
  @type message :: String.t()

  @callback start_link(keyword()) :: Supervisor.on_start()
  @callback send_message(message()) :: :ok | {:error, reason()}
  @callback send_message(t(), message()) :: :ok | {:error, reason()}
  @callback shutdown(t()) :: :ok | {:error, reason()}
  
  @optional_callbacks send_message: 1
end
```

This standardized interface allows the client to work with different transport mechanisms interchangeably.

## STDIO Transport

The STDIO transport (`Hermes.Transport.STDIO`) enables communication with an MCP server running as a separate process. It's suitable for local integrations and communicates through standard input/output streams.

### Configuration

```elixir
{Hermes.Transport.STDIO, [
  name: MyApp.MCPTransport,
  client: MyApp.MCPClient, 
  command: "mcp",
  args: ["run", "path/to/server.py"],
  env: %{"CUSTOM_VAR" => "value"},
  cwd: "/path/to/working/directory"
]}
```

### Configuration Options

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `:name` | atom | Registration name for the transport process | `__MODULE__` |
| `:client` | atom or pid | The client process that will receive messages | Required |
| `:command` | string | The command to execute | Required |
| `:args` | list | Command line arguments | `nil` |
| `:env` | map | Environment variables | System defaults |
| `:cwd` | string | Working directory | Current directory |

### Example: Running a Python MCP Server

```elixir
{Hermes.Transport.STDIO, [
  name: MyApp.MCPTransport,
  client: MyApp.MCPClient, 
  command: "python",
  args: ["-m", "mcp.server", "my_server.py"],
  env: %{"PYTHONPATH" => "/path/to/python/modules"}
]}
```

### Example: Running a Node.js MCP Server

```elixir
{Hermes.Transport.STDIO, [
  name: MyApp.MCPTransport,
  client: MyApp.MCPClient, 
  command: "node",
  args: ["server.js"],
  env: %{"NODE_ENV" => "production"}
]}
```

## HTTP/SSE Transport

Support for HTTP with Server-Sent Events (SSE) transport is planned for future releases. This will enable communication with remote MCP servers over HTTP.

### Configuration

```elixir
{Hermes.Transport.HTTP, [
  name: MyApp.HTTPTransport,
  client: MyApp.MCPClient,
  server_url: "https://example.com/mcp",
  headers: [{"Authorization", "Bearer token"}],
  transport_opts: [verify: :verify_peer],
  http_options: [recv_timeout: 30_000]
]}
```

### Configuration Options

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `:name` | atom | Registration name for the transport process | `__MODULE__` |
| `:client` | atom or pid | The client process that will receive messages | Required |
| `:server_url` | string | The SSE server URL to use | Required |
| `:headers` | map | Additional request headers to be sent | `%{}` |
| `:transport_opts` | keyword | Options to be passed to the underlying HTTP Client, yo ucan check the avaiable options on https://hexdocs.pm/mint/Mint.HTTP.html#connect/4-transport-options | System defaults |
| `:http_options` | string | Options passed directly to the HTTP Client, you can check the available options on https://hexdocs.pm/finch/Finch.html#t:request_opt/0 | Current directory |

## Custom Transport Implementation

You can implement custom transports by creating a module that implements the `Hermes.Transport.Behaviour` behavior.

### Example: Custom TCP Transport

```elixir
defmodule MyApp.Transport.TCP do
  @behaviour Hermes.Transport.Behaviour
  use GenServer
  
  @impl true
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end
  
  @impl true
  def send_message(message) when is_binary(message) do
    GenServer.call(__MODULE__, {:send, message})
  end
  
  @impl true
  def send_message(pid, message) when is_pid(pid) and is_binary(message) do
    GenServer.call(pid, {:send, message})
  end
  
  @impl true
  def init(opts) do
    client = opts[:client]
    host = opts[:host] || "localhost"
    port = opts[:port] || 8080
    
    case :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: true]) do
      {:ok, socket} ->
        {:ok, %{socket: socket, client: client}}
        
      {:error, reason} ->
        {:stop, reason}
    end
  end
  
  @impl true
  def handle_call({:send, message}, _from, %{socket: socket} = state) do
    case :gen_tcp.send(socket, message) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_info({:tcp, _socket, data}, %{client: client} = state) do
    # Forward data to client
    Process.send(client, {:response, data}, [:noconnect])
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :normal, state}
  end
  
  @impl true
  def handle_info({:tcp_error, _socket, reason}, state) do
    {:stop, reason, state}
  end
end
```

## Transport Selection Guidelines

When choosing a transport mechanism, consider:

1. **Location**: For local servers, STDIO is typically the simplest and most efficient option.
2. **Security**: For remote servers, HTTP/SSE with TLS provides secure communication.
3. **Performance**: STDIO generally has lower latency for local communication.
4. **Reliability**: HTTP transports can handle intermittent network issues more gracefully.

## Transport Lifecycle Management

Transports in Hermes are designed to be supervised, with automatic recovery in case of failures:

```elixir
# In your supervision tree
children = [
  {Hermes.Transport.STDIO, transport_opts},
  {Hermes.Client, client_opts},
  # ...
]

# The transport will automatically restart if it crashes
opts = [strategy: :one_for_one]
Supervisor.start_link(children, opts)
```
