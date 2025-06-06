defmodule Hermes.Client.Registry do
  @moduledoc """
  Registry naming conventions for MCP client processes.

  This module provides consistent naming for client processes
  to avoid conflicts and enable easy process lookup.
  """

  @doc """
  Returns the registered name for a client supervisor.
  """
  @spec supervisor(module()) :: {:via, Registry, {Hermes.Registry, term()}}
  def supervisor(client_module) do
    {:via, Registry, {Hermes.Registry, {__MODULE__, :supervisor, client_module}}}
  end

  @doc """
  Returns the registered name for a base client process.
  """
  @spec client(module()) :: {:via, Registry, {Hermes.Registry, term()}}
  def client(client_module) do
    {:via, Registry, {Hermes.Registry, {__MODULE__, :client, client_module}}}
  end

  @doc """
  Returns the registered name for a transport process.
  """
  @spec transport(module(), atom()) :: {:via, Registry, {Hermes.Registry, term()}}
  def transport(client_module, transport_type) do
    {:via, Registry, {Hermes.Registry, {__MODULE__, :transport, client_module, transport_type}}}
  end

  @doc """
  Looks up the PID of a client process by its module.

  Returns `{:ok, pid}` if found, `:error` otherwise.

  ## Examples

      iex> Hermes.Client.Registry.whereis_client(MyApp.MCPClient)
      {:ok, #PID<0.123.0>}

      iex> Hermes.Client.Registry.whereis_client(NonExistentClient)
      :error
  """
  @spec whereis_client(module()) :: {:ok, pid()} | :error
  def whereis_client(client_module) do
    case Registry.lookup(Hermes.Registry, {__MODULE__, :client, client_module}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  Looks up the PID of a transport process by its client module and type.

  Returns `{:ok, pid}` if found, `:error` otherwise.

  ## Examples

      iex> Hermes.Client.Registry.whereis_transport(MyApp.MCPClient, :stdio)
      {:ok, #PID<0.124.0>}

      iex> Hermes.Client.Registry.whereis_transport(MyApp.MCPClient, :sse)
      :error
  """
  @spec whereis_transport(module(), atom()) :: {:ok, pid()} | :error
  def whereis_transport(client_module, transport_type) do
    case Registry.lookup(Hermes.Registry, {__MODULE__, :transport, client_module, transport_type}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end
end
