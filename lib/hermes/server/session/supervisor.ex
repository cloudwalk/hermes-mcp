defmodule Hermes.Server.Session.Supervisor do
  @moduledoc """
  Dynamic supervisor for managing per-session server processes.

  This module provides a clean API for starting and stopping session-specific
  server instances without creating atoms dynamically.
  """

  use DynamicSupervisor

  alias Hermes.Server.Registry
  alias Hermes.Server.Session

  @kind :session_supervisor

  @doc """
  Starts the session supervisor.
  """
  def start_link(server) when is_atom(server) do
    name = Registry.supervisor(@kind, server)
    DynamicSupervisor.start_link(__MODULE__, server, name: name)
  end

  def create_session(server, session_id) do
    name = Registry.supervisor(@kind, server)
    DynamicSupervisor.start_child(name, {Session, server: server, session_id: session_id})
  end

  def close_session(server, session_id) when is_binary(session_id) do
    name = Registry.supervisor(@kind, server)

    if pid = Registry.whereis_server_session(server, session_id) do
      DynamicSupervisor.terminate_child(name, pid)
    else
      {:error, :not_found}
    end
  end

  @impl DynamicSupervisor
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
