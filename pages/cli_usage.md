# Interactive CLI

Test and debug MCP servers with Hermes interactive CLI.

## Available CLIs

- **STDIO Interactive** - For local subprocess servers
- **StreamableHTTP Interactive** - For HTTP/SSE servers  
- **WebSocket Interactive** - For WebSocket servers
- **SSE Interactive** - For legacy SSE servers

## Quick Start

### STDIO Server

```shell
mix hermes.stdio.interactive --command=python --args=-m,mcp.server,my_server.py
```

### HTTP Server

```shell
mix hermes.streamable_http.interactive --base-url=http://localhost:8080
```

### WebSocket Server

```shell
mix hermes.websocket.interactive --base-url=ws://localhost:8081
```

## Common Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help |
| `-v` | Increase verbosity (can stack: `-vvv`) |

Verbosity levels:
- No flag: Errors only
- `-v`: + Warnings
- `-vv`: + Info
- `-vvv`: + Debug

## Interactive Commands

| Command | Description |
|---------|-------------|
| `help` | Show available commands |
| `ping` | Check server connection |
| `list_tools` | List available tools |
| `call_tool` | Call a tool |
| `list_prompts` | List prompts |
| `get_prompt` | Get prompt messages |
| `list_resources` | List resources |
| `read_resource` | Read resource content |
| `show_state` | Debug state info |
| `clear` | Clear screen |
| `exit` | Exit CLI |

## Examples

### Test Local Server

```shell
# Start interactive session
mix hermes.stdio.interactive --command=./my-server

# In the CLI
mcp> ping
pong

mcp> list_tools
Available tools:
- calculator: Perform calculations
- file_reader: Read files

mcp> call_tool
Tool name: calculator
Tool arguments (JSON): {"operation": "add", "a": 5, "b": 3}
Result: 8
```

### Debug Connection

```shell
# Verbose mode
mix hermes.streamable_http.interactive -vvv --base-url=http://api.example.com

mcp> show_state
Client State:
  Protocol: 2025-03-26
  Initialized: true
  Capabilities: %{"tools" => %{}}
  
Transport State:
  Type: StreamableHTTP
  URL: http://api.example.com
  Connected: true
```

### Test Tool Execution

```
mcp> list_tools
mcp> call_tool
Tool name: search
Tool arguments (JSON): {"query": "elixir"}
```

## Transport-Specific Options

### STDIO

| Option | Description | Default |
|--------|-------------|---------|
| `--command` | Command to run | `mcp` |
| `--args` | Comma-separated args | none |

### StreamableHTTP

| Option | Description | Default |
|--------|-------------|---------|
| `--base-url` | Server URL | `http://localhost:8080` |
| `--base-path` | Base path | `/` |

### WebSocket

| Option | Description | Default |
|--------|-------------|---------|
| `--base-url` | WebSocket URL | `ws://localhost:8081` |
| `--ws-path` | WebSocket path | `/ws` |

## Tips

1. Use `-vvv` for debugging connection issues
2. `show_state` reveals internal state
3. JSON arguments must be valid JSON
4. Exit with `exit` or Ctrl+C