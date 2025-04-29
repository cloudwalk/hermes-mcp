# Transport Layer

Hermes MCP supports multiple transport mechanisms to connect clients with servers. This page covers the available options and how to configure them.

## Transport Behavior

All transports in Hermes implement the `Hermes.Transport.Behaviour` behavior, which defines the interface for sending and receiving messages:

```elixir
defmodule Hermes.Transport.Behaviour do
  @moduledoc """
  Defines the behavior that all transport implementations must follow.
  """

  @type t :: GenServer.server()
  @typedoc "The JSON-RPC message to send, encoded"
  @type message :: String.t()
  @type reason :: term()

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback send_message(t(), message()) :: :ok | {:error, reason()}
  @callback shutdown(t()) :: :ok | {:error, reason()}
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
| `:name` | [GenServer.name](https://hexdocs.pm/elixir/GenServer.html#t:name/0) | Registration name for the transport process | `__MODULE__` |
| `:client` | [GenServer.server](https://hexdocs.pm/elixir/GenServer.html#t:server/0) | The client process that will receive messages | Required |
| `:command` | string | The command to execute, it will be searched on `$PATH` | Required |
| `:args` | list(String.t()) | Command line arguments | `[]` |
| `:env` | map | Environment variables to merge into the default ones | System defaults |
| `:cwd` | string | Working directory | Current directory (aka `Path.expand(".")`) |

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
  env: %{"NODE_ENV" => "production"},
  cwd: "/path/to/server"
]}
```

## HTTP/SSE Transport

The HTTP/SSE transport (`Hermes.Transport.SSE`) enables communication with an MCP server over HTTP using [Server-Sent Events (SSE)](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events). It's suitable for remote integrations and provides secure communication over TLS.

### Configuration

```elixir
{Hermes.Transport.SSE, [
  name: MyApp.HTTPTransport,
  client: MyApp.MCPClient,
  server: [
    base_url: "https://example.com",
    base_path: "/mcp", # defaults to "/"
    sse_path: "/sse" # defaults to `:base_path` <> "/sse"
  ],
  headers: [{"Authorization", "Bearer token"}],
  transport_opts: [verify: :verify_peer],
  http_options: [request_timeout: 30_000]
]}
```

### Configuration Options

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `:name` | [GenServer.name](https://hexdocs.pm/elixir/GenServer.html#t:name/0) | Registration name for the transport process | `__MODULE__` |
| `:client` | [GenServer.server](https://hexdocs.pm/elixir/GenServer.html#t:server/0) | The client process that will receive messages | Required |
| `:server` | enumerable | The SSE server config | Required |
| `:server.base_url` | string | The SSE server base url | Required |
| `:server.base_path` | string | The SSE server base path | `"/"`|
| `:server.sse_path` | string | The SSE server base path for starting a SSE connection | `"/sse"`|
| `:headers` | map | Additional request headers to be sent | `%{}` |
| `:transport_opts` | keyword | Options to be passed to the underlying HTTP Client, you can check the avaiable options on [Mint docs](https://hexdocs.pm/mint/Mint.HTTP.html#connect/4-transport-options) | System defaults |
| `:http_options` | keyword | Options passed directly to the HTTP Client, you can check the available options on [Finch docs](https://hexdocs.pm/finch/Finch.html#t:request_opt/0) | Current directory |

## WebSocket Transport

The WebSocket transport (`Hermes.Transport.WebSocket`) enables bidirectional communication with an MCP server over WebSockets. It's suitable for remote integrations requiring real-time bidirectional communication and provides secure communication over TLS.

### Configuration

```elixir
{Hermes.Transport.WebSocket, [
  name: MyApp.WebSocketTransport,
  client: MyApp.MCPClient,
  server: [
    base_url: "https://example.com",
    base_path: "/mcp", # defaults to "/"
    ws_path: "/ws" # defaults to "/ws"
  ],
  headers: [{"Authorization", "Bearer token"}],
  transport_opts: [protocols: [:http], verify: :verify_peer]
]}
```

### Configuration Options

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `:name` | [GenServer.name](https://hexdocs.pm/elixir/GenServer.html#t:name/0) | Registration name for the transport process | `__MODULE__` |
| `:client` | [GenServer.server](https://hexdocs.pm/elixir/GenServer.html#t:server/0) | The client process that will receive messages | Required |
| `:server` | enumerable | The WebSocket server config | Required |
| `:server.base_url` | string | The WebSocket server base url | Required |
| `:server.base_path` | string | The WebSocket server base path | `"/"`|
| `:server.ws_path` | string | The WebSocket server endpoint path | `"/ws"`|
| `:headers` | map | Additional request headers to be sent | `%{}` |
| `:transport_opts` | keyword | Options to be passed to the underlying Gun client | `[protocols: [:http], http_opts: %{keepalive: :infinity}]` |

## Custom Transport Implementation

You can implement custom transports by creating a module that implements the `Hermes.Transport.Behaviour` behavior.

### Example: Custom TCP Transport

```elixir
defmodule MyApp.Transport.TCP do
  @behaviour Hermes.Transport.Behaviour

  use GenServer

  alias Hermes.Transport.Behaviour, as: Transport

  @impl Transport
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl Transport
  def send_message(pid, message) when is_binary(message) do
    GenServer.call(pid, {:send, message})
  end

  @impl Transport
  def shutdown(pid) do
    GenServer.cast(pid, :shutdown)
  end

  @impl GenServer
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

  @impl GenServer
  def handle_call({:send, message}, _from, %{socket: socket} = state) do
    case :gen_tcp.send(socket, message) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_cast(:shutdown, %{socket: socket} = state) do
    :gen_tcp.close(socket)
    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_info({:tcp, _socket, data}, %{client: client} = state) do
    # Forward data to client
    GenServer.cast(client, {:response, data})
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :normal, state}
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    {:stop, reason, state}
  end
end
```

## Transport Lifecycle Management

Transports in Hermes are designed to be supervised, with automatic recovery in case of failures:

```elixir
# In your supervision tree
children = [
  {Hermes.Transport.STDIO, transport_opts},
  {Hermes.Client, client_opts},
  # ...
]

# We recommend using :one_for_all strategy
# to restart all children if one of them fails
# since the client depends on the transport and vice-versa
opts = [strategy: :one_for_all]
Supervisor.start_link(children, opts)
```

## References

You can find more detailed information about MCP transport layers on the official [MCP specification](https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/transports/)
