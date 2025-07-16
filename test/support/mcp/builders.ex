defmodule Hermes.MCP.Builders do
  @moduledoc false

  alias Hermes.MCP.ID
  alias Hermes.MCP.Message

  require Message

  def init_request(protocol_version, client_info, capabilities \\ %{}) do
    %{
      "jsonrpc" => "2.0",
      "id" => ID.generate_request_id(),
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => protocol_version,
        "clientInfo" => client_info,
        "capabilities" => capabilities
      }
    }
  end

  def init_response(request_id, protocol_version, server_info, capabilities \\ %{}) do
    %{
      "jsonrpc" => "2.0",
      "id" => request_id,
      "result" => %{
        "protocolVersion" => protocol_version,
        "serverInfo" => server_info,
        "capabilities" => capabilities
      }
    }
  end

  def init_response(request_id, capabilities) when is_binary(request_id) and is_map(capabilities) do
    init_response(
      request_id,
      "2025-03-26",
      %{"name" => "TestServer", "version" => "1.0.0"},
      capabilities
    )
  end

  def build_request(method, params \\ %{}, id \\ ID.generate_request_id()) do
    %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}
  end

  def build_response(result, request_id) do
    %{"jsonrpc" => "2.0", "id" => request_id, "result" => result}
  end

  def build_error(code, message, request_id, data \\ nil) do
    error = %{"code" => code, "message" => message}
    error = if data, do: Map.put(error, "data", data), else: error

    %{"jsonrpc" => "2.0", "id" => request_id, "error" => error}
  end

  def build_notification(method, params \\ %{}) do
    %{"jsonrpc" => "2.0", "method" => method, "params" => params}
  end

  def decode_message(data) when is_binary(data) do
    case Message.decode(data) do
      {:ok, [message]} -> message
      {:ok, messages} -> messages
      error -> error
    end
  end

  def encode_message(message) when is_map(message) do
    cond do
      Message.is_notification(message) ->
        Message.encode_notification(message)

      Message.is_error(message) ->
        Message.encode_error(message["error"], message["id"])

      Message.is_response(message) ->
        Message.encode_response(message, message["id"])

      Message.is_request(message) ->
        Message.encode_request(message, message["id"])
    end
  end

  # Response builders for testing - using generic builders

  def ping_response(request_id) do
    build_response(%{}, request_id)
  end

  def resources_list_response(request_id, resources) do
    build_response(%{"resources" => resources, "nextCursor" => nil}, request_id)
  end

  def resources_read_response(request_id, contents) do
    build_response(%{"contents" => contents}, request_id)
  end

  def prompts_list_response(request_id, prompts) do
    build_response(%{"prompts" => prompts, "nextCursor" => nil}, request_id)
  end

  def prompts_get_response(request_id, messages) do
    build_response(%{"messages" => messages}, request_id)
  end

  def tools_list_response(request_id, tools) do
    build_response(%{"tools" => tools, "nextCursor" => nil}, request_id)
  end

  def tools_call_response(request_id, content, is_error \\ false) do
    build_response(%{"content" => content, "isError" => is_error}, request_id)
  end

  def error_response(request_id) do
    build_error(-32_601, "Method not found", request_id)
  end

  def completion_complete_response(request_id, values, total, has_more) do
    build_response(
      %{
        "completion" => %{
          "values" => values,
          "total" => total,
          "hasMore" => has_more
        }
      },
      request_id
    )
  end

  def empty_result_response(request_id) do
    build_response(%{}, request_id)
  end

  # Notification builders - using generic builder

  def log_notification(level, data, logger) do
    build_notification("notifications/message", %{
      "level" => level,
      "data" => data,
      "logger" => logger
    })
  end

  def progress_notification(token, progress \\ 0, total \\ nil) do
    params = %{"progressToken" => token, "progress" => progress}

    params = if total == nil, do: params, else: Map.put(params, "total", total)

    build_notification("notifications/progress", params)
  end

  def cancelled_notification(request_id, reason) do
    build_notification("notifications/cancelled", %{
      "requestId" => request_id,
      "reason" => reason
    })
  end
end
