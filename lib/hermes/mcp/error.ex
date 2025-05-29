defmodule Hermes.MCP.Error do
  @moduledoc """
  Represents errors in the MCP protocol.

  This module defines standardized error types based on the JSON-RPC 2.0
  error codes, with additional MCP-specific error reasons.

  ## Error Structure

  Each error includes:
  - `code`: Numeric error code (following JSON-RPC 2.0 conventions)
  - `reason`: Atom representing the error type (e.g., `:parse_error`, `:timeout`)
  - `data`: Additional context or metadata about the error

  ## Error Categories

  Errors are categorized into:
  - Standard JSON-RPC errors (parse errors, invalid requests, etc.)
  - Transport errors (connection issues, timeouts)
  - Client errors (request handling issues)
  - Server errors (capability issues, domain errors)

  ## Examples

  ```elixir
  # Creating standard RPC errors
  Hermes.MCP.Error.parse_error()

  # Creating transport errors
  Hermes.MCP.Error.transport_error(:connection_refused)

  # Creating client errors
  Hermes.MCP.Error.client_error(:request_timeout, %{elapsed_ms: 30000})

  # Converting from JSON-RPC errors
  Hermes.MCP.Error.from_json_rpc(%{"code" => -32700, "message" => "Parse error"})
  ```
  """

  alias Hermes.MCP.ID
  alias Hermes.MCP.Message

  @type t :: %__MODULE__{code: integer(), reason: atom(), data: map()}

  defstruct [:code, :reason, data: %{}]

  # Standard JSON-RPC error codes
  @parse_error -32_700
  @invalid_request -32_600
  @method_not_found -32_601
  @invalid_params -32_602
  @internal_error -32_603
  @server_error -32_000

  @doc """
  Returns the JSON-RPC error code for parse errors.

  ## Examples

      iex> Hermes.MCP.Error.parse_error_code()
      -32700
  """
  @spec parse_error_code() :: integer()
  def parse_error_code, do: @parse_error

  @doc """
  Returns the JSON-RPC error code for invalid request errors.

  ## Examples

      iex> Hermes.MCP.Error.invalid_request_code()
      -32600
  """
  @spec invalid_request_code() :: integer()
  def invalid_request_code, do: @invalid_request

  @doc """
  Returns the JSON-RPC error code for method not found errors.

  ## Examples

      iex> Hermes.MCP.Error.method_not_found_code()
      -32601
  """
  @spec method_not_found_code() :: integer()
  def method_not_found_code, do: @method_not_found

  @doc """
  Returns the JSON-RPC error code for invalid params errors.

  ## Examples

      iex> Hermes.MCP.Error.invalid_params_code()
      -32602
  """
  @spec invalid_params_code() :: integer()
  def invalid_params_code, do: @invalid_params

  @doc """
  Returns the JSON-RPC error code for internal errors.

  ## Examples

      iex> Hermes.MCP.Error.internal_error_code()
      -32603
  """
  @spec internal_error_code() :: integer()
  def internal_error_code, do: @internal_error

  @doc """
  Creates a parse error.

  Used when the server is unable to parse the JSON received.

  ## Examples

      iex> Hermes.MCP.Error.parse_error()
      %Hermes.MCP.Error{code: -32700, reason: :parse_error, data: %{}}
  """
  @spec parse_error(map()) :: t()
  def parse_error(data \\ %{}) do
    %__MODULE__{code: @parse_error, reason: :parse_error, data: data}
  end

  @doc """
  Creates an invalid request error.

  Used when the JSON sent is not a valid request object.

  ## Examples

      iex> Hermes.MCP.Error.invalid_request()
      %Hermes.MCP.Error{code: -32600, reason: :invalid_request, data: %{}}
  """
  @spec invalid_request(map()) :: t()
  def invalid_request(data \\ %{}) do
    %__MODULE__{code: @invalid_request, reason: :invalid_request, data: data}
  end

  @doc """
  Creates a method not found error.

  Used when the requested method does not exist or is not available.

  ## Examples

      iex> Hermes.MCP.Error.method_not_found(%{method: "unknown_method"})
      %Hermes.MCP.Error{code: -32601, reason: :method_not_found, data: %{method: "unknown_method"}}
  """
  @spec method_not_found(map()) :: t()
  def method_not_found(data \\ %{}) do
    %__MODULE__{code: @method_not_found, reason: :method_not_found, data: data}
  end

  @doc """
  Creates an invalid params error.

  Used when the parameters provided are invalid for the requested method.

  ## Examples

      iex> Hermes.MCP.Error.invalid_params(%{param: "name"})
      %Hermes.MCP.Error{code: -32602, reason: :invalid_params, data: %{param: "name"}}
  """
  @spec invalid_params(map()) :: t()
  def invalid_params(data \\ %{}) do
    %__MODULE__{code: @invalid_params, reason: :invalid_params, data: data}
  end

  @doc """
  Creates an internal error.

  Used when an internal server error occurs.

  ## Examples

      iex> Hermes.MCP.Error.internal_error()
      %Hermes.MCP.Error{code: -32603, reason: :internal_error, data: %{}}
  """
  @spec internal_error(map()) :: t()
  def internal_error(data \\ %{}) do
    %__MODULE__{code: @internal_error, reason: :internal_error, data: data}
  end

  @doc """
  Creates a transport-related error.

  Used for communication/network errors between client and server.

  ## Parameters

    * `reason` - Atom representing the specific transport error
    * `data` - Additional error context or metadata

  ## Examples

      iex> Hermes.MCP.Error.transport_error(:connection_refused)
      %Hermes.MCP.Error{code: -32000, reason: :connection_refused, data: %{type: :transport}}
  """
  @spec transport_error(atom(), map()) :: t()
  def transport_error(reason, data \\ %{}) when is_atom(reason) do
    %__MODULE__{code: @server_error, reason: reason, data: Map.put(data, :type, :transport)}
  end

  @doc """
  Creates a client-related error.

  Used for errors that occur within the client implementation.

  ## Parameters

    * `reason` - Atom representing the specific client error
    * `data` - Additional error context or metadata

  ## Examples

      iex> Hermes.MCP.Error.client_error(:request_timeout, %{elapsed_ms: 30000})
      %Hermes.MCP.Error{code: -32000, reason: :request_timeout, data: %{type: :client, elapsed_ms: 30000}}
  """
  @spec client_error(atom(), map()) :: t()
  def client_error(reason, data \\ %{}) when is_atom(reason) do
    %__MODULE__{code: @server_error, reason: reason, data: Map.put(data, :type, :client)}
  end

  @doc """
  Creates a domain-level error from an MCP server response.

  Used for application-level errors returned as valid JSON-RPC responses with `isError: true`.

  ## Examples

      iex> Hermes.MCP.Error.domain_error(%{"message" => "Resource not found"})
      %Hermes.MCP.Error{code: -32000, reason: :domain_error, data: %{"message" => "Resource not found"}}
  """
  @spec domain_error(map()) :: t()
  def domain_error(data) when is_map(data) do
    %__MODULE__{code: @server_error, reason: :domain_error, data: data}
  end

  @doc """
  Converts from a JSON-RPC error object to a Hermes.MCP.Error struct.

  ## Parameters

    * `error` - A map containing the JSON-RPC error fields

  ## Examples

      iex> Hermes.MCP.Error.from_json_rpc(%{"code" => -32700, "message" => "Parse error"})
      %Hermes.MCP.Error{code: -32700, reason: :parse_error, data: %{message: "Parse error"}}
  """
  @spec from_json_rpc(map()) :: t()
  def from_json_rpc(%{"code" => code} = error) do
    message = Map.get(error, "message", "")
    data = Map.get(error, "data", %{})
    data = if message == "", do: data, else: Map.put(data, :message, message)

    reason = reason_for_code(code)

    %__MODULE__{code: code, reason: reason, data: data}
  end

  @doc """
  Converts from a Hermes.MCP.Error struct to a JSON-RPC error object.

  ## Parameters

    * `error` - `Hermes.MCP.Error.t()`

  ## Examples

      iex> error = %Hermes.MCP.Error{code: -32700, reason: :parse_error, data: %{message: "Parse error"}}
      iex> result = Hermes.MCP.Error.to_json_rpc!(error)
      iex> String.contains?(result, "Parse error")
      true
  """
  @spec to_json_rpc!(t()) :: String.t()
  def to_json_rpc!(%__MODULE__{} = error, id \\ ID.generate_error_id()) do
    {message, data} = Map.pop(error.data, :message)
    payload = %{"code" => error.code, "data" => data, "message" => message || ""}
    {:ok, encoded} = Message.encode_error(%{"error" => payload}, id)
    encoded
  end

  @doc """
  Converts an MCP error to a tuple of the form `{:error, error}`.

  This is useful for returning errors in functions that follow the 
  `{:ok, result} | {:error, reason}` pattern.

  ## Examples

      iex> error = Hermes.MCP.Error.parse_error()
      iex> Hermes.MCP.Error.to_tuple(error)
      {:error, %Hermes.MCP.Error{code: -32700, reason: :parse_error, data: %{}}}
  """
  @spec to_tuple(t()) :: {:error, t()}
  def to_tuple(%__MODULE__{} = error), do: {:error, error}

  # Private helper functions

  # Maps JSON-RPC error codes to Elixir atoms
  defp reason_for_code(@parse_error), do: :parse_error
  defp reason_for_code(@invalid_request), do: :invalid_request
  defp reason_for_code(@method_not_found), do: :method_not_found
  defp reason_for_code(@invalid_params), do: :invalid_params
  defp reason_for_code(@internal_error), do: :internal_error
  defp reason_for_code(_), do: :server_error

  @doc """
  Returns the JSON-RPC error code for a given error reason.

  ## Parameters

    * `reason` - Atom representing the error reason

  ## Examples

      iex> Hermes.MCP.Error.code_for_reason(:parse_error)
      -32700

      iex> Hermes.MCP.Error.code_for_reason(:invalid_request)
      -32600
  """
  @spec code_for_reason(atom()) :: integer()
  def code_for_reason(:parse_error), do: @parse_error
  def code_for_reason(:invalid_request), do: @invalid_request
  def code_for_reason(:method_not_found), do: @method_not_found
  def code_for_reason(:invalid_params), do: @invalid_params
  def code_for_reason(:internal_error), do: @internal_error
end

defimpl Inspect, for: Hermes.MCP.Error do
  def inspect(%{reason: reason, data: data}, _opts) do
    details = if Enum.empty?(data), do: "", else: " #{Kernel.inspect(data, pretty: true)}"
    "#MCP.Error<#{reason}#{details}>"
  end
end
