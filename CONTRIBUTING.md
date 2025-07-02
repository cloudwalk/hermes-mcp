# Contributing to Hermes MCP

Thank you for your interest in contributing to Hermes MCP! This document provides guidelines and instructions for contributing to the project.

Firstly, have sure to follow the official MCP (Model Context Protocol) [specification](https://spec.modelcontextprotocol.io/specification/2024-11-05/)!

## Development Setup

### Prerequisites

- Elixir 1.18+
- Erlang/OTP 26+
- Python 3.11+ with uv (for echo server)
- Go 1.21+ (for calculator server)
- Just command runner

### Getting Started

1. Clone the repository

   ```bash
   git clone https://github.com/cloudwalk/hermes-mcp.git
   cd hermes-mcp
   ```

2. Install dependencies

   ```bash
   mix setup
   ```

3. Run tests to ensure everything is working
   ```bash
   mix test
   ```

## Development Workflow

### Running MCP Servers

For development and testing, you can use the provided MCP server implementations:

```bash
# Start the Echo server (Python)
# For now only support stdio transport
just echo-server

# Start the Calculator server (Go)
# Supports both stdio and http/sse transport
just calculator-server sse
```

### Code Quality

Before submitting a pull request, ensure your code passes all quality checks:

```bash
# Run all code quality checks
mix lint

# Individual checks
mix format        # Code formatting
mix credo         # Linting
mix dialyzer      # Type checking
```

### Testing

Write tests for all new features and bug fixes:

```bash
# Run all tests
mix test
```

## Submitting Contributions

1. Create a new branch for your feature or bugfix

   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes and commit them with clear, descriptive messages

3. Push your branch to GitHub

   ```bash
   git push origin feature/your-feature-name
   ```

4. Open a pull request against the main branch

## Pull Request Guidelines

- Follow the existing code style and conventions
- Include tests for new functionality
- Update documentation as needed
- Keep pull requests focused on a single topic
- Reference any related issues in your PR description

## Documentation

Update documentation for any user-facing changes:

- Update relevant sections in `pages/` directory
- Add examples for new features
- Document any breaking changes

## Release Process

Releases are managed by the maintainers. Version numbers follow [Semantic Versioning](https://semver.org/).

## License

By contributing to Hermes MCP, you agree that your contributions will be licensed under the project's [MIT License](./LICENSE).
