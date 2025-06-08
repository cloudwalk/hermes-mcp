defmodule Hermes.MCP.Assertions do
  @moduledoc false

  import ExUnit.Assertions, only: [assert: 2, assert: 1, refute: 2]

  def assert_mcp_response(message) do
    assert message["jsonrpc"] == "2.0"
    assert message["id"], "Response missing id"
    assert Map.has_key?(message, "result"), "Response missing result"
    refute Map.has_key?(message, "error"), "Expected response but got error: #{inspect(message["error"])}"
    message
  end

  def assert_mcp_error(message) do
    assert message["jsonrpc"] == "2.0"
    assert message["id"], "Error response missing id"
    assert Map.has_key?(message, "error"), "Expected error but got result"
    refute Map.has_key?(message, "result"), "Expected error but got result"

    error = message["error"]
    assert is_integer(error["code"]), "Error code must be integer"
    assert is_binary(error["message"]), "Error message must be string"

    message
  end

  def assert_mcp_notification(message) do
    assert message["jsonrpc"] == "2.0"
    assert message["method"], "Notification missing method"
    refute Map.has_key?(message, "id"), "Notification should not have id"
    refute Map.has_key?(message, "result"), "Notification should not have result"
    refute Map.has_key?(message, "error"), "Notification should not have error"
    message
  end

  def assert_client_initialized(client) do
    state = :sys.get_state(client)
    assert state.initialized, "Expected client to be initialized"
    assert state.server_capabilities, "Expected server capabilities to be set"
    state
  end

  def assert_server_initialized(server) do
    state = :sys.get_state(server)
    assert state.initialized, "Expected server to be initialized"
    state
  end
end
