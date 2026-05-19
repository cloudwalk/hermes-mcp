defmodule Hermes.Server.Session.SupervisorTest do
  # ENA-9175 T1.2: the lookup-only existence probe used by the Base
  # discriminator to tell a resumable session from an unknown/terminated
  # one. It MUST NOT have create_session's side effect of vivifying a
  # session — a false vivification on an unknown id is exactly the bug
  # ENA-9175 fixes (silent uninitialized session → init-wait wedge).
  use Hermes.MCP.Case, async: false

  alias Hermes.Server.Session.Supervisor, as: SessionSupervisor

  setup :with_default_registry

  setup %{registry: registry} do
    start_supervised!({SessionSupervisor, server: StubServer, registry: registry})
    :ok
  end

  describe "whereis_session/3" do
    test "returns :not_found for an unseen session id", %{registry: registry} do
      assert :not_found == SessionSupervisor.whereis_session(registry, StubServer, "never-seen")
    end

    test "returns {:ok, pid} for a created session", %{registry: registry} do
      assert {:ok, created_pid} = SessionSupervisor.create_session(registry, StubServer, "live-1")

      assert {:ok, ^created_pid} =
               SessionSupervisor.whereis_session(registry, StubServer, "live-1")
    end

    test "does NOT create a child when the session is unknown", %{registry: registry} do
      sup_pid = registry.whereis_supervisor(StubServer, :session_supervisor)
      %{active: before_count} = DynamicSupervisor.count_children(sup_pid)

      assert :not_found == SessionSupervisor.whereis_session(registry, StubServer, "phantom")

      %{active: after_count} = DynamicSupervisor.count_children(sup_pid)

      assert before_count == after_count,
             "whereis_session must be side-effect free; child count changed #{before_count} -> #{after_count}"
    end
  end
end
