# Hermes MCP Development Guide

## Build & Test Commands
```bash
# Setup dependencies
mix deps.get

# Compile code 
mix compile

# Run all tests
mix test

# Run a single test
mix test test/path/to/test_file.exs:line_number

# Format code
mix format

# Run linting
mix credo

# Type checking
mix dialyxir

# Generate documentation
mix docs

# Start dev servers
just echo-server
just calculator-server
```

## Code Style Guidelines
- **Formatting**: Follow .formatter.exs rules with Peri imports
- **Types**: Use @type/@spec for all public functions
- **Naming**: snake_case for functions, PascalCase modules
- **Imports**: Group imports at top, organize by category
- **Documentation**: Include @moduledoc and @doc with examples
- **Error Handling**: Pattern match with {:ok, _} and {:error, reason}
- **Testing**: Descriptive test blocks, use Mox for mocking
- **Constants**: Define defaults as module attributes (@default_*)