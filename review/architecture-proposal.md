# Hermes MCP Architecture Proposal

## Introduction

This document proposes a revised architecture for the Hermes MCP client implementation, addressing issues identified in the code review. The goal is to create a more maintainable, reliable, and semantically clear codebase that better follows Elixir/OTP best practices while maintaining full compliance with the MCP specification.

## Core Principles

1. **Clean Domain Modeling**: Use proper types to represent MCP protocol concepts
2. **Simplified State Management**: Clear, explicit state management for client and transport
3. **OTP Best Practices**: Follow Elixir/OTP idioms and patterns
4. **Complete Documentation**: Thorough @doc and @spec annotations for all public APIs
5. **Comprehensive Testing**: Unit and integration tests for all components

## Revised Architecture

### 1. MCP Domain Model

```elixir
defmodule Hermes.MCP.Error do
  @moduledoc """
  Represents errors in the MCP protocol.
  
  This module defines standardized error types based on the JSON-RPC 2.0
  error codes, with additional MCP-specific error reasons.
  """
  
  @type t :: %__MODULE__{
    code: integer(),
    reason: atom(),
    message: String.t(),
    data: map()
  }
  
  defstruct [:code, :reason, :message, data: %{}]
  
  # Standard JSON-RPC error codes
  @parse_error -32700
  @invalid_request -32600
  @method_not_found -32601
  @invalid_params -32602
  @internal_error -32603
  
  @doc """
  Creates a parse error.
  """
  @spec parse_error(String.t(), map()) :: t()
  def parse_error(message \\ "Parse error", data \\ %{}) do
    %__MODULE__{
      code: @parse_error,
      reason: :parse_error,
      message: message,
      data: data
    }
  end
  
  @doc """
  Creates an invalid request error.
  """
  @spec invalid_request(String.t(), map()) :: t()
  def invalid_request(message \\ "Invalid request", data \\ %{}) do
    %__MODULE__{
      code: @invalid_request,
      reason: :invalid_request,
      message: message,
      data: data
    }
  end
  
  @doc """
  Creates a method not found error.
  """
  @spec method_not_found(String.t(), map()) :: t()
  def method_not_found(message \\ "Method not found", data \\ %{}) do
    %__MODULE__{
      code: @method_not_found,
      reason: :method_not_found,
      message: message,
      data: data
    }
  end
  
  @doc """
  Creates an invalid params error.
  """
  @spec invalid_params(String.t(), map()) :: t()
  def invalid_params(message \\ "Invalid params", data \\ %{}) do
    %__MODULE__{
      code: @invalid_params,
      reason: :invalid_params,
      message: message,
      data: data
    }
  end
  
  @doc """
  Creates an internal error.
  """
  @spec internal_error(String.t(), map()) :: t()
  def internal_error(message \\ "Internal error", data \\ %{}) do
    %__MODULE__{
      code: @internal_error,
      reason: :internal_error,
      message: message,
      data: data
    }
  end
  
  @doc """
  Creates a transport-related error.
  """
  @spec transport_error(atom(), String.t(), map()) :: t()
  def transport_error(reason, message, data \\ %{}) when is_atom(reason) do
    %__MODULE__{
      code: -32000, # Server error range
      reason: reason,
      message: message,
      data: Map.put(data, :type, :transport)
    }
  end
  
  @doc """
  Creates a client-related error.
  """
  @spec client_error(atom(), String.t(), map()) :: t()
  def client_error(reason, message, data \\ %{}) when is_atom(reason) do
    %__MODULE__{
      code: -32000, # Server error range
      reason: reason,
      message: message,
      data: Map.put(data, :type, :client)
    }
  end
  
  @doc """
  Converts from a JSON-RPC error.
  """
  @spec from_json_rpc(map()) :: t()
  def from_json_rpc(%{"code" => code, "message" => message} = error) do
    data = Map.get(error, "data", %{})
    reason = reason_for_code(code)
    
    %__MODULE__{
      code: code,
      reason: reason,
      message: message,
      data: data
    }
  end
  
  # Private helper functions
  defp reason_for_code(@parse_error), do: :parse_error
  defp reason_for_code(@invalid_request), do: :invalid_request
  defp reason_for_code(@method_not_found), do: :method_not_found
  defp reason_for_code(@invalid_params), do: :invalid_params
  defp reason_for_code(@internal_error), do: :internal_error
  defp reason_for_code(_), do: :server_error
end

defmodule Hermes.MCP.Response do
  @moduledoc """
  Represents successful responses in the MCP protocol.
  
  Provides a wrapper around JSON-RPC responses that includes
  domain-specific error handling for MCP's "isError" field.
  """
  
  @type t :: %__MODULE__{
    result: map(),
    id: String.t(),
    is_error: boolean()
  }
  
  defstruct [:result, :id, is_error: false]
  
  @doc """
  Creates a Response struct from a JSON-RPC response.
  """
  @spec from_json_rpc(map()) :: t()
  def from_json_rpc(%{"result" => result, "id" => id}) do
    is_error = is_map(result) && Map.get(result, "isError", false)
    
    %__MODULE__{
      result: result,
      id: id,
      is_error: is_error
    }
  end
  
  @doc """
  Unwraps the response, handling domain-level errors.
  
  Returns either:
  - `{:ok, result}` for successful responses
  - `{:error, result}` for responses with isError: true
  """
  @spec unwrap(t()) :: {:ok, map()} | {:error, map()}
  def unwrap(%__MODULE__{result: result, is_error: false}), do: {:ok, result}
  def unwrap(%__MODULE__{result: result, is_error: true}), do: {:error, result}
  
  @doc """
  Checks if the response is successful.
  """
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{is_error: false}), do: true
  def success?(_), do: false
  
  @doc """
  Checks if the response has a domain error.
  """
  @spec error?(t()) :: boolean()
  def error?(%__MODULE__{is_error: true}), do: true
  def error?(_), do: false
end

defmodule Hermes.MCP.ID do
  @moduledoc """
  Utilities for working with MCP message identifiers.
  """
  
  @doc """
  Generates a unique request ID.
  
  Creates a Base64 encoded string with:
  - Timestamp component
  - Process identifier hash
  - Random component
  """
  @spec generate() :: String.t()
  def generate do
    <<
      System.system_time(:nanosecond)::64,
      :erlang.phash2({node(), self()}, 16_777_216)::24,
      :rand.uniform(16_777_216)::24
    >>
    |> Base.url_encode64()
  end
  
  @doc """
  Generates a unique progress token.
  """
  @spec generate_progress_token() :: String.t()
  def generate_progress_token do
    "progress_" <> generate()
  end
  
  @doc """
  Extracts timestamp from an ID for debugging purposes.
  """
  @spec timestamp_from_id(String.t()) :: integer() | nil
  def timestamp_from_id(id) when is_binary(id) do
    case Base.url_decode64(id) do
      {:ok, <<timestamp::64, _::48>>} -> 
        timestamp
      _ -> 
        nil
    end
  end
end

defmodule Hermes.MCP.Message do
  @moduledoc """
  Handles encoding and decoding of MCP protocol messages.
  
  This module provides functions for parsing, validating, and creating
  MCP (Model Context Protocol) messages using the JSON-RPC 2.0 format.
  """
  
  import Peri
  
  alias Hermes.MCP.{Error, Response, ID}
  
  # Message type guard functions
  defguard is_request(data) when is_map_key(data, "method") and is_map_key(data, "id")
  defguard is_notification(data) when is_map_key(data, "method") and not is_map_key(data, "id")
  defguard is_response(data) when is_map_key(data, "result") and is_map_key(data, "id")
  defguard is_error(data) when is_map_key(data, "error") and is_map_key(data, "id")
  
  @doc """
  Decodes a JSON string into MCP message(s).
  
  Returns either:
  - `{:ok, messages}` where messages is a list of parsed MCP messages
  - `{:error, error}` if parsing fails
  """
  @spec decode(String.t()) :: {:ok, list(map())} | {:error, Hermes.MCP.Error.t()}
  def decode(data) when is_binary(data) do
    # Implementation similar to current Hermes.Message.decode/1
    # but using the new Error type
  end
  
  @doc """
  Encodes a request message into a JSON-RPC 2.0 compliant string.
  
  Returns the encoded string with a newline character appended.
  """
  @spec encode_request(map(), String.t()) :: {:ok, String.t()} | {:error, Hermes.MCP.Error.t()}
  def encode_request(request, id) do
    # Implementation similar to current encode_request
  end
  
  @doc """
  Encodes a notification message into a JSON-RPC 2.0 compliant string.
  
  Returns the encoded string with a newline character appended.
  """
  @spec encode_notification(map()) :: {:ok, String.t()} | {:error, Hermes.MCP.Error.t()}
  def encode_notification(notification) do
    # Implementation similar to current encode_notification
  end
  
  # Additional encoding/decoding functions with proper @spec annotations
end
```

