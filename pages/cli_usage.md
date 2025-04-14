# Interactive CLI Usage

Hermes MCP provides interactive command-line interfaces that allow you to directly interact with MCP servers. These CLI tools are useful for:

- Testing and debugging MCP servers
- Exploring available tools and resources
- Rapid prototyping and development
- Diagnostic purposes

## Available CLI Tools

Hermes provides two built-in interactive CLIs:

1. **SSE Interactive**: For connecting to HTTP/SSE MCP servers
2. **STDIO Interactive**: For connecting to STDIO-based MCP servers

## Starting the CLI

### SSE Interactive

The SSE interactive CLI connects to HTTP-based MCP servers using Server-Sent Events (SSE).

```shell
mix hermes.sse.interactive --base-url=https://your-mcp-server.com
```

### STDIO Interactive

The STDIO interactive CLI connects to subprocess-based MCP servers using standard input/output.

```shell
mix hermes.stdio.interactive --command=path/to/server --args=arg1,arg2
```

## Command-Line Options

Both CLIs support the following common options:

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message and exit |
| `-v, --verbose` | Enable verbose output and detailed error information |

### SSE Transport Options

| Option | Description | Default |
|--------|-------------|---------|
| `--base-url URL` | Base URL for SSE server | http://localhost:8000 |
| `--base-path PATH` | Base path for the SSE server | / |
| `--sse-path PATH` | Path for SSE endpoint | /sse |

### STDIO Transport Options

| Option | Description | Default |
|--------|-------------|---------|
| `-c, --command CMD` | Command to execute | mcp |
| `--args ARGS` | Comma-separated arguments for the command | run,priv/dev/echo/index.py |

## Interactive Commands

Once connected, the CLI provides an interactive shell with several commands:

| Command | Description |
|---------|-------------|
| `help` | Show list of available commands |
| `list_tools` | List available server tools |
| `call_tool` | Call a server tool with arguments |
| `list_prompts` | List available server prompts |
| `get_prompt` | Get a server prompt |
| `list_resources` | List available server resources |
| `read_resource` | Read a server resource |
| `show_state` | Show internal state of client and transport |
| `initialize` | Retry server connection initialization |
| `clear` | Clear the screen |
| `exit` | Exit the interactive session |

### Using the `show_state` Command

The `show_state` command provides detailed information about the internal state of both the client and transport processes. This is particularly useful for debugging connection issues.

```
mcp> show_state
```

This will display:
- Client state information (protocol version, client info, server capabilities, etc.)
- Transport state (connection details, status)
- Pending requests (if any)

For more detailed error information, use the `--verbose` flag when starting the CLI or set the `HERMES_VERBOSE=1` environment variable.

## Examples

### Connecting to a Local SSE Server

```shell
mix hermes.sse.interactive
```

### Connecting to a Remote SSE Server

```shell
mix hermes.sse.interactive --base-url=https://remote-server.example.com --verbose
```

### Running a Local MCP Server with STDIO

```shell
mix hermes.stdio.interactive --command=./my-mcp-server --args=arg1,arg2
```

### Calling a Tool

```
mcp> list_tools
# Lists available tools

mcp> call_tool
Tool name: calculator
Tool arguments (JSON): {"operation": "+", "a": 1, "b": 2}
# Returns: 3
```

### Advanced Debugging

```shell
# Enable verbose mode
HERMES_VERBOSE=1 mix hermes.sse.interactive

# Or use the command-line flag
mix hermes.sse.interactive -v
```

Then use the `show_state` command to see detailed internal state information, or examine extended error information when initialization fails.