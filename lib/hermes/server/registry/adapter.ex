defmodule Hermes.Server.Registry.Adapter do
  @moduledoc """
  Behaviour for registry adapters in MCP servers.

  This module defines the interface that registry implementations must follow
  to be pluggable into the Hermes MCP server architecture. It allows users
  to provide custom registry implementations (e.g., using Horde for cluster-wide
  distribution) while maintaining compatibility with the existing API.

  ## Implementing a Custom Registry

  To implement a custom registry adapter, create a module that implements
  all the callbacks defined in this behaviour:

      defmodule MyApp.HordeRegistry do
        @behaviour Hermes.Server.Registry.Adapter

        def child_spec(opts) do
          %{
            id: __MODULE__,
            start: {Horde.Registry, :start_link, [
              [
                name: __MODULE__,
                keys: :unique,
                members: :auto
              ] ++ opts
            ]}
          }
        end

        def server(module) do
          {:via, Horde.Registry, {__MODULE__, {:server, module}}}
        end

        # ... implement other callbacks
      end

  ## Using a Custom Registry

  You can configure a custom registry at multiple levels:

    Hermes.Server.start_link(MyServer, :ok, transport: :stdio, registry: MyApp.HordeRegistry)

  ## Default Implementation

  The default implementation uses Elixir's built-in Registry module.
  """

  @doc """
  Returns a child specification for the registry.

  This is used when starting the registry as part of a supervision tree.
  The implementation should return a valid child specification map or tuple.
  """
  @callback child_spec(opts :: keyword()) :: Supervisor.child_spec()

  @doc """
  Returns a name for a server process.

  The returned value must be a valid GenServer name that can be passed
  to `GenServer.start_link/3` and similar functions.

  ## Parameters

    * `module` - The module implementing the server
  """
  @callback server(module :: module()) :: GenServer.name()

  @doc """
  Returns a name for a `Task.Supervisor` process.

  The returned value must be a valid GenServer name that can be passed
  to `GenServer.start_link/3` and similar functions.

  ## Parameters

    * `module` - The module implementing the server
  """
  @callback task_supervisor(module :: module()) :: GenServer.name()

  @doc """
  Returns a name for a server session process.

  ## Parameters

    * `server_module` - The module implementing the server
    * `session_id` - The unique session identifier
  """
  @callback server_session(server_module :: module(), session_id :: String.t()) ::
              GenServer.name()

  @doc """
  Returns a name for a transport process.

  ## Parameters

    * `server_module` - The module implementing the server
    * `transport_type` - The type of transport (e.g., :stdio, :sse, :websocket)
  """
  @callback transport(server_module :: module(), transport_type :: atom()) ::
              GenServer.name()

  @doc """
  Returns a name for a supervisor process.

  ## Parameters

    * `kind` - The kind of supervisor (e.g., :supervisor, :session_supervisor)
    * `server_module` - The module implementing the server
  """
  @callback supervisor(kind :: atom(), server_module :: module()) :: GenServer.name()

  @doc """
  Gets the PID of a registered server.

  Returns the PID if the server is registered, nil otherwise.

  ## Parameters

    * `server_module` - The module implementing the server
  """
  @callback whereis_server(server_module :: module()) :: pid() | nil

  @doc """
  Gets the PID of a server session process.

  Returns the PID if the session is registered, nil otherwise.

  ## Parameters

    * `server_module` - The module implementing the server
    * `session_id` - The unique session identifier
  """
  @callback whereis_server_session(
              server_module :: module(),
              session_id :: String.t()
            ) :: pid() | nil

  @doc """
  Gets the PID of a transport process.

  Returns the PID if the transport is registered, nil otherwise.

  ## Parameters

    * `server_module` - The module implementing the server
    * `transport_type` - The type of transport
  """
  @callback whereis_transport(server_module :: module(), transport_type :: atom()) ::
              pid() | nil

  @doc """
  Gets the PID of a supervisor process.

  Returns the PID if the supervisor is registered, nil otherwise.

  ## Parameters

    * `kind` - The kind of supervisor
    * `server_module` - The module implementing the server
  """
  @callback whereis_supervisor(kind :: atom(), server_module :: module()) ::
              pid() | nil
end