### 2. Client State Management

```elixir
defmodule Hermes.Client.State do
  @moduledoc """
  Manages state for the Hermes MCP client.
  
  This module provides a structured representation of client state,
  including capabilities, server info, and request tracking.
  """
  
  alias Hermes.MCP.Error
  
  @type t :: %__MODULE__{
    client_info: map(),
    capabilities: map(),
    server_capabilities: map() | nil,
    server_info: map() | nil,
    protocol_version: String.t(),
    request_timeout: integer(),
    transport: module() | {module(), atom()},
    pending_requests: map(),
    callbacks: %{
      progress: %{String.t() => (String.t(), number(), number() | nil -> any())},
      log: nil | (String.t(), term(), String.t() | nil -> any())
    }
  }
  
  defstruct [
    :client_info,
    :capabilities,
    :server_capabilities,
    :server_info,
    :protocol_version,
    :request_timeout,
    :transport,
    pending_requests: %{},
    callbacks: %{
      progress: %{},
      log: nil
    }
  ]
  
  @doc """
  Creates a new client state with the given options.
  """
  @spec new(map()) :: t()
  def new(opts) do
    %__MODULE__{
      client_info: opts.client_info,
      capabilities: opts.capabilities,
      protocol_version: opts.protocol_version,
      request_timeout: opts.request_timeout,
      transport: opts.transport
    }
  end
  
  @doc """
  Adds a new request to the state.
  """
  @spec add_request(t(), String.t(), GenServer.from(), String.t()) :: t()
  def add_request(state, id, from, method) do
    timer_ref = Process.send_after(self(), {:request_timeout, id}, state.request_timeout)
    request = {from, method, timer_ref, System.monotonic_time(:millisecond)}
    
    %{state | pending_requests: Map.put(state.pending_requests, id, request)}
  end
  
  @doc """
  Gets a request by ID.
  """
  @spec get_request(t(), String.t()) :: {GenServer.from(), String.t(), reference(), integer()} | nil
  def get_request(state, id) do
    Map.get(state.pending_requests, id)
  end
  
  @doc """
  Removes a request and returns its info along with the updated state.
  """
  @spec remove_request(t(), String.t()) :: {map() | nil, t()}
  def remove_request(state, id) do
    case Map.pop(state.pending_requests, id) do
      {nil, _} -> 
        {nil, state}
        
      {{from, method, timer_ref, start_time}, requests} ->
        Process.cancel_timer(timer_ref)
        elapsed = System.monotonic_time(:millisecond) - start_time
        
        request_info = %{from: from, method: method, elapsed_ms: elapsed}
        {request_info, %{state | pending_requests: requests}}
    end
  end
  
  @doc """
  Handles a request timeout, responding to the caller with an error.
  """
  @spec handle_request_timeout(t(), String.t()) :: t()
  def handle_request_timeout(state, id) do
    case Map.pop(state.pending_requests, id) do
      {nil, _} -> 
        state
        
      {{from, method, _timer, start_time}, requests} ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        error = Error.client_error(:request_timeout, "Request timed out after #{elapsed}ms")
        
        GenServer.reply(from, {:error, error})
        %{state | pending_requests: requests}
    end
  end
  
  @doc """
  Registers a progress callback for a token.
  """
  @spec add_progress_callback(t(), String.t(), (String.t(), number(), number() | nil -> any())) :: t()
  def add_progress_callback(state, token, callback) when is_function(callback, 3) do
    callbacks = put_in(state.callbacks.progress, Map.put(state.callbacks.progress, token, callback))
    %{state | callbacks: callbacks}
  end
  
  @doc """
  Gets a progress callback for a token.
  """
  @spec get_progress_callback(t(), String.t()) :: (String.t(), number(), number() | nil -> any()) | nil
  def get_progress_callback(state, token) do
    get_in(state.callbacks, [:progress, token])
  end
  
  @doc """
  Unregisters a progress callback for a token.
  """
  @spec remove_progress_callback(t(), String.t()) :: t()
  def remove_progress_callback(state, token) do
    callbacks = put_in(state.callbacks.progress, Map.delete(state.callbacks.progress, token))
    %{state | callbacks: callbacks}
  end
  
  @doc """
  Sets the log callback.
  """
  @spec set_log_callback(t(), (String.t(), term(), String.t() | nil -> any())) :: t()
  def set_log_callback(state, callback) when is_function(callback, 3) do
    callbacks = put_in(state.callbacks.log, callback)
    %{state | callbacks: callbacks}
  end
  
  @doc """
  Gets the log callback.
  """
  @spec get_log_callback(t()) :: (String.t(), term(), String.t() | nil -> any()) | nil
  def get_log_callback(state) do
    get_in(state.callbacks, [:log])
  end
  
  @doc """
  Updates server info after initialization.
  """
  @spec update_server_info(t(), map(), map()) :: t()
  def update_server_info(state, capabilities, server_info) do
    %{state | 
      server_capabilities: capabilities,
      server_info: server_info
    }
  end
  
  @doc """
  Returns a list of all pending requests.
  """
  @spec list_pending_requests(t()) :: list(map())
  def list_pending_requests(state) do
    current_time = System.monotonic_time(:millisecond)
    
    Enum.map(state.pending_requests, fn {id, {_from, method, _timer, start_time}} ->
      elapsed = current_time - start_time
      %{id: id, method: method, elapsed_ms: elapsed}
    end)
  end
end
```

