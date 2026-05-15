defmodule Hermes.Server.Session.Supervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Hermes.Server.Session

  @kind :session_supervisor

  @doc """
  Starts the session supervisor.

  ## Options
    * `:server` - The server module atom (required)
    * `:registry` - Registry adapter (default: `Hermes.Server.Registry`)
    * `:supervisor_module` - Underlying supervisor implementation. Defaults
      to `DynamicSupervisor`. Pass `Horde.DynamicSupervisor` to make
      session supervision cluster-wide so distributed clients (load
      balanced across nodes) attach to the same session process.
    * `:supervisor_opts` - Extra options forwarded to the supervisor
      module's `start_link/1` (e.g. `[members: :auto]` for Horde).

  ## Examples

      # Default — single-node DynamicSupervisor
      {:ok, _} = Session.Supervisor.start_link(server: MyServer)

      # Cluster-wide via Horde
      {:ok, _} = Session.Supervisor.start_link(
        server: MyServer,
        supervisor_module: Horde.DynamicSupervisor,
        supervisor_opts: [members: :auto]
      )
  """
  def start_link(opts \\ []) do
    server = Keyword.fetch!(opts, :server)
    registry = Keyword.get(opts, :registry, Hermes.Server.Registry)
    supervisor_module = Keyword.get(opts, :supervisor_module, DynamicSupervisor)
    supervisor_opts = Keyword.get(opts, :supervisor_opts, [])
    name = registry.supervisor(@kind, server)

    # The supervisor `name` is unique per running instance (the registry
    # adapter derives it from the server module + kind), so keying by
    # `name` lets two instances of the same server module under different
    # registries or supervisor modules coexist without colliding.
    :persistent_term.put({__MODULE__, name}, supervisor_module)

    if supervisor_module == DynamicSupervisor do
      DynamicSupervisor.start_link(__MODULE__, server, name: name)
    else
      supervisor_module.start_link(
        Keyword.merge(
          [name: name, strategy: :one_for_one],
          supervisor_opts
        )
      )
    end
  end

  @doc """
  Creates a new session for a client connection.

  When the supervisor was started with `:supervisor_module` set to a
  cluster-wide implementation (e.g. `Horde.DynamicSupervisor`), the
  start request is routed via consistent hashing to the single node
  that owns the session. That node's start either succeeds (`{:ok, pid}`)
  or returns `{:error, {:already_started, pid}}` — guaranteed to be the
  same answer regardless of which node initiated the call.
  """
  def create_session(registry \\ Hermes.Server.Registry, server, session_id) do
    name = registry.supervisor(@kind, server)
    supervisor_module = lookup_supervisor_module(name)
    session_name = registry.server_session(server, session_id)

    supervisor_module.start_child(
      name,
      {Session, session_id: session_id, name: session_name}
    )
  end

  @doc """
  Looks up a live session **without** creating one.

  Returns `{:ok, pid}` when a session process for `session_id` is
  currently registered, or `:not_found` otherwise. Resolution goes
  through the configured registry adapter's `whereis_server_session/2`,
  so it is cluster-wide whenever that adapter is distributed (e.g. a
  `Horde.Registry`-backed adapter) — the same resolution
  `close_session/3` uses, minus the side effect.

  Unlike `create_session/3` this never calls `start_child`: it is the
  existence probe that distinguishes a resumable session from an
  unknown/terminated one. Per the MCP Streamable HTTP spec a request
  bearing an unknown session id must yield HTTP 404 rather than
  silently vivifying a fresh, uninitialized session.
  """
  @spec whereis_session(module(), module(), String.t()) :: {:ok, pid()} | :not_found
  def whereis_session(registry \\ Hermes.Server.Registry, server, session_id) when is_binary(session_id) do
    case registry.whereis_server_session(server, session_id) do
      pid when is_pid(pid) -> {:ok, pid}
      nil -> :not_found
    end
  end

  @doc """
  Terminates a session and cleans up its resources.
  """
  def close_session(registry \\ Hermes.Server.Registry, server, session_id) when is_binary(session_id) do
    name = registry.supervisor(@kind, server)
    supervisor_module = lookup_supervisor_module(name)

    if pid = registry.whereis_server_session(server, session_id) do
      supervisor_module.terminate_child(name, pid)
    else
      {:error, :not_found}
    end
  end

  @impl DynamicSupervisor
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  defp lookup_supervisor_module(server) do
    :persistent_term.get({__MODULE__, server}, DynamicSupervisor)
  end
end
