defmodule Hermes.Server.Registry do
  @moduledoc false

  def child_spec(_) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end

  @doc """
  Returns a via tuple for naming a server process.
  """
  @spec server(server_module :: module()) :: GenServer.name()
  def server(module) do
    {:via, Registry, {__MODULE__, {:server, module}}}
  end

  @spec task_supervisor(server_module :: module()) :: GenServer.name()
  def task_supervisor(module) when is_atom(module) do
    {:via, Registry, {__MODULE__, {:task_supervisor, module}}}
  end

  @doc """
  Returns a via tuple for naming a server session process.
  """
  @spec server_session(server_module :: module(), session_id :: String.t()) ::
          GenServer.name()
  def server_session(server, session_id) do
    {:via, Registry, {__MODULE__, {:session, server, session_id}}}
  end

  @doc """
  Returns a via tuple for naming a transport process.
  """
  @spec transport(server_module :: module(), transport_type :: atom()) ::
          GenServer.name()
  def transport(module, type) when is_atom(module) do
    {:via, Registry, {__MODULE__, {:transport, module, type}}}
  end

  @doc """
  Returns a via tuple for naming a supervisor process.
  """
  @spec supervisor(kind :: atom(), server_module :: module()) :: GenServer.name()
  def supervisor(kind \\ :supervisor, module) do
    {:via, Registry, {__MODULE__, {kind, module}}}
  end

  @doc """
  Gets the PID of a session-specific server.
  """
  @spec whereis_server_session(server_module :: module(), session_id :: String.t()) ::
          pid | nil
  def whereis_server_session(module, session_id) do
    case Registry.lookup(__MODULE__, {:session, module, session_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Gets the PID of a supervisor process.
  """
  @spec whereis_supervisor(atom(), module()) :: pid() | nil
  def whereis_supervisor(server, kind \\ :supervisor) when is_atom(server) do
    case Registry.lookup(__MODULE__, {kind, server}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Gets the PID of a registered server.
  """
  @spec whereis_server(module()) :: pid | nil
  def whereis_server(module) when is_atom(module) do
    case Registry.lookup(__MODULE__, {:server, module}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Gets the PID of a registered transport.
  """
  @spec whereis_transport(module(), atom()) :: pid | nil
  def whereis_transport(module, type) when is_atom(module) and is_atom(type) do
    case Registry.lookup(__MODULE__, {:transport, module, type}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end
end
