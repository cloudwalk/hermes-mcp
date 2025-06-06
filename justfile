setup-venv:
    @echo "Run: source priv/dev/echo/.venv/bin/activate"

echo-server transport="stdio":
    source priv/dev/echo/.venv/bin/activate && \
    mcp run -t {{transport}} priv/dev/echo/index.py

calculator-server transport="stdio":
    cd priv/dev/calculator && go build && ./calculator -t {{transport}} || cd -

[working-directory: 'priv/dev/upcase']
build-upcase-server:
    mix assemble 1>/dev/null

[working-directory: 'priv/dev/upcase']
upcase-server transport="stdio": build-upcase-server
    ./upcase

[working-directory: 'priv/dev/ascii']
ascii-server:
    iex -S mix phx.server
