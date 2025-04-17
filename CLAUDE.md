# Hermes MCP Development Guide

## Build & Test Commands
```bash
# Setup dependencies
mix deps.get

# Compile code 
mix compile --force --warnings-as-errors

# Run all tests
mix test

# Run tests without stderr output (suppresses "broken pipe" messages)
mix test 2>/dev/null

# Run a single test
mix test test/path/to/test_file.exs:line_number

# Format code
mix format

# Run linting
mix credo --strict

# Type checking
mix dialyzer

# Generate documentation
mix docs

# Start dev servers
just echo-server
just calculator-server
```

## Code Style Guidelines
- **Code Comments**: Only add code comments if strictly necessary, avoid it generally
- **Formatting**: Follow .formatter.exs rules with Peri imports
- **Types**: Use @type/@spec for all public functions
- **Naming**: snake_case for functions, PascalCase modules
- **Imports**: Group imports at top, organize by category
- **Documentation**: Include @moduledoc and @doc with examples
- **Error Handling**: Pattern match with {:ok, _} and {:error, reason}
- **Testing**: Descriptive test blocks, use Mox for mocking
- **Constants**: Define defaults as module attributes (@default_*)