### 3. Callback Handling

```elixir
defmodule Hermes.Client.Callback do
  @moduledoc """
  Safe callback execution for Hermes MCP client.
  """
  
  require Logger
  
  @doc """
  Safely executes a progress callback.
  """
  @spec execute_progress(function(), String.t(), number(), number() | nil) :: {:ok, pid()} | :not_found
  def execute_progress(callback, token, progress, total) when is_function(callback, 3) do
    Task.start(fn ->
      try do
        callback.(token, progress, total)
      rescue
        e -> Logger.error("Progress callback error: #{inspect(e)}")
      end
    end)
  end
  
  @doc """
  Safely executes a log callback.
  """
  @spec execute_log(function(), String.t(), term(), String.t() | nil) :: {:ok, pid()} | :not_found
  def execute_log(callback, level, data, logger) when is_function(callback, 3) do
    Task.start(fn ->
      try do
        callback.(level, data, logger)
      rescue
        e -> Logger.error("Log callback error: #{inspect(e)}")
      end
    end)
  end
  
  @doc """
  Logs a message to Elixir's logger.
  """
  @spec log_to_logger(String.t(), term(), String.t() | nil) :: :ok
  def log_to_logger(level, data, logger) do
    prefix = if logger, do: "[#{logger}] ", else: ""
    message = "#{prefix}#{inspect(data)}"
    
    case level do
      level when level in ["debug"] -> Logger.debug(message)
      level when level in ["info", "notice"] -> Logger.info(message)
      level when level in ["warning"] -> Logger.warning(message)
      level when level in ["error", "critical", "alert", "emergency"] -> Logger.error(message)
      _ -> Logger.info(message)
    end
  end
end
```

