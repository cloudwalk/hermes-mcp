defmodule Hermes.Server.Transport.StreamableHTTP.SessionRegistryTest do
  use ExUnit.Case, async: true

  alias Hermes.Server.Transport.StreamableHTTP.SessionRegistry

  @moduletag capture_log: true

  setup do
    {:ok, registry_pid} = SessionRegistry.start_link()

    on_exit(fn ->
      if Process.alive?(registry_pid) do
        Process.exit(registry_pid, :kill)
      end
    end)

    %{registry: registry_pid}
  end

  describe "create_session/1" do
    test "creates a new session with valid server" do
      server =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      assert {:ok, session_id} = SessionRegistry.create_session(server)
      assert is_binary(session_id)
      assert byte_size(session_id) > 0
    end

    test "created session can be looked up" do
      server =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      {:ok, session_id} = SessionRegistry.create_session(server)

      assert {:ok, session_info} = SessionRegistry.lookup_session(session_id)
      assert session_info.server == server
      assert session_info.sse_pid == nil
      assert session_info.mcp_session_id == nil
      assert session_info.client_info == nil
      assert %DateTime{} = session_info.created_at
      assert %DateTime{} = session_info.last_activity
    end

    test "each session gets a unique ID" do
      server =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      {:ok, session_id1} = SessionRegistry.create_session(server)
      {:ok, session_id2} = SessionRegistry.create_session(server)

      assert session_id1 != session_id2
    end
  end

  describe "lookup_session/1" do
    test "returns error for non-existent session" do
      assert {:error, :not_found} = SessionRegistry.lookup_session("non-existent")
    end

    test "returns session info for existing session" do
      server =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      {:ok, session_id} = SessionRegistry.create_session(server)

      assert {:ok, session_info} = SessionRegistry.lookup_session(session_id)
      assert session_info.server == server
    end
  end

  describe "record_activity/1" do
    test "updates last activity timestamp" do
      server =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      {:ok, session_id} = SessionRegistry.create_session(server)

      {:ok, original_info} = SessionRegistry.lookup_session(session_id)

      Process.sleep(10)

      assert :ok = SessionRegistry.record_activity(session_id)

      {:ok, updated_info} = SessionRegistry.lookup_session(session_id)
      assert DateTime.after?(updated_info.last_activity, original_info.last_activity)
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = SessionRegistry.record_activity("non-existent")
    end
  end

  describe "set_sse_connection/2" do
    test "sets SSE PID for existing session" do
      server =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      sse_pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      {:ok, session_id} = SessionRegistry.create_session(server)

      assert :ok = SessionRegistry.set_sse_connection(session_id, sse_pid)

      {:ok, session_info} = SessionRegistry.lookup_session(session_id)
      assert session_info.sse_pid == sse_pid
    end

    test "returns error for non-existent session" do
      sse_pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      assert {:error, :not_found} = SessionRegistry.set_sse_connection("non-existent", sse_pid)
    end
  end

  describe "set_mcp_session_id/2" do
    test "sets MCP session ID for existing session" do
      server =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      {:ok, session_id} = SessionRegistry.create_session(server)

      mcp_session_id = "mcp-session-123"
      assert :ok = SessionRegistry.set_mcp_session_id(session_id, mcp_session_id)

      {:ok, session_info} = SessionRegistry.lookup_session(session_id)
      assert session_info.mcp_session_id == mcp_session_id
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = SessionRegistry.set_mcp_session_id("non-existent", "mcp-123")
    end
  end

  describe "set_client_info/2" do
    test "sets client info for existing session" do
      server =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      {:ok, session_id} = SessionRegistry.create_session(server)

      client_info = %{"name" => "Test Client", "version" => "1.0.0"}
      assert :ok = SessionRegistry.set_client_info(session_id, client_info)

      {:ok, session_info} = SessionRegistry.lookup_session(session_id)
      assert session_info.client_info == client_info
    end

    test "returns error for non-existent session" do
      client_info = %{"name" => "Test Client"}
      assert {:error, :not_found} = SessionRegistry.set_client_info("non-existent", client_info)
    end
  end

  describe "terminate_session/1" do
    test "removes session from registry" do
      server =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      {:ok, session_id} = SessionRegistry.create_session(server)

      assert {:ok, _} = SessionRegistry.lookup_session(session_id)

      :ok = SessionRegistry.terminate_session(session_id)

      assert {:error, :not_found} = SessionRegistry.lookup_session(session_id)
    end

    test "terminates SSE process if present" do
      server =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      sse_pid =
        spawn(fn ->
          receive do
            :terminate -> exit(:normal)
            _ -> :ok
          end
        end)

      {:ok, session_id} = SessionRegistry.create_session(server)
      SessionRegistry.set_sse_connection(session_id, sse_pid)

      assert Process.alive?(sse_pid)

      SessionRegistry.terminate_session(session_id)

      Process.sleep(10)
      refute Process.alive?(sse_pid)
    end

    test "gracefully handles non-existent session" do
      assert :ok = SessionRegistry.terminate_session("non-existent")
    end
  end

  describe "list_sessions/0" do
    test "returns empty list when no sessions" do
      assert [] = SessionRegistry.list_sessions()
    end

    test "returns list of session IDs" do
      server =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      {:ok, session_id1} = SessionRegistry.create_session(server)
      {:ok, session_id2} = SessionRegistry.create_session(server)

      session_ids = SessionRegistry.list_sessions()
      assert length(session_ids) == 2
      assert session_id1 in session_ids
      assert session_id2 in session_ids
    end
  end
end
