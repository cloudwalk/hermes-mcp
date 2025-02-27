setup-venv:
    @echo "Run: source priv/dev/echo/.venv/bin/activate"

echo-server transport="stdio":
    source priv/dev/echo/.venv/bin/activate && \
    mcp run -t {{transport}} priv/dev/echo/index.py

calculator-server transport="stdio":
    cd priv/dev/calculator && go build && ./calculator -t {{transport}} || cd -
