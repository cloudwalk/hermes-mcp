defmodule Hermes.Server.Session.Storage.ETS do
  @moduledoc """
  ETS-based storage implementation for MCP server sessions.

  This module provides a local, in-memory storage backend using ETS tables.
  It's suitable for single-node deployments and development environments.

  ## Features

  - Fast in-memory lookups
  - Automatic session expiration
  - Efficient filtering and listing
  - No external dependencies

  ## Limitations

  - Sessions are not shared across nodes
  - Sessions are lost on process restart
  - Not suitable for distributed deployments

  ## Usage

  This is the default storage backend for `Hermes.Server.Session`:

      # Start with default ETS storage
      Hermes.Server.Session.start_link()

      # Or explicitly configure
      Hermes.Server.Session.start_link(
        storage: Hermes.Server.Session.Storage.ETS,
        storage_opts: [
          table_name: :my_sessions,
          table_opts: [:set, :protected]
        ]
      )
  """

  @behaviour Hermes.Server.Session.Storage

  @default_table_name :hermes_sessions
  @default_table_opts [:set, :protected, :named_table, {:read_concurrency, true}]

  @impl true
  def init(opts) do
    table_name = Keyword.get(opts, :table_name, @default_table_name)
    table_opts = Keyword.get(opts, :table_opts, @default_table_opts)

    case :ets.info(table_name) do
      :undefined ->
        table = :ets.new(table_name, table_opts)
        {:ok, %{table: table}}

      _ ->
        {:ok, %{table: table_name}}
    end
  rescue
    ArgumentError ->
      {:error, :invalid_table_options}
  end

  @impl true
  def register(state, session_id, session_data) do
    if :ets.insert_new(state.table, {session_id, session_data}) do
      {:ok, state}
    else
      {:error, :session_exists, state}
    end
  end

  @impl true
  def lookup(state, session_id) do
    case :ets.lookup(state.table, session_id) do
      [{^session_id, session_data}] ->
        {:ok, session_data, state}

      [] ->
        {:error, :session_not_found, state}
    end
  end

  @impl true
  def list(state, opts) do
    match_spec = build_match_spec(opts)

    sessions =
      case match_spec do
        :all ->
          state.table
          |> :ets.tab2list()
          |> Enum.map(fn {_id, session} -> session end)

        spec ->
          :ets.select(state.table, spec)
      end

    sessions = apply_pagination(sessions, opts)

    {:ok, sessions, state}
  end

  @impl true
  def update(state, session_id, updates) do
    case :ets.lookup(state.table, session_id) do
      [{^session_id, session_data}] ->
        updated_session =
          session_data
          |> Map.merge(updates)
          |> Map.put(:last_activity, DateTime.utc_now())

        :ets.insert(state.table, {session_id, updated_session})
        {:ok, updated_session, state}

      [] ->
        {:error, :session_not_found, state}
    end
  end

  @impl true
  def unregister(state, session_id) do
    if :ets.member(state.table, session_id) do
      :ets.delete(state.table, session_id)
      {:ok, state}
    else
      {:error, :session_not_found, state}
    end
  end

  @impl true
  def clear(state) do
    count = :ets.info(state.table, :size)
    :ets.delete_all_objects(state.table)
    {:ok, count, state}
  end

  @impl true
  def touch(state, session_id) do
    case :ets.lookup(state.table, session_id) do
      [{^session_id, session_data}] ->
        updated_session = Map.put(session_data, :last_activity, DateTime.utc_now())
        :ets.insert(state.table, {session_id, updated_session})
        {:ok, state}

      [] ->
        {:error, :session_not_found, state}
    end
  end

  @impl true
  def expire_inactive(state, timeout_ms) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -timeout_ms, :millisecond)

    expired_sessions =
      :ets.select(state.table, [
        {
          {:"$1", %{last_activity: :"$2"}},
          [{:<, :"$2", cutoff_time}],
          [:"$1"]
        }
      ])

    Enum.each(expired_sessions, &:ets.delete(state.table, &1))

    {:ok, length(expired_sessions), state}
  end

  defp build_match_spec(opts) do
    filters = []

    filters =
      case Keyword.get(opts, :server) do
        nil -> filters
        server -> [{:server, server} | filters]
      end

    filters =
      case Keyword.get(opts, :transport_type) do
        nil -> filters
        type -> [{:transport_type, type} | filters]
      end

    case filters do
      [] ->
        :all

      _ ->
        build_ets_match_spec(filters)
    end
  end

  defp build_ets_match_spec(filters) do
    pattern = {:"$1", :"$2"}
    guards = []

    guards =
      Enum.reduce(filters, guards, fn
        {:server, server}, acc ->
          [{:==, {:map_get, :server, :"$2"}, server} | acc]

        {:transport_type, type}, acc ->
          [{:==, {:element, 1, {:map_get, :transport, :"$2"}}, type} | acc]
      end)

    case guards do
      [] ->
        [{pattern, [], [:"$2"]}]

      _ ->
        [{pattern, guards, [:"$2"]}]
    end
  end

  defp apply_pagination(sessions, opts) do
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit)

    sessions
    |> Enum.drop(offset)
    |> then(fn sessions ->
      case limit do
        nil -> sessions
        n -> Enum.take(sessions, n)
      end
    end)
  end
end
