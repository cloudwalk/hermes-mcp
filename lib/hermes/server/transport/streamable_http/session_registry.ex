defmodule Hermes.Server.Transport.StreamableHTTP.SessionRegistry do
  @moduledoc """
  ETS-based session registry for StreamableHTTP transport.

  Manages active sessions, tracks SSE connections, and handles session lifecycle.
  """

  use GenServer

  alias Hermes.Logging
  alias Hermes.MCP.ID
  alias Hermes.Telemetry

  @table_name :hermes_streamable_http_sessions
  @cleanup_interval_ms 60_000
  @session_timeout_ms 300_000

  @type session_id :: String.t()
  @type session_info :: %{
          server: GenServer.server(),
          sse_pid: pid() | nil,
          created_at: DateTime.t(),
          last_activity: DateTime.t(),
          mcp_session_id: String.t() | nil,
          client_info: map() | nil
        }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Creates a new session"
  @spec create_session(GenServer.server()) :: {:ok, session_id()}
  def create_session(server) do
    session_id = ID.generate_session_id()
    now = DateTime.utc_now()

    session_info = %{
      server: server,
      sse_pid: nil,
      created_at: now,
      last_activity: now,
      mcp_session_id: nil,
      client_info: nil
    }

    :ets.insert(@table_name, {session_id, session_info})

    Logging.server_event("session_created", %{
      session_id: session_id,
      server: server
    })

    Telemetry.execute(
      Telemetry.event_server_session_created(),
      %{system_time: System.system_time()},
      %{session_id: session_id, server: server}
    )

    {:ok, session_id}
  end

  @doc "Looks up a session by ID"
  @spec lookup_session(session_id()) :: {:ok, session_info()} | {:error, :not_found}
  def lookup_session(session_id) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, session_info}] -> {:ok, session_info}
      [] -> {:error, :not_found}
    end
  end

  @doc "Updates session activity timestamp"
  @spec record_activity(session_id()) :: :ok | {:error, :not_found}
  def record_activity(session_id) do
    update_session_field(session_id, :last_activity, DateTime.utc_now())
  end

  @doc "Sets the SSE connection process for a session"
  @spec set_sse_connection(session_id(), pid()) :: :ok | {:error, :not_found}
  def set_sse_connection(session_id, sse_pid) do
    update_session_field(session_id, :sse_pid, sse_pid)
  end

  @doc "Sets the MCP session ID for a session"
  @spec set_mcp_session_id(session_id(), String.t()) :: :ok | {:error, :not_found}
  def set_mcp_session_id(session_id, mcp_session_id) do
    update_session_field(session_id, :mcp_session_id, mcp_session_id)
  end

  @doc "Sets client info for a session"
  @spec set_client_info(session_id(), map()) :: :ok | {:error, :not_found}
  def set_client_info(session_id, client_info) do
    update_session_field(session_id, :client_info, client_info)
  end

  @doc "Terminates a session"
  @spec terminate_session(session_id()) :: :ok
  def terminate_session(session_id) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, session_info}] ->
        # Stop SSE connection if active
        if session_info.sse_pid && Process.alive?(session_info.sse_pid) do
          send(session_info.sse_pid, :terminate)
        end

        :ets.delete(@table_name, session_id)

        Logging.server_event("session_terminated", %{
          session_id: session_id,
          server: session_info.server
        })

        Telemetry.execute(
          Telemetry.event_server_session_terminated(),
          %{system_time: System.system_time()},
          %{session_id: session_id, server: session_info.server}
        )

      [] ->
        :ok
    end

    :ok
  end

  @doc "Lists all active sessions"
  @spec list_sessions() :: [session_id()]
  def list_sessions do
    @table_name
    |> :ets.tab2list()
    |> Enum.map(fn {session_id, _} -> session_id end)
  end

  # GenServer implementation

  @impl GenServer
  def init(_opts) do
    :ets.new(@table_name, [:set, :public, :named_table, {:read_concurrency, true}])
    schedule_cleanup()

    Logging.server_event("session_registry_started", %{})

    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:create_session, server}, _from, state) do
    {:reply, create_session(server), state}
  end

  @impl GenServer
  def handle_call({:lookup_session, session_id}, _from, state) do
    {:reply, lookup_session(session_id), state}
  end

  @impl GenServer
  def handle_call({:record_activity, session_id}, _from, state) do
    {:reply, record_activity(session_id), state}
  end

  @impl GenServer
  def handle_call({:set_sse_connection, session_id, sse_pid}, _from, state) do
    {:reply, set_sse_connection(session_id, sse_pid), state}
  end

  @impl GenServer
  def handle_call({:terminate_session, session_id}, _from, state) do
    {:reply, terminate_session(session_id), state}
  end

  @impl GenServer
  def handle_call(:list_sessions, _from, state) do
    {:reply, list_sessions(), state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    cleanup_expired_sessions()
    schedule_cleanup()
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp update_session_field(session_id, field, value) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, session_info}] ->
        updated_info = Map.put(session_info, field, value)
        :ets.insert(@table_name, {session_id, updated_info})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp cleanup_expired_sessions do
    now = DateTime.utc_now()
    timeout_threshold = DateTime.add(now, -@session_timeout_ms, :millisecond)

    expired_sessions =
      @table_name
      |> :ets.tab2list()
      |> Enum.filter(fn {_session_id, session_info} ->
        DateTime.before?(session_info.last_activity, timeout_threshold)
      end)

    Enum.each(expired_sessions, fn {session_id, _} ->
      Logging.server_event("session_expired", %{session_id: session_id})
      terminate_session(session_id)
    end)

    if length(expired_sessions) > 0 do
      Telemetry.execute(
        Telemetry.event_server_session_cleanup(),
        %{system_time: System.system_time()},
        %{expired_count: length(expired_sessions)}
      )
    end
  end
end