### 4. Transport State

```elixir
defmodule Hermes.Transport.State do
  @moduledoc """
  Manages state for transport connections.
  
  This module provides a structured representation of transport state,
  including connection status, errors, and retry information.
  """
  
  @type status :: :disconnected | :connecting | :connected | :disconnecting | :error
  
  @type t :: %__MODULE__{
    name: atom(),
    type: atom(),
    endpoint: String.t() | nil,
    client: pid() | atom(),
    connected_at: DateTime.t() | nil,
    last_error: term() | nil,
    status: status(),
    reconnect_count: non_neg_integer(),
    options: map()
  }
  
  defstruct [
    :name,
    :type,
    :endpoint,
    :client,
    :connected_at,
    :last_error,
    status: :disconnected,
    reconnect_count: 0,
    options: %{}
  ]
  
  @doc """
  Creates a new transport state.
  """
  @spec new(atom(), atom(), String.t() | nil, pid() | atom(), map()) :: t()
  def new(name, type, endpoint, client, options \\ %{}) do
    %__MODULE__{
      name: name,
      type: type,
      endpoint: endpoint,
      client: client,
      options: options
    }
  end
  
  @doc """
  Updates state to reflect a connection attempt.
  """
  @spec connecting(t()) :: t()
  def connecting(state) do
    %{state | status: :connecting}
  end
  
  @doc """
  Updates state to reflect a successful connection.
  """
  @spec connected(t()) :: t()
  def connected(state) do
    %{state | 
      status: :connected,
      connected_at: DateTime.utc_now(),
      last_error: nil
    }
  end
  
  @doc """
  Updates state to reflect a disconnection.
  """
  @spec disconnected(t(), term() | nil) :: t()
  def disconnected(state, error \\ nil) do
    %{state | 
      status: :disconnected,
      last_error: error,
      reconnect_count: state.reconnect_count + 1
    }
  end
  
  @doc """
  Updates state to reflect a connection error.
  """
  @spec error(t(), term()) :: t()
  def error(state, error) do
    %{state | 
      status: :error,
      last_error: error
    }
  end
  
  @doc """
  Returns a map with the current transport info.
  """
  @spec info(t()) :: map()
  def info(state) do
    %{
      name: state.name,
      type: state.type,
      endpoint: state.endpoint,
      status: state.status,
      connected_at: state.connected_at,
      reconnect_count: state.reconnect_count,
      last_error: state.last_error
    }
  end
  
  @doc """
  Determines if a reconnection should be attempted.
  """
  @spec should_reconnect?(t(), pos_integer() | nil) :: boolean()
  def should_reconnect?(state, max_attempts \\ nil) do
    state.status in [:disconnected, :error] and
      (max_attempts == nil or state.reconnect_count < max_attempts)
  end
end
```

