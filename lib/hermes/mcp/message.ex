defmodule Hermes.MCP.Message do
  @moduledoc """
  Handles encoding and decoding of MCP protocol messages.
  
  This module provides functions for parsing, validating, and creating
  MCP (Model Context Protocol) messages using the JSON-RPC 2.0 format.
  
  ## Message Types
  
  The MCP protocol uses JSON-RPC 2.0 messages in these forms:
  
  1. Requests - Messages sent from client to server that expect a response
  2. Responses - Messages sent from server to client in response to a request
  3. Notifications - Messages sent in either direction that don't expect a response
  4. Errors - Error responses sent from server to client
  
  ## Examples
  
  ```elixir
  # Decode MCP messages from a string
  {:ok, messages} = Hermes.MCP.Message.decode(json_string)
  
  # Encode a request
  {:ok, request_json} = Hermes.MCP.Message.encode_request(%{"method" => "ping", "params" => %{}}, "req_123")
  
  # Encode a notification
  {:ok, notif_json} = Hermes.MCP.Message.encode_notification(%{"method" => "notifications/progress", "params" => %{...}})
  ```
  """
  
  alias Hermes.MCP.Error
  alias Hermes.MCP.Response
  
  @request_methods ~w(initialize ping resources/list resources/read prompts/get prompts/list tools/call tools/list logging/setLevel)
  
  @notification_methods ~w(notifications/initialized notifications/cancelled notifications/progress notifications/message)
  
  @typedoc """
  Represents any MCP protocol message.
  
  MCP protocol uses JSON-RPC 2.0 with several message formats:
  
  1. Request Message:
     ```
     {
       "jsonrpc": "2.0",
       "method": String, // Method name like "ping", "resources/list"
       "params": Object, // Method parameters
       "id": String|Number // Request identifier
     }
     ```
  
  2. Notification Message:
     ```
     {
       "jsonrpc": "2.0",
       "method": String, // Method name like "notifications/progress"
       "params": Object  // Notification parameters
     }
     ```
  
  3. Response Message:
     ```
     {
       "jsonrpc": "2.0",
       "result": Object, // Result value
       "id": String|Number // Request identifier
     }
     ```
  
  4. Error Message:
     ```
     {
       "jsonrpc": "2.0",
       "error": {
         "code": Number,    // Error code
         "message": String, // Error message
         "data": Any        // Optional error data
       },
       "id": String|Number // Request identifier
     }
     ```
  """
  @type message :: map()
  
  # Message type guard functions
  defguard is_request(data) when is_map_key(data, "method") and is_map_key(data, "id")
  defguard is_notification(data) when is_map_key(data, "method") and not is_map_key(data, "id")
  defguard is_response(data) when is_map_key(data, "result") and is_map_key(data, "id")
  defguard is_error(data) when is_map_key(data, "error") and is_map_key(data, "id")
  
  @doc """
  Decodes a JSON string into MCP message(s).
  
  This function handles both single messages and newline-delimited message streams.
  
  ## Parameters
  
    * `data` - The JSON string to decode
  
  ## Returns
  
    * `{:ok, messages}` where messages is a list of parsed MCP messages
    * `{:error, error}` if parsing fails
  
  ## Examples
  
      iex> Hermes.MCP.Message.decode(~s({"jsonrpc":"2.0","result":{},"id":"req_123"}))
      {:ok, [%{"jsonrpc" => "2.0", "result" => %{}, "id" => "req_123"}]}
      
      iex> {:error, error} = Hermes.MCP.Message.decode("invalid")
      iex> error.code
      -32700
      iex> error.reason
      :parse_error
  """
  @spec decode(String.t()) :: {:ok, list(message())} | {:error, Error.t()}
  def decode(data) when is_binary(data) do
    data
    |> String.split("\n", trim: true)
    |> Enum.reduce_while({:ok, []}, &parse_message/2)
    |> then(fn
      {:ok, messages} -> {:ok, Enum.reverse(messages)}
      {:error, reason} -> {:error, reason}
    end)
  end
  
  defp parse_message(line, {:ok, acc}) do
    case JSON.decode(line) do
      {:ok, message} -> 
        {:cont, {:ok, [message | acc]}}
      {:error, _} -> 
        {:halt, {:error, Error.parse_error(%{line: line})}}
    end
  end
  
  @doc """
  Encodes a request message into a JSON-RPC 2.0 compliant string.
  
  ## Parameters
  
    * `request` - A map containing the request method and params
    * `id` - A unique identifier for the request
  
  ## Returns
  
    * `{:ok, json_string}` with the encoded request and a newline
    * `{:error, error}` if encoding fails
  
  ## Examples
  
      iex> {:ok, request} = Hermes.MCP.Message.encode_request(%{"method" => "ping", "params" => %{}}, "req_123")
      iex> request_map = request |> String.trim() |> JSON.decode!()
      iex> request_map["jsonrpc"]
      "2.0"
      iex> request_map["method"]
      "ping"
      iex> request_map["id"]
      "req_123"
  """
  @spec encode_request(map(), String.t() | integer()) :: {:ok, String.t()} | {:error, Error.t()}
  def encode_request(request, id) do
    data = request
    |> Map.put("jsonrpc", "2.0")
    |> Map.put("id", id)
    
    {:ok, JSON.encode!(data) <> "\n"}
  end
  
  @doc """
  Encodes a notification message into a JSON-RPC 2.0 compliant string.
  
  ## Parameters
  
    * `notification` - A map containing the notification method and params
  
  ## Returns
  
    * `{:ok, json_string}` with the encoded notification and a newline
    * `{:error, error}` if encoding fails
  
  ## Examples
  
      iex> {:ok, notif} = Hermes.MCP.Message.encode_notification(%{"method" => "notifications/progress", "params" => %{"progress" => 50}})
      iex> notif_map = notif |> String.trim() |> JSON.decode!()
      iex> notif_map["jsonrpc"]
      "2.0"
      iex> notif_map["method"]
      "notifications/progress"
      iex> notif_map["params"]["progress"]
      50
  """
  @spec encode_notification(map()) :: {:ok, String.t()} | {:error, Error.t()}
  def encode_notification(notification) do
    data = notification
    |> Map.put("jsonrpc", "2.0")
    
    {:ok, JSON.encode!(data) <> "\n"}
  end
  
  @doc """
  Encodes a progress notification message.
  
  ## Parameters
  
    * `progress_token` - The token that was provided in the original request (string or integer)
    * `progress` - The current progress value (number)
    * `total` - Optional total value for the operation (number)
  
  ## Returns
  
    * `{:ok, json_string}` with the encoded notification and a newline
    * `{:error, error}` if encoding fails
  
  ## Examples
  
      iex> {:ok, notif} = Hermes.MCP.Message.encode_progress_notification("token123", 50)
      iex> notif_map = notif |> String.trim() |> JSON.decode!()
      iex> notif_map["method"]
      "notifications/progress"
      iex> notif_map["params"]["progressToken"]
      "token123"
      iex> notif_map["params"]["progress"]
      50
  """
  @spec encode_progress_notification(String.t() | integer(), number(), number() | nil) ::
          {:ok, String.t()} | {:error, Error.t()}
  def encode_progress_notification(progress_token, progress, total \\ nil)
      when (is_binary(progress_token) or is_integer(progress_token)) and is_number(progress) do
    params = %{
      "progressToken" => progress_token,
      "progress" => progress
    }
    
    params = if total, do: Map.put(params, "total", total), else: params
    
    encode_notification(%{
      "method" => "notifications/progress",
      "params" => params
    })
  end
  
  @doc """
  Validates a message according to the MCP protocol.
  
  Performs basic validation to ensure the message conforms to the JSON-RPC 2.0
  structure and has valid MCP-specific fields.
  
  ## Parameters
  
    * `message` - The parsed JSON message to validate
  
  ## Returns
  
    * `:ok` if the message is valid
    * `{:error, error}` if validation fails
  
  ## Examples
  
      iex> Hermes.MCP.Message.validate(%{"jsonrpc" => "2.0", "result" => %{}, "id" => "req_123"})
      :ok
      
      iex> {:error, error} = Hermes.MCP.Message.validate(%{"jsonrpc" => "1.0", "result" => %{}, "id" => "req_123"})
      iex> error.reason
      :invalid_request
  """
  @spec validate(map()) :: :ok | {:error, Error.t()}
  def validate(message) when not is_map(message) do
    {:error, Error.invalid_request(%{reason: "not_a_map"})}
  end
  
  def validate(message) when is_map(message) and not is_map_key(message, "jsonrpc") do
    {:error, Error.invalid_request(%{reason: "missing_jsonrpc_field"})}
  end
  
  def validate(%{"jsonrpc" => version}) when version != "2.0" do
    {:error, Error.invalid_request(%{reason: "invalid_jsonrpc_version"})}
  end
  
  def validate(message) when is_request(message) do
    validate_request(message)
  end
  
  def validate(message) when is_notification(message) do
    validate_notification(message)
  end
  
  def validate(message) when is_response(message) do
    :ok
  end
  
  def validate(message) when is_error(message) do
    :ok
  end
  
  def validate(message) when is_map(message) do
    {:error, Error.invalid_request(%{reason: "invalid_message_structure"})}
  end
  
  defp validate_request(%{"method" => method} = message) do
    with :ok <- validate_method(method, @request_methods),
         :ok <- validate_id(message["id"]) do
      :ok
    end
  end
  
  defp validate_notification(%{"method" => method}) do
    validate_method(method, @notification_methods)
  end
  
  defp validate_method(method, allowed_methods) do
    if method in allowed_methods do
      :ok
    else
      {:error, Error.method_not_found(%{method: method})}
    end
  end
  
  defp validate_id(id) when is_binary(id) or is_integer(id), do: :ok
  defp validate_id(_), do: {:error, Error.invalid_request(%{reason: "invalid_id_type"})}
  
  @doc """
  Converts a message to the appropriate domain object based on its type.
  
  ## Parameters
  
    * `message` - A parsed JSON-RPC 2.0 message
  
  ## Returns
  
    * `{:ok, domain_object}` with the appropriate type (Response or Error)
    * `{:error, error}` if conversion fails
  
  ## Examples
  
      iex> resp = %{"jsonrpc" => "2.0", "result" => %{"data" => "value"}, "id" => "req_123"}
      iex> {:ok, response} = Hermes.MCP.Message.to_domain(resp)
      iex> response.__struct__
      Hermes.MCP.Response
      
      iex> err = %{"jsonrpc" => "2.0", "error" => %{"code" => -32700, "message" => "Parse error"}, "id" => "req_123"}
      iex> {:ok, error} = Hermes.MCP.Message.to_domain(err)
      iex> error.__struct__
      Hermes.MCP.Error
  """
  @spec to_domain(message()) :: 
    {:ok, Response.t() | Error.t()} | 
    {:error, Error.t()}
  def to_domain(message) when is_response(message) do
    {:ok, Response.from_json_rpc(message)}
  end
  
  def to_domain(message) when is_error(message) do
    {:ok, Error.from_json_rpc(message["error"])}
  end
  
  def to_domain(_message) do
    {:error, Error.invalid_request(%{reason: "cannot_convert_to_domain"})}
  end
end