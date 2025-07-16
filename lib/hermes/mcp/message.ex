defmodule Hermes.MCP.Message do
  @moduledoc """
  Handles parsing and validation of MCP (Model Context Protocol) messages using the Peri library.

  This module provides functions to parse and validate MCP messages based on the Model Context Protocol schema
  """

  import Peri

  # MCP message schemas

  @request_methods ~w(initialize ping resources/list resources/read prompts/get prompts/list tools/call tools/list logging/setLevel completion/complete roots/list sampling/createMessage)

  @init_params_schema %{
    "protocolVersion" => {:required, :string},
    "capabilities" => {:map, {:default, %{}}},
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

  @progress_params %{
    "_meta" => %{
      "progressToken" => {:either, {:string, :integer}}
    }
  }

  @text_content_schema %{
    "type" => {:required, {:literal, "text"}},
    "text" => {:required, :string}
  }

  @image_content_schema %{
    "type" => {:required, {:literal, "image"}},
    "data" => {:required, :string},
    "mimeType" => {:required, :string}
  }

  @audio_content_schema %{
    "type" => {:required, {:literal, "audio"}},
    "data" => {:required, :string},
    "mimeType" => {:required, :string}
  }

  @message_schema %{
    "role" => {:required, {:enum, ~w(user assistant system)}},
    "content" => {:required, {:oneof, [@text_content_schema, @image_content_schema, @audio_content_schema]}}
  }

  @model_preferences_schema %{
    "intelligencePriority" => :float,
    "speedPriority" => :float,
    "costPriority" => :float,
    "hints" => {:list, %{"name" => :string}}
  }

  @sampling_create_params %{
    "messages" => {:list, @message_schema},
    "modelPreferences" => @model_preferences_schema,
    "systemPrompt" => :string,
    "maxTokens" => :integer
  }

  defschema(:request_schema, %{
    "jsonrpc" => {:required, {:string, {:eq, "2.0"}}},
    "method" => {:required, {:enum, @request_methods}},
    "params" => {:dependent, &params_with_progress_token/1},
    "id" => {:required, {:either, {:string, :integer}}}
  })

  defp params_with_progress_token(attrs) do
    with {:ok, %{} = schema} <- parse_request_params_by_method(attrs) do
      schema =
        if get_in(attrs, ["params", "_meta"]),
          do: Map.merge(schema, @progress_params),
          else: schema

      {:ok, schema}
    end
  end

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

  defp parse_request_params_by_method(%{"method" => "sampling/createMessage"}), do: {:ok, @sampling_create_params}

  defp parse_request_params_by_method(%{"method" => "roots/list"}), do: {:ok, :map}
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

  # 2025-03-26 progress notification schema with message field
  @progress_notif_params_schema_2025 %{
    "progressToken" => {:required, {:either, {:string, :integer}}},
    "progress" => {:required, {:either, {:float, :integer}}},
    "total" => {:either, {:float, :integer}},
    "message" => :string
  }
  @logging_message_notif_params_schema %{
    "level" => {:required, {:enum, @log_levels}},
    "data" => {:required, :any},
    "logger" => :string
  }

  defschema(:notification_schema, %{
    "jsonrpc" => {:required, {:string, {:eq, "2.0"}}},
    "method" =>
      {:required,
       {:enum,
        ~w(notifications/initialized notifications/cancelled notifications/progress notifications/message notifications/roots/list_changed)}},
    "params" => {:dependent, &parse_notification_params_by_method/1}
  })

  defp parse_notification_params_by_method(%{"method" => "notifications/initialized"}),
    do: {:ok, @init_noti_params_schema}

  defp parse_notification_params_by_method(%{"method" => "notifications/cancelled"}),
    do: {:ok, @cancel_noti_params_schema}

  defp parse_notification_params_by_method(%{"method" => "notifications/progress"}),
    do: {:ok, @progress_notif_params_schema}

  defp parse_notification_params_by_method(%{"method" => "notifications/message"}),
    do: {:ok, @logging_message_notif_params_schema}

  defp parse_notification_params_by_method(%{"method" => "notifications/roots/list_changed"}), do: {:ok, :map}

  defp parse_notification_params_by_method(_), do: {:ok, :map}

  defschema(:response_schema, %{
    "jsonrpc" => {:required, {:string, {:eq, "2.0"}}},
    "result" => {:required, :any},
    "id" => {:required, {:either, {:string, :integer}}}
  })

  defschema(:sampling_result_schema, %{
    "role" => {:required, {:literal, "assistant"}},
    "content" => {:required, {:oneof, [@text_content_schema, @image_content_schema, @audio_content_schema]}},
    "model" => {:required, :string},
    "stopReason" => {:string, {:default, "endTurn"}}
  })

  defschema(
    :sampling_response_schema,
    Map.put(
      get_schema(:response_schema),
      "result",
      get_schema(:sampling_result_schema)
    )
  )

  defschema(:error_schema, %{
    "jsonrpc" => {:required, {:string, {:eq, "2.0"}}},
    "error" => %{
      "code" => {:required, :integer},
      "message" => {:required, :string},
      "data" => :any
    },
    "id" => {:required, {:either, {:string, :integer}}}
  })

  defschema(
    :mcp_message_schema,
    {:oneof,
     [
       get_schema(:request_schema),
       get_schema(:notification_schema),
       get_schema(:response_schema),
       get_schema(:error_schema)
     ]}
  )

  # generic guards

  @doc """
  Guard to determine if a JSON-RPC message is a request.

  A message is considered a request if it contains both "method" and "id" fields.

  ## Examples

      iex> message = %{"jsonrpc" => "2.0", "method" => "ping", "id" => 1}
      iex> is_request(message)
      true

      iex> notification = %{"jsonrpc" => "2.0", "method" => "notification"}
      iex> is_request(notification)
      false
  """
  defguard is_request(data)
           when is_map_key(data, "method") and is_map_key(data, "id")

  @doc """
  Guard to determine if a JSON-RPC message is a notification.

  A message is considered a notification if it contains a "method" field but no "id" field.

  ## Examples

      iex> message = %{"jsonrpc" => "2.0", "method" => "notification"}
      iex> is_notification(message)
      true

      iex> request = %{"jsonrpc" => "2.0", "method" => "ping", "id" => 1}
      iex> is_notification(request)
      false
  """
  defguard is_notification(data)
           when is_map_key(data, "method") and not is_map_key(data, "id")

  @doc """
  Guard to determine if a JSON-RPC message is a response.

  A message is considered a response if it contains both "result" and "id" fields.

  ## Examples

      iex> message = %{"jsonrpc" => "2.0", "result" => %{}, "id" => 1}
      iex> is_response(message)
      true
  """
  defguard is_response(data)
           when is_map_key(data, "result") and is_map_key(data, "id")

  @doc """
  Guard to determine if a JSON-RPC message is an error.

  A message is considered an error if it contains both "error" and "id" fields.

  ## Examples

      iex> message = %{"jsonrpc" => "2.0", "error" => %{"code" => -32600}, "id" => 1}
      iex> is_error(message)
      true
  """
  defguard is_error(data) when is_map_key(data, "error") and is_map_key(data, "id")

  # request guards

  @doc """
  Guard to check if a request is a ping request.

  ## Examples

      iex> message = %{"jsonrpc" => "2.0", "method" => "ping", "id" => 1}
      iex> is_ping(message)
      true
  """
  defguard is_ping(data)
           when is_request(data) and :erlang.map_get("method", data) == "ping"

  @doc """
  Guard to check if a request is an initialize request.

  ## Examples

      iex> message = %{"jsonrpc" => "2.0", "method" => "initialize", "id" => 1, "params" => %{}}
      iex> is_initialize(message)
      true
  """
  defguard is_initialize(data)
           when is_request(data) and :erlang.map_get("method", data) == "initialize"

  @doc """
  Guard to check if a message is part of the initialization lifecycle.

  This includes both the initialize request and the notifications/initialized notification.

  ## Examples

      iex> init_request = %{"jsonrpc" => "2.0", "method" => "initialize", "id" => 1, "params" => %{}}
      iex> is_initialize_lifecycle(init_request)
      true

      iex> init_notification = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}
      iex> is_initialize_lifecycle(init_notification)
      true

      iex> other_message = %{"jsonrpc" => "2.0", "method" => "tools/list", "id" => 2}
      iex> is_initialize_lifecycle(other_message)
      false
  """
  defguard is_initialize_lifecycle(data)
           when (is_request(data) and :erlang.map_get("method", data) == "initialize") or
                  (is_notification(data) and
                     :erlang.map_get("method", data) == "notifications/initialized")

  @doc """
  Decodes raw data (possibly containing multiple messages) into JSON-RPC messages.

  Returns either:
  - `{:ok, messages}` where messages is a list of parsed JSON-RPC messages
  - `{:error, reason}` if parsing fails
  """
  def decode(data) when is_binary(data) do
    data
    |> String.split("\n", trim: true)
    |> decode_lines()
  end

  defp decode_lines(lines) do
    lines
    |> Enum.flat_map(&decode_line/1)
    |> validate_all_messages()
  end

  defp decode_line(line) do
    case JSON.decode(line) do
      {:ok, message} when is_map(message) -> [message]
      {:ok, _} -> [:invalid]
      {:error, _} -> [:invalid]
    end
  end

  defp validate_all_messages(messages) do
    messages
    |> Enum.reduce_while({:ok, []}, fn
      :invalid, _acc ->
        {:halt, {:error, :invalid_message}}

      message, {:ok, acc} ->
        case validate_message(message) do
          {:ok, validated} -> {:cont, {:ok, [validated | acc]}}
          error -> {:halt, error}
        end
    end)
    |> case do
      {:ok, validated} -> {:ok, Enum.reverse(validated)}
      error -> error
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
    encode_request(request, id, get_schema(:request_schema))
  end

  @doc """
  Encodes a request message using a custom schema.

  ## Parameters

    * `request` - The request map containing method and params
    * `id` - The request ID
    * `schema` - The Peri schema to use for validation

  Returns the encoded string with a newline character appended.
  """
  def encode_request(request, id, schema) do
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
    encode_notification(notification, get_schema(:notification_schema))
  end

  @doc """
  Encodes a notification message using a custom schema.

  ## Parameters

    * `notification` - The notification map containing method and params
    * `schema` - The Peri schema to use for validation

  Returns the encoded string with a newline character appended.
  """
  def encode_notification(notification, schema) do
    notification
    |> Map.put("jsonrpc", "2.0")
    |> encode_message(schema)
  end

  @doc """
  Encodes a progress notification message to a JSON-RPC 2.0 compliant string.

  ## Parameters

    * `params` - Map containing progress parameters:
      * `"progressToken"` - The token that was provided in the original request (string or integer)
      * `"progress"` - The current progress value (number) 
      * `"total"` - Optional total value for the operation (number)
      * `"message"` - Optional descriptive message (string, for 2025-03-26)
    * `params_schema` - Optional Peri schema for params validation (defaults to @progress_notif_params_schema)

  Returns the encoded string with a newline character appended.
  """
  @spec encode_progress_notification(map(), term() | nil) ::
          {:ok, String.t()} | {:error, term()}
  def encode_progress_notification(params, params_schema \\ @progress_notif_params_schema) when is_map(params) do
    # Validate params against the provided schema
    case Peri.validate(params_schema, params) do
      {:ok, validated_params} ->
        encode_notification(%{
          "method" => "notifications/progress",
          "params" => validated_params
        })

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Legacy function for progress notifications with individual parameters.

  **Deprecated**: Prefer using `encode_progress_notification/2` with a params map.

  This function will be removed in a future release. Update your code to use the newer function:

      encode_progress_notification(%{
        "progressToken" => progress_token,
        "progress" => progress,
        "total" => total
      })
  """
  @deprecated "Use encode_progress_notification/2 with a params map. This function will be removed in a future release."
  @spec encode_progress_notification(
          String.t() | integer(),
          number(),
          number() | nil
        ) ::
          {:ok, String.t()} | {:error, term()}
  def encode_progress_notification(progress_token, progress, total)
      when (is_binary(progress_token) or is_integer(progress_token)) and is_number(progress) do
    params = %{
      "progressToken" => progress_token,
      "progress" => progress
    }

    params = if total, do: Map.put(params, "total", total), else: params
    encode_progress_notification(params)
  end

  @doc """
  Encodes a response message to a JSON-RPC 2.0 compliant string.

  Returns the encoded string with a newline character appended.
  """
  def encode_response(response, id) do
    encode_response(response, id, get_schema(:response_schema))
  end

  def encode_sampling_response(response, id) do
    encode_response(response, id, get_schema(:sampling_response_schema))
  end

  @doc """
  Encodes a response message using a custom schema.

  ## Parameters

    * `response` - The response map containing result
    * `id` - The response ID
    * `schema` - The Peri schema to use for validation

  Returns the encoded string with a newline character appended.
  """
  def encode_response(response, id, schema) do
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
  @spec encode_log_message(String.t(), term(), String.t() | nil) ::
          {:ok, String.t()} | {:error, term()}
  def encode_log_message(level, data, logger \\ nil) when level in @log_levels do
    params = maybe_add_logger(%{"level" => level, "data" => data}, logger)

    encode_notification(%{
      "method" => "notifications/message",
      "params" => params
    })
  end

  defp maybe_add_logger(params, nil), do: params

  defp maybe_add_logger(params, logger) when is_binary(logger), do: Map.put(params, "logger", logger)

  @doc """
  Returns the progress notification parameters schema for 2025-03-26 (with message field).
  """
  def progress_params_schema_2025, do: @progress_notif_params_schema_2025

  @doc """
  Returns the standard progress notification parameters schema for 2024-11-05.
  """
  def progress_params_schema, do: @progress_notif_params_schema

  @doc """
  Builds a response message map without encoding to JSON.
    
  ## Examples

      iex> Message.build_response(%{"value" => 42}, "req_123")
      %{"jsonrpc" => "2.0", "result" => %{"value" => 42}, "id" => "req_123"}
  """
  @spec build_response(map(), String.t() | integer()) :: map()
  def build_response(result, id) do
    %{"jsonrpc" => "2.0", "result" => result, "id" => id}
  end

  @doc """
  Builds an error message map without encoding to JSON.
    
  ## Examples

      iex> Message.build_error(%{"code" => -32600, "message" => "Invalid Request"}, "req_123")
      %{"jsonrpc" => "2.0", "error" => %{"code" => -32600, "message" => "Invalid Request"}, "id" => "req_123"}
  """
  @spec build_error(map(), String.t() | integer() | nil) :: map()
  def build_error(error, id) do
    %{"jsonrpc" => "2.0", "error" => error, "id" => id}
  end

  @doc """
  Builds a notification message map without encoding to JSON.

  ## Examples

      iex> Message.build_notification("notifications/message", %{"level" => "info", "data" => "test"})
      %{"jsonrpc" => "2.0", "method" => "notifications/message", "params" => %{"level" => "info", "data" => "test"}}
  """
  @spec build_notification(String.t(), map()) :: map()
  def build_notification(method, params) do
    %{"jsonrpc" => "2.0", "method" => method, "params" => params}
  end
end
