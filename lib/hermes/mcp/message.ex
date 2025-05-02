defmodule Hermes.MCP.Message do
  @moduledoc """
  Handles parsing and validation of MCP (Model Context Protocol) messages using the Peri library.

  This module provides functions to parse and validate MCP messages based on the Model Context Protocol schema
  """

  import Peri

  # MCP message schemas

  @request_methods ~w(initialize ping resources/list resources/read prompts/get prompts/list tools/call tools/list logging/setLevel completion/complete)

  @init_params_schema %{
    "protocolVersion" => {:required, :string},
    "capabilities" => {:required, :map},
    "clientInfo" => %{
      "name" => {:required, :string},
      "version" => {:required, :string}
    }
  }

  @ping_params_schema :map

  @resources_list_params_schema %{
    "cursor" => :string
  }

  @resources_read_params_schema %{
    "uri" => {:required, :string}
  }

  @prompts_list_params_schema %{
    "cursor" => :string
  }

  @prompts_get_params_schema %{
    "name" => {:required, :string},
    "arguments" => :map
  }

  @tools_list_params_schema %{
    "cursor" => :string
  }

  @tools_call_params_schema %{
    "name" => {:required, :string},
    "arguments" => :map
  }

  @log_levels ~w(debug info notice warning error critical alert emergency)

  @set_log_level_params_schema %{
    "level" => {:required, {:enum, @log_levels}}
  }


  @completion_prompt_ref_schema %{
    "type" => {:required, {:string, {:eq, "ref/prompt"}}},
    "name" => {:required, :string}
  }

  @completion_resource_ref_schema %{
    "type" => {:required, {:string, {:eq, "ref/resource"}}},
    "uri" => {:required, :string}
  }

  @completion_argument_schema %{
    "name" => {:required, :string},
    "value" => {:required, :string}
  }

  @completion_complete_params_schema %{
    "ref" => {:required, {:oneof, [@completion_prompt_ref_schema, @completion_resource_ref_schema]}},
    "argument" => {:required, @completion_argument_schema}
  }

  defschema :request_schema, %{
    "jsonrpc" => {:required, {:string, {:eq, "2.0"}}},
    "method" => {:required, {:enum, @request_methods}},
    "params" => {:dependent, &parse_request_params_by_method/1},
    "id" => {:required, {:either, {:string, :integer}}}
  }

  defp parse_request_params_by_method(%{"method" => "initialize"}), do: {:ok, @init_params_schema}
  defp parse_request_params_by_method(%{"method" => "ping"}), do: {:ok, @ping_params_schema}

  defp parse_request_params_by_method(%{"method" => "resources/list"}), do: {:ok, @resources_list_params_schema}

  defp parse_request_params_by_method(%{"method" => "resources/read"}), do: {:ok, @resources_read_params_schema}

  defp parse_request_params_by_method(%{"method" => "prompts/list"}), do: {:ok, @prompts_list_params_schema}

  defp parse_request_params_by_method(%{"method" => "prompts/get"}), do: {:ok, @prompts_get_params_schema}

  defp parse_request_params_by_method(%{"method" => "tools/list"}), do: {:ok, @tools_list_params_schema}

  defp parse_request_params_by_method(%{"method" => "tools/call"}), do: {:ok, @tools_call_params_schema}

  defp parse_request_params_by_method(%{"method" => "logging/setLevel"}), do: {:ok, @set_log_level_params_schema}

  defp parse_request_params_by_method(%{"method" => "completion/complete"}), do: {:ok, @completion_complete_params_schema}

  defp parse_request_params_by_method(_), do: {:ok, :map}

  @init_noti_params_schema :map
  @cancel_noti_params_schema %{
    "requestId" => {:required, {:either, {:string, :integer}}},
    "reason" => :string
  }
  @progress_notif_params_schema %{
    "progressToken" => {:required, {:either, {:string, :integer}}},
    "progress" => {:required, {:either, {:float, :integer}}},
    "total" => {:either, {:float, :integer}}
  }
  @logging_message_notif_params_schema %{
    "level" => {:required, {:enum, @log_levels}},
    "data" => {:required, :any},
    "logger" => :string
  }

  defschema :notification_schema, %{
    "jsonrpc" => {:required, {:string, {:eq, "2.0"}}},
    "method" =>
      {:required,
       {:enum, ~w(notifications/initialized notifications/cancelled notifications/progress notifications/message)}},
    "params" => {:dependent, &parse_notification_params_by_method/1}
  }

  defp parse_notification_params_by_method(%{"method" => "notifications/initialized"}),
    do: {:ok, @init_noti_params_schema}

  defp parse_notification_params_by_method(%{"method" => "notifications/cancelled"}),
    do: {:ok, @cancel_noti_params_schema}

  defp parse_notification_params_by_method(%{"method" => "notifications/progress"}),
    do: {:ok, @progress_notif_params_schema}

  defp parse_notification_params_by_method(%{"method" => "notifications/message"}),
    do: {:ok, @logging_message_notif_params_schema}

  defp parse_notification_params_by_method(_), do: {:ok, :map}

  defschema :response_schema, %{
    "jsonrpc" => {:required, {:string, {:eq, "2.0"}}},
    "result" => {:required, :any},
    "id" => {:required, {:either, {:string, :integer}}}
  }

  defschema :error_schema, %{
    "jsonrpc" => {:required, {:string, {:eq, "2.0"}}},
    "error" => %{
      "code" => {:required, :integer},
      "message" => {:required, :string},
      "data" => :any
    },
    "id" => {:required, {:either, {:string, :integer}}}
  }

  defschema :mcp_message_schema,
            {:oneof,
             [
               get_schema(:request_schema),
               get_schema(:notification_schema),
               get_schema(:response_schema),
               get_schema(:error_schema)
             ]}

  @doc """
  Determines if a JSON-RPC message is a request.
  """
  defguard is_request(data) when is_map_key(data, "method") and is_map_key(data, "id")

  @doc """
  Determines if a JSON-RPC message is a notification.
  """
  defguard is_notification(data) when is_map_key(data, "method") and not is_map_key(data, "id")

  @doc """
  Determines if a JSON-RPC message is a response.
  """
  defguard is_response(data) when is_map_key(data, "result") and is_map_key(data, "id")

  @doc """
  Determines if a JSON-RPC message is an error.
  """
  defguard is_error(data) when is_map_key(data, "error") and is_map_key(data, "id")

  @doc """
  Decodes raw data (possibly containing multiple messages) into JSON-RPC messages.

  Returns either:
  - `{:ok, messages}` where messages is a list of parsed JSON-RPC messages
  - `{:error, reason}` if parsing fails
  """
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
    with {:ok, message} <- JSON.decode(line),
         {:ok, message} <- validate_message(message) do
      {:cont, {:ok, [message | acc]}}
    else
      err -> {:halt, err}
    end
  end

  @doc """
  Validates a decoded JSON message to ensure it complies with the MCP schema.
  """
  def validate_message(message) when is_map(message) do
    with {:error, _} <- mcp_message_schema(message) do
      {:error, :invalid_message}
    end
  end

  @doc """
  Encodes a request message to a JSON-RPC 2.0 compliant string.

  Returns the encoded string with a newline character appended.
  """
  def encode_request(request, id) do
    schema = get_schema(:request_schema)

    request
    |> Map.put("jsonrpc", "2.0")
    |> Map.put("id", id)
    |> encode_message(schema)
  end

  @doc """
  Encodes a notification message to a JSON-RPC 2.0 compliant string.

  Returns the encoded string with a newline character appended.
  """
  def encode_notification(notification) do
    schema = get_schema(:notification_schema)

    notification
    |> Map.put("jsonrpc", "2.0")
    |> encode_message(schema)
  end

  @doc """
  Encodes a progress notification message to a JSON-RPC 2.0 compliant string.

  ## Parameters

    * `progress_token` - The token that was provided in the original request (string or integer)
    * `progress` - The current progress value (number)
    * `total` - Optional total value for the operation (number)

  Returns the encoded string with a newline character appended.
  """
  @spec encode_progress_notification(String.t() | integer(), number(), number() | nil) ::
          {:ok, String.t()} | {:error, term()}
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
  Encodes a response message to a JSON-RPC 2.0 compliant string.

  Returns the encoded string with a newline character appended.
  """
  def encode_response(response, id) do
    schema = get_schema(:response_schema)

    response
    |> Map.put("jsonrpc", "2.0")
    |> Map.put("id", id)
    |> encode_message(schema)
  end

  @doc """
  Encodes an error message to a JSON-RPC 2.0 compliant string.

  Returns the encoded string with a newline character appended.
  """
  def encode_error(response, id) do
    schema = get_schema(:error_schema)

    response
    |> Map.put("jsonrpc", "2.0")
    |> Map.put("id", id)
    |> encode_message(schema)
  end

  defp encode_message(data, schema) do
    encoder = {schema, {:transform, fn data -> JSON.encode!(data) <> "\n" end}}
    Peri.validate(encoder, data)
  end

  @doc """
  Encodes a log message notification to be sent to the client.

  ## Parameters

    * `level` - The log level (debug, info, notice, warning, error, critical, alert, emergency)
    * `data` - The data to be logged (any JSON-serializable value)
    * `logger` - Optional name of the logger issuing the message

  Returns the encoded notification string with a newline character appended.
  """
  @spec encode_log_message(String.t(), term(), String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def encode_log_message(level, data, logger \\ nil) when level in @log_levels do
    params = maybe_add_logger(%{"level" => level, "data" => data}, logger)

    encode_notification(%{
      "method" => "notifications/message",
      "params" => params
    })
  end

  defp maybe_add_logger(params, nil), do: params
  defp maybe_add_logger(params, logger) when is_binary(logger), do: Map.put(params, "logger", logger)
end
