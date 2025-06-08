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
end
