defmodule Hermes.MCP.Response do
  @moduledoc """
  Represents successful responses in the MCP protocol.

  This module provides a wrapper around JSON-RPC responses, handling
  domain-specific error semantics for MCP's "isError" field in results.

  ## Response Structure

  Each response includes:
  - `result`: The response data from the server
  - `id`: The request ID this response is associated with
  - `is_error`: Boolean flag indicating if this is a domain-level error

  ## Domain vs. Protocol Errors

  The MCP protocol distinguishes between two types of errors:

  1. Protocol errors: Standard JSON-RPC errors with error codes (handled by `Hermes.MCP.Error`)
  2. Domain errors: Valid responses that indicate application-level errors with `isError: true`

  This module specifically handles domain errors, which are successful at the protocol level
  but indicate failures at the application level.

  ## Examples

  ```elixir
  # Create from a JSON-RPC response
  response = Hermes.MCP.Response.from_json_rpc(%{"result" => %{"data" => "value"}, "id" => "req_123"})

  # Check if the response is successful or has a domain error
  if Hermes.MCP.Response.success?(response) do
    # Handle success
  else
    # Handle domain error
  end

  # Unwrap the response to get the result or error
  case Hermes.MCP.Response.unwrap(response) do
    {:ok, result} -> # Handle success
    {:error, error} -> # Handle domain error
  end
  ```
  """

  @type t :: %__MODULE__{
          result: map(),
          id: String.t(),
          is_error: boolean(),
          method: String.t() | nil
        }

  defstruct [:result, :id, :method, is_error: false]

  @doc """
  Creates a Response struct from a JSON-RPC response.

  Automatically detects domain errors by checking for the "isError" field.

  ## Parameters

    * `response` - A map containing the JSON-RPC response

  ## Examples

      iex> Hermes.MCP.Response.from_json_rpc(%{"result" => %{}, "id" => "req_123"})
      %Hermes.MCP.Response{result: %{}, id: "req_123", is_error: false}
      
      iex> Hermes.MCP.Response.from_json_rpc(%{"result" => %{"isError" => true}, "id" => "req_123"})
      %Hermes.MCP.Response{result: %{"isError" => true}, id: "req_123", is_error: true}
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
  Unwraps the response, returning the raw result.

  Returns the raw result data regardless of whether it represents
  a success or domain error.

  ## Examples

      iex> response = Hermes.MCP.Response.from_json_rpc(%{"result" => %{"data" => "value"}, "id" => "req_123"})
      iex> Hermes.MCP.Response.unwrap(response)
      %{"data" => "value"}
      
      iex> error_response = Hermes.MCP.Response.from_json_rpc(%{"result" => %{"isError" => true, "reason" => "not_found"}, "id" => "req_123"})
      iex> Hermes.MCP.Response.unwrap(error_response)
      %{"isError" => true, "reason" => "not_found"}
  """
  @spec unwrap(t()) :: map()
  def unwrap(%__MODULE__{result: result}), do: result

  @doc """
  Checks if the response is successful (no domain error).

  ## Examples

      iex> response = Hermes.MCP.Response.from_json_rpc(%{"result" => %{"data" => "value"}, "id" => "req_123"})
      iex> Hermes.MCP.Response.success?(response)
      true
      
      iex> error_response = Hermes.MCP.Response.from_json_rpc(%{"result" => %{"isError" => true}, "id" => "req_123"})
      iex> Hermes.MCP.Response.success?(error_response)
      false
  """
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{is_error: false}), do: true
  def success?(_), do: false

  @doc """
  Checks if the response has a domain error.

  ## Examples

      iex> response = Hermes.MCP.Response.from_json_rpc(%{"result" => %{"data" => "value"}, "id" => "req_123"})
      iex> Hermes.MCP.Response.error?(response)
      false
      
      iex> error_response = Hermes.MCP.Response.from_json_rpc(%{"result" => %{"isError" => true}, "id" => "req_123"})
      iex> Hermes.MCP.Response.error?(error_response)
      true
  """
  @spec error?(t()) :: boolean()
  def error?(%__MODULE__{is_error: true}), do: true
  def error?(_), do: false

  @doc """
  Gets the result data from the response.

  This function returns the raw result regardless of whether it represents
  a success or domain error.

  ## Examples

      iex> response = Hermes.MCP.Response.from_json_rpc(%{"result" => %{"data" => "value"}, "id" => "req_123"})
      iex> Hermes.MCP.Response.get_result(response)
      %{"data" => "value"}
  """
  @spec get_result(t()) :: map()
  def get_result(%__MODULE__{result: result}), do: result

  @doc """
  Gets the request ID associated with this response.

  ## Examples

      iex> response = Hermes.MCP.Response.from_json_rpc(%{"result" => %{}, "id" => "req_123"})
      iex> Hermes.MCP.Response.get_id(response)
      "req_123"
  """
  @spec get_id(t()) :: String.t()
  def get_id(%__MODULE__{id: id}), do: id
end
