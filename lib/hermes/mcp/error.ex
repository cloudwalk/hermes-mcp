defmodule Hermes.MCP.Error do
  @moduledoc """
  Fluent API for building MCP protocol errors.

  This module provides a semantic interface for creating errors that comply with
  the MCP specification and JSON-RPC 2.0 error standards.

  ## Error Categories

  - **Protocol Errors**: Standard JSON-RPC errors (parse, invalid request, etc.)
  - **Transport Errors**: Connection and communication issues
  - **Resource Errors**: MCP-specific resource handling errors
  - **Execution Errors**: Tool and operation execution failures

  ## Examples

      # Protocol errors
      Hermes.MCP.Error.protocol(:parse_error)
      Hermes.MCP.Error.protocol(:method_not_found, %{method: "unknown"})

      # Transport errors
      Hermes.MCP.Error.transport(:connection_refused)
      Hermes.MCP.Error.transport(:timeout, %{elapsed_ms: 30000})

      # Resource errors
      Hermes.MCP.Error.resource(:not_found, %{uri: "file:///missing.txt"})

      # Execution errors with custom messages
      Hermes.MCP.Error.execution("Database connection failed", %{retries: 3})

      # Converting from JSON-RPC
      Hermes.MCP.Error.from_json_rpc(%{"code" => -32700, "message" => "Parse error"})
  """

  alias Hermes.MCP.ID
  alias Hermes.MCP.Message

  @type t :: %__MODULE__{
          code: integer(),
          reason: atom(),
          message: String.t() | nil,
          data: map()
        }

  defstruct [:code, :reason, :message, data: %{}]

  # JSON-RPC 2.0 standard error codes
  @parse_error -32_700
  @invalid_request -32_600
  @method_not_found -32_601
  @invalid_params -32_602
  @internal_error -32_603

  # MCP-specific error codes
  @resource_not_found -32_002

  # Generic server error code for custom errors
  @server_error -32_000

  # Standard error messages
  @error_messages %{
    parse_error: "Parse error",
    invalid_request: "Invalid Request",
    method_not_found: "Method not found",
    invalid_params: "Invalid params",
    internal_error: "Internal error",
    resource_not_found: "Resource not found",
    server_error: "Server error"
  }

  @doc """
  Creates a protocol-level error.

  These are standard JSON-RPC errors that occur during message parsing and validation.

  ## Supported Reasons

  - `:parse_error` - Invalid JSON was received
  - `:invalid_request` - The JSON is not a valid Request object
  - `:method_not_found` - The method does not exist
  - `:invalid_params` - Invalid method parameters
  - `:internal_error` - Internal JSON-RPC error

  ## Examples

      iex> Hermes.MCP.Error.protocol(:parse_error)
      %Hermes.MCP.Error{code: -32700, reason: :parse_error, message: "Parse error", data: %{}}

      iex> Hermes.MCP.Error.protocol(:method_not_found, %{method: "foo"})
      %Hermes.MCP.Error{code: -32601, reason: :method_not_found, message: "Method not found", data: %{method: "foo"}}
  """
  @spec protocol(atom(), map()) :: t()
  def protocol(reason, data \\ %{})

  def protocol(:parse_error, data) do
    %__MODULE__{
      code: @parse_error,
      reason: :parse_error,
      message: @error_messages.parse_error,
      data: data
    }
  end

  def protocol(:invalid_request, data) do
    %__MODULE__{
      code: @invalid_request,
      reason: :invalid_request,
      message: @error_messages.invalid_request,
      data: data
    }
  end

  def protocol(:method_not_found, data) do
    %__MODULE__{
      code: @method_not_found,
      reason: :method_not_found,
      message: @error_messages.method_not_found,
      data: data
    }
  end

  def protocol(:invalid_params, data) do
    %__MODULE__{
      code: @invalid_params,
      reason: :invalid_params,
      message: @error_messages.invalid_params,
      data: data
    }
  end

  def protocol(:internal_error, data) do
    %__MODULE__{
      code: @internal_error,
      reason: :internal_error,
      message: @error_messages.internal_error,
      data: data
    }
  end

  @doc """
  Creates a transport-level error.

  Used for network, connection, and communication failures.

  ## Examples

      iex> Hermes.MCP.Error.transport(:connection_refused)
      %Hermes.MCP.Error{code: -32000, reason: :connection_refused, message: "Connection Refused", data: %{}}

      iex> Hermes.MCP.Error.transport(:timeout, %{elapsed_ms: 5000})
      %Hermes.MCP.Error{code: -32000, reason: :timeout, message: "Timeout", data: %{elapsed_ms: 5000}}
  """
  @spec transport(atom(), map()) :: t()
  def transport(reason, data \\ %{}) when is_atom(reason) do
    message = reason |> to_string() |> humanize()

    %__MODULE__{
      code: @server_error,
      reason: reason,
      message: message,
      data: data
    }
  end

  @doc """
  Creates a resource-specific error.

  Used for MCP resource operations.

  ## Examples

      iex> Hermes.MCP.Error.resource(:not_found, %{uri: "file:///missing.txt"})
      %Hermes.MCP.Error{code: -32002, reason: :resource_not_found, message: "Resource not found", data: %{uri: "file:///missing.txt"}}
  """
  @spec resource(atom(), map()) :: t()
  def resource(:not_found, data \\ %{}) do
    %__MODULE__{
      code: @resource_not_found,
      reason: :resource_not_found,
      message: @error_messages.resource_not_found,
      data: data
    }
  end

  @doc """
  Creates an execution error with a custom message.

  Used for tool execution failures and domain-specific errors.

  ## Examples

      iex> Hermes.MCP.Error.execution("Database connection failed")
      %Hermes.MCP.Error{code: -32000, reason: :execution_error, message: "Database connection failed", data: %{}}

      iex> Hermes.MCP.Error.execution("API rate limit exceeded", %{retry_after: 60})
      %Hermes.MCP.Error{code: -32000, reason: :execution_error, message: "API rate limit exceeded", data: %{retry_after: 60}}
  """
  @spec execution(String.t(), map()) :: t()
  def execution(message, data \\ %{}) when is_binary(message) do
    %__MODULE__{
      code: @server_error,
      reason: :execution_error,
      message: message,
      data: data
    }
  end

  @doc """
  Creates an error from a JSON-RPC error object.

  ## Examples

      iex> Hermes.MCP.Error.from_json_rpc(%{"code" => -32700, "message" => "Parse error"})
      %Hermes.MCP.Error{code: -32700, reason: :parse_error, message: "Parse error", data: %{}}

      iex> Hermes.MCP.Error.from_json_rpc(%{"code" => -32002, "message" => "Not found", "data" => %{"uri" => "/file"}})
      %Hermes.MCP.Error{code: -32002, reason: :resource_not_found, message: "Not found", data: %{"uri" => "/file"}}
  """
  @spec from_json_rpc(map()) :: t()
  def from_json_rpc(%{"code" => code} = error) do
    %__MODULE__{
      code: code,
      reason: reason_from_code(code),
      message: Map.get(error, "message"),
      data: Map.get(error, "data", %{})
    }
  end

  @doc """
  Encodes the error as a JSON-RPC error response.

  ## Examples

      iex> error = Hermes.MCP.Error.protocol(:parse_error)
      iex> {:ok, encoded} = Hermes.MCP.Error.to_json_rpc(error, "req-123")
      iex> String.contains?(encoded, "Parse error")
      true
  """
  @spec to_json_rpc(t(), String.t() | integer()) ::
          {:ok, String.t()} | {:error, term()}
  def to_json_rpc(%__MODULE__{} = error, id \\ ID.generate_error_id()) do
    error_payload =
      %{
        "code" => error.code,
        "message" => error.message || default_message(error.reason),
        "data" => if(map_size(error.data) > 0, do: error.data)
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    Message.encode_error(%{"error" => error_payload}, id)
  end

  def build_json_rpc(%__MODULE__{} = error, id \\ ID.generate_error_id()) do
    %{
      "code" => error.code,
      "message" => error.message || default_message(error.reason),
      "data" => if(map_size(error.data) > 0, do: error.data)
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
    |> then(&%{"error" => &1, "id" => id})
  end

  # Private helpers

  defp reason_from_code(@parse_error), do: :parse_error
  defp reason_from_code(@invalid_request), do: :invalid_request
  defp reason_from_code(@method_not_found), do: :method_not_found
  defp reason_from_code(@invalid_params), do: :invalid_params
  defp reason_from_code(@internal_error), do: :internal_error
  defp reason_from_code(@resource_not_found), do: :resource_not_found
  defp reason_from_code(_), do: :server_error

  defp default_message(reason) do
    Map.get(@error_messages, reason, @error_messages.server_error)
  end

  defp humanize(string) when is_binary(string) do
    string
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end

defimpl Inspect, for: Hermes.MCP.Error do
  def inspect(%{reason: reason, message: message, data: data}, _opts) do
    details =
      cond do
        message && map_size(data) > 0 ->
          ": #{message} #{Kernel.inspect(data, pretty: true)}"

        message ->
          ": #{message}"

        map_size(data) > 0 ->
          " #{Kernel.inspect(data, pretty: true)}"

        true ->
          ""
      end

    "#MCP.Error<#{reason}#{details}>"
  end
end
