setup-venv:
    @echo "Run: source priv/dev/echo/.venv/bin/activate"

echo-server transport="stdio":
    source priv/dev/echo/.venv/bin/activate && \
    mcp run -t {{transport}} priv/dev/echo/index.py

calculator-server transport="stdio":
    cd priv/dev/calculator && go build && ./calculator -t {{transport}} || cd -

[working-directory: 'priv/dev/upcase']
upcase-server:
    HERMES_MCP_SERVER=true iex -S mix

[working-directory: 'priv/dev/ascii']
ascii-server:
    iex -S mix phx.server

[working-directory: 'priv/dev/echo-elixir']
echo-ex-server transport="sse":
    MCP_TRANSPORT={{transport}} {{ if transport == "sse" { "iex -S mix phx.server" } else { "mix run --no-halt" } }}