### 5. Telemetry Integration

```elixir
defmodule Hermes.Telemetry do
  @moduledoc """
  Telemetry integration for Hermes MCP.
  """
  
  @prefix [:hermes, :mcp]
  
  @doc """
  Emits a telemetry event.
  """
  @spec emit(atom() | list(atom()), map(), map()) :: :ok
  def emit(event, measurements \\ %{}, metadata \\ %{}) do
    :telemetry.execute(@prefix ++ List.wrap(event), measurements, metadata)
  end
  
  @doc """
  Wraps a function with start/stop telemetry events.
  """
  @spec span(atom() | list(atom()), map(), (() -> any())) :: any()
  def span(event, metadata \\ %{}, fun) do
    start_time = System.monotonic_time()
    emit([:start] ++ List.wrap(event), %{time: start_time}, metadata)
    
    try do
      result = fun.()
      end_time = System.monotonic_time()
      duration = end_time - start_time
      
      emit([:stop] ++ List.wrap(event), %{
        time: end_time,
        duration: duration
      }, metadata)
      
      result
    rescue
      error ->
        end_time = System.monotonic_time()
        duration = end_time - start_time
        
        emit([:exception] ++ List.wrap(event), %{
          time: end_time,
          duration: duration
        }, Map.merge(metadata, %{
          error: error,
          stacktrace: __STACKTRACE__
        }))
        
        reraise error, __STACKTRACE__
    end
  end
end
```

## Implementation Roadmap

### Phase 1: Domain Model and Core Types
1. Create `Hermes.MCP` context with `Error`, `Response`, `ID`, and `Message` modules
2. Ensure complete documentation with @doc and @spec for all public functions
3. Write comprehensive unit tests for these core types

### Phase 2: Client State Management
1. Implement `Hermes.Client.State` for client state management
2. Create helper module for callback management
3. Add extensive tests for state transitions and edge cases

### Phase 3: Transport Abstractions
1. Implement `Hermes.Transport.State` for connection state tracking
2. Enhance transport behavior with error handling improvements
3. Add tests for transport state transitions and reconnection

### Phase 4: Integration and Refactoring
1. Refactor `Hermes.Client` to use the new state management
2. Update transport implementations to use the new state tracking
3. Create integration tests for the client-transport interaction

### Phase 5: Testing and Documentation
1. Fix existing test suite to accommodate API changes
2. Complete documentation for all modules and functions
3. Add example usage patterns in documentation

## Key Benefits

1. **Clean Domain Model**: Better representation of MCP types (Error, Response)
2. **Simplified Architecture**: No unnecessary components for 1:1:1 relationships
3. **Properly Documented**: Complete @doc and @spec annotations
4. **Maintainable Structure**: Clear module organization with MCP context
5. **OTP Best Practices**: Proper process supervision and relationships
6. **Comprehensive Testing**: Unit and integration tests for all components

This architecture maintains the 1:1:1 relationship between client, transport, and server as per the MCP spec, avoids unnecessary abstractions, improves code organization, and ensures proper documentation and testing.