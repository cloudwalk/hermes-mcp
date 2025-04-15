# Hermes MCP

A high-performance Model Context Protocol (MCP) implementation in Elixir with first-class Phoenix support.

## Overview

Hermes MCP provides a unified solution for building both MCP clients and servers in Elixir, leveraging the language's exceptional concurrency model and fault tolerance capabilities. The library currently focuses on a robust client implementation, with server functionality planned for future releases.

## Key Features

- **High-Performance Client**: Built for concurrency and fault tolerance
- **Multiple Transport Options**: Support for SSE and STDIO transports
- **Interactive CLI Tools**: Command-line interfaces for testing and debugging ([CLI Usage Guide](cli_usage.html))
- **Protocol-Compliant**: Full implementation of the Model Context Protocol specification

## Protocol Compliance

Hermes MCP implements the [Model Context Protocol specification](https://spec.modelcontextprotocol.io/specification/2024-11-05/), ensuring interoperability with other MCP-compliant tools and services. The library handles all aspects of the MCP lifecycle, from initialization and capability negotiation to request routing and response handling.

## Why Hermes?

The library is named after Hermes, the Greek god of boundaries, communication, and commerce. This namesake reflects the core purpose of the Model Context Protocol: to establish standardized communication between AI applications and external tools. Like Hermes who served as a messenger between gods and mortals, this library facilitates seamless interaction between Large Language Models and various data sources or tools.

Furthermore, Hermes was known for his speed and reliability in delivering messages, which aligns with our implementation's focus on high performance and fault tolerance in the Elixir ecosystem.
