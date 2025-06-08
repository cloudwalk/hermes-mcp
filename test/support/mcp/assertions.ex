defmodule Hermes.MCP.Assertions do
  @moduledoc false

  import ExUnit.Assertions, only: [assert: 2]

  def assert_client_initialized(client) do
    state = :sys.get_state(client)
    assert state.server_capabilities, "Expected server capabilities to be set"
    state
  end

  def assert_server_initialized(server) do
    state = :sys.get_state(server)
    assert state.initialized, "Expected server to be initialized"
    state
  end
end
