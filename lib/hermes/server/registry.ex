defmodule Hermes.Server.Registry do
  @moduledoc """
  Registry for MCP server and transport processes.

  This module provides a safe way to manage process names without creating
  atoms dynamically at runtime. It uses a via tuple pattern with Registry.

  ## Usage

      # Register a server process
      {:ok, _pid} = GenServer.start_link(MyServer, arg, name: Registry.server(MyModule))
      
      # Register a transport process
      {:ok, _pid} = GenServer.start_link(Transport, arg, name: Registry.transport(MyModule, :stdio))
      
      # Look up a process
      GenServer.call(Registry.server(MyModule), :ping)
  """

  @registry_name __MODULE__

  @doc """
  Starts the registry as part of your supervision tree.

  This should be started before any MCP servers.
  """
  def child_spec(_opts) do
    Registry.child_spec(
      keys: :unique,
      name: @registry_name
    )
  end

  @doc """
  Returns a via tuple for naming a server process.

  ## Examples

      iex> Hermes.Server.Registry.server(MyApp.Calculator)
      {:via, Registry, {Hermes.Server.Registry, {:server, MyApp.Calculator}}}
  """
  @spec server(module()) :: GenServer.name()
  def server(module) when is_atom(module) do
    {:via, Registry, {@registry_name, {:server, module}}}
  end

  @doc """
  Returns a via tuple for naming a server session process.

  ## Examples

      iex> Hermes.Server.Registry.server_session(Calculator, "session_123")
      {:via, Registry, {Hermes.Server.Registry, {:session, Calculator, "session_123"}}}
  """
  @spec server_session(module(), String.t()) :: GenServer.name()
  def server_session(server, id) when is_binary(id) do
    {:via, Registry, {@registry_name, {:session, server, id}}}
  end

  @doc """
  Returns a via tuple for naming a transport process.

  ## Examples

      iex> Hermes.Server.Registry.transport(MyApp.Calculator, :stdio)
      {:via, Registry, {Hermes.Server.Registry, {:transport, MyApp.Calculator, :stdio}}}
  """
  @spec transport(module(), atom()) :: GenServer.name()
  def transport(module, type) when is_atom(module) and is_atom(type) do
    {:via, Registry, {@registry_name, {:transport, module, type}}}
  end

  @doc """
  Returns a via tuple for naming a supervisor process.

  ## Examples

      iex> Hermes.Server.Registry.supervisor(MyApp.Calculator)
      {:via, Registry, {Hermes.Server.Registry, {:supervisor, MyApp.Calculator}}}
  """
  @spec supervisor(module()) :: GenServer.name()
  def supervisor(module) when is_atom(module) do
    {:via, Registry, {@registry_name, {:supervisor, module}}}
  end

  @doc """
  Lists all registered servers.

  ## Examples

      iex> Hermes.Server.Registry.list_servers()
      [MyApp.Calculator, MyApp.FileServer]
  """
  @spec list_servers() :: [module()]
  def list_servers do
    @registry_name
    |> Registry.select([{{:"$1", :_, :_}, [{:==, {:element, 1, :"$1"}, :server}], [:"$1"]}])
    |> Enum.map(fn {:server, module} -> module end)
    |> Enum.uniq()
  end

  @doc """
  Lists all registered transports for a server.

  ## Examples

      iex> Hermes.Server.Registry.list_transports(MyApp.Calculator)
      [:stdio, :streamable_http]
  """
  @spec list_transports(module()) :: [atom()]
  def list_transports(module) when is_atom(module) do
    @registry_name
    |> Registry.select([
      {{:"$1", :_, :_}, [{:andalso, {:==, {:element, 1, :"$1"}, :transport}, {:==, {:element, 2, :"$1"}, module}}],
       [:"$1"]}
    ])
    |> Enum.map(fn {:transport, ^module, type} -> type end)
  end

  @doc """
  Lists all server sessions for a given module.

  ## Examples

      iex> Hermes.Server.Registry.list_server_sessions(MyApp.Calculator)
      ["session-abc123", "session-def456"]
  """
  @spec list_server_sessions(module()) :: [String.t()]
  def list_server_sessions(module) when is_atom(module) do
    @registry_name
    |> Registry.select([
      {{:"$1", :_, :_}, [{:andalso, {:==, {:element, 1, :"$1"}, :session}, {:==, {:element, 2, :"$1"}, module}}], [:"$1"]}
    ])
    |> Enum.map(fn {:session, ^module, id} -> id end)
  end

  @doc """
  Gets the PID of a session-specific server.

  ## Examples

      iex> Hermes.Server.Registry.whereis_server_session("session-abc123", MyApp.Calculator)
      {:ok, #PID<0.125.0>}
  """
  @spec whereis_server_session(module(), String.t()) :: {:ok, pid()} | :error
  def whereis_server_session(module, session_id) when is_binary(session_id) and is_atom(module) do
    case Registry.lookup(@registry_name, {:session, module, session_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Checks if a server is registered.

  ## Examples

      iex> Hermes.Server.Registry.registered?(MyApp.Calculator)
      true
  """
  @spec registered?(module()) :: boolean()
  def registered?(module) when is_atom(module) do
    case Registry.lookup(@registry_name, {:server, module}) do
      [] -> false
      _ -> true
    end
  end

  @doc """
  Gets the PID of a registered server.

  ## Examples

      iex> Hermes.Server.Registry.whereis_server(MyApp.Calculator)
      {:ok, #PID<0.123.0>}
      
      iex> Hermes.Server.Registry.whereis_server(NotRegistered)
      :error
  """
  @spec whereis_server(module()) :: {:ok, pid()} | :error
  def whereis_server(module) when is_atom(module) do
    case Registry.lookup(@registry_name, {:server, module}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Gets the PID of a registered transport.

  ## Examples

      iex> Hermes.Server.Registry.whereis_transport(MyApp.Calculator, :stdio)
      {:ok, #PID<0.124.0>}
  """
  @spec whereis_transport(module(), atom()) :: {:ok, pid()} | :error
  def whereis_transport(module, type) when is_atom(module) and is_atom(type) do
    case Registry.lookup(@registry_name, {:transport, module, type}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end
end
