defmodule Hermes.Message do
  @moduledoc """
  Handles parsing and validation of MCP (Model Context Protocol) messages using the Peri library.

  This module provides functions to parse and validate MCP messages based on the Model Context Protocol schema
  """

  import Peri

  # MCP message schemas

  @request_methods ~w(initialize ping resources/list resources/read prompts/get prompts/list tools/call tools/list)

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

  defschema :request_schema, %{
    "jsonrpc" => {:required, {:string, {:eq, "2.0"}}},
    "method" => {:required, {:enum, @request_methods}},
    "params" => {:dependent, &parse_request_params_by_method/1},
    "id" => {:required, {:either, {:string, :integer}}}
  }

  defp parse_request_params_by_method(%{"method" => "initialize"}), do: {:ok, @init_params_schema}
  defp parse_request_params_by_method(%{"method" => "ping"}), do: {:ok, @ping_params_schema}

  defp parse_request_params_by_method(%{"method" => "resources/list"}),
    do: {:ok, @resources_list_params_schema}

  defp parse_request_params_by_method(%{"method" => "resources/read"}),
    do: {:ok, @resources_read_params_schema}

  defp parse_request_params_by_method(%{"method" => "prompts/list"}),
    do: {:ok, @prompts_list_params_schema}

  defp parse_request_params_by_method(%{"method" => "prompts/get"}),
    do: {:ok, @prompts_get_params_schema}

  defp parse_request_params_by_method(%{"method" => "tools/list"}),
    do: {:ok, @tools_list_params_schema}

  defp parse_request_params_by_method(%{"method" => "tools/call"}),
    do: {:ok, @tools_call_params_schema}

  defp parse_request_params_by_method(_), do: {:ok, :map}

  @init_noti_params_schema :map
  @cancel_noti_params_schema %{
    "requestId" => {:required, {:either, {:string, :integer}}},
    "reason" => :string
  }
  @progress_notif_params_schema %{
    "progressToken" => {:required, {:either, {:string, :integer}}},
    "progress" => {:required, :float},
    "total" => :float
  }

  defschema :notification_schema, %{
    "jsonrpc" => {:required, {:string, {:eq, "2.0"}}},
    "method" =>
      {:required,
       {:enum, ~w(notifications/initialized notifications/cancelled notifications/progress)}},
    "params" => {:dependent, &parse_notification_params_by_method/1}
  }

  defp parse_notification_params_by_method(%{"method" => "notifications/initialized"}),
    do: {:ok, @init_noti_params_schema}

  defp parse_notification_params_by_method(%{"method" => "notifications/cancelled"}),
    do: {:ok, @cancel_noti_params_schema}

  defp parse_notification_params_by_method(%{"method" => "notifications/progress"}),
    do: {:ok, @progress_notif_params_schema}

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

  defp encode_message(data, schema) do
    encoder = {schema, {:transform, fn data -> JSON.encode!(data) <> "\n" end}}
    Peri.validate(encoder, data)
  end
end
