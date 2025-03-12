# Hermes MCP

A high-performance Model Context Protocol (MCP) implementation in Elixir with first-class Phoenix support.

## Overview

Hermes MCP provides a unified solution for building both MCP clients and servers in Elixir, leveraging the language's exceptional concurrency model and fault tolerance capabilities. The library currently focuses on a robust client implementation, with server functionality planned for future releases.

## Implementation Status

- ✅ Complete client implementation with protocol lifecycle management
- ✅ STDIO transport for local process communication
- ✅ HTTP/SSE transport for production-ready and async process communication
- ✅ Comprehensive capability negotiation
- ✅ Robust error handling and recovery
- 🔄 Phoenix integration (in progress)
- 🔄 Full server implementation (planned)

## Protocol Compliance

Hermes MCP implements the [Model Context Protocol specification](https://spec.modelcontextprotocol.io/specification/2024-11-05/), ensuring interoperability with other MCP-compliant tools and services. The library handles all aspects of the MCP lifecycle, from initialization and capability negotiation to request routing and response handling.

## Why Hermes?

The library is named after Hermes, the Greek god of boundaries, communication, and commerce. This namesake reflects the core purpose of the Model Context Protocol: to establish standardized communication between AI applications and external tools. Like Hermes who served as a messenger between gods and mortals, this library facilitates seamless interaction between Large Language Models and various data sources or tools.

Furthermore, Hermes was known for his speed and reliability in delivering messages, which aligns with our implementation's focus on high performance and fault tolerance in the Elixir ecosystem.
