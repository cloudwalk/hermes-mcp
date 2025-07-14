defmodule MockCustomRegistry do
  @moduledoc false
  @behaviour Hermes.Server.Registry.Adapter

  alias Hermes.Server.Registry.Adapter

  @impl true
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {GenServer, :start_link, [__MODULE__, opts, [name: __MODULE__]]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @impl Adapter
  def transport(server, transport_type) do
    {:via, __MODULE__, {:transport, server, transport_type}}
  end

  @impl Adapter
  def task_supervisor(server_module) do
    {:via, __MODULE__, {:task_supervisor, server_module}}
  end

  @impl Adapter
  def server(server_module) do
    {:via, __MODULE__, {:server, server_module}}
  end

  @impl Adapter
  def server_session(server_module, session_id) do
    {:via, __MODULE__, {:server_session, server_module, session_id}}
  end

  @impl Adapter
  def supervisor(kind, server_module) do
    {:via, __MODULE__, {:supervisor, kind, server_module}}
  end

  @impl Adapter
  def whereis_server(server_module) do
    case :ets.lookup(__MODULE__, {:server, server_module}) do
      [{_, pid}] -> pid
      [] -> nil
    end
  end

  @impl Adapter
  def whereis_server_session(server_module, session_id) do
    case :ets.lookup(__MODULE__, {:server_session, server_module, session_id}) do
      [{_, pid}] -> pid
      [] -> nil
    end
  end

  @impl Adapter
  def whereis_transport(server_module, transport_type) do
    case :ets.lookup(__MODULE__, {:transport, server_module, transport_type}) do
      [{_, pid}] -> pid
      [] -> nil
    end
  end

  @impl Adapter
  def whereis_supervisor(kind, server_module) do
    case :ets.lookup(__MODULE__, {:supervisor, kind, server_module}) do
      [{_, pid}] -> pid
      [] -> nil
    end
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, %{}}
  end
end
