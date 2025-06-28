defmodule Hermes.MCP.Assertions do
  @moduledoc false

  import ExUnit.Assertions, only: [assert: 2, assert: 1]

  def assert_client_initialized(client) when is_pid(client) do
    state = :sys.get_state(client)
    assert state.server_capabilities, "Expected server capabilities to be set"
  end

  def assert_server_initialized(server) when is_pid(server) do
    state = :sys.get_state(server)
    assert {session_id, _} = state.sessions |> Map.to_list() |> List.first()

    assert session =
             Hermes.Server.Registry.whereis_server_session(StubServer, session_id)

    state = :sys.get_state(session)
    assert state.initialized, "Expected server to be initialized"
  end
end
