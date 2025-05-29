defmodule Hermes.Server.Behaviour do
  @moduledoc """
  Defines the core behavior that all MCP servers must implement.

  This module specifies the required callbacks that concrete server
  implementations must provide to handle MCP protocol interactions.
  """

  @type state :: term()
  @type request :: map()
  @type response :: map()
  @type notification :: map()
  @type mcp_error :: Hermes.MCP.Error.t()
  @type server_info :: %{required(String.t()) => String.t()}

  @doc """
  Initializes the server state.

  This callback is invoked when the server is started and should perform
  any necessary setup, returning the initial state.
  """
  @callback init(init_arg :: term()) ::
              {:ok, state()} | {:error, reason :: term()}

  @doc """
  Handles incoming requests from clients.

  This callback processes client requests and returns an appropriate response,
  along with updated server state.
  """
  @callback handle_request(request :: request(), state :: state()) ::
              {:reply, response :: response(), new_state :: state()}
              | {:noreply, new_state :: state()}
              | {:error, error :: mcp_error(), new_state :: state()}

  @doc """
  Handles incoming notifications from clients.

  This callback processes client notifications, which don't require responses.
  """
  @callback handle_notification(notification :: notification(), state :: state()) ::
              {:noreply, new_state :: state()}
              | {:error, error :: mcp_error(), new_state :: state()}

  @doc """
  Returns server information for initialization response.
  """
  @callback server_info() :: server_info()

  @doc """
  Returns server capabilities for initialization response.
  Optional callback with default implementation.
  """
  @callback server_capabilities() :: map()

  @doc """
  Returns the list of MCP protocol versions supported by this server.

  ## Examples

      iex> MyServer.supported_protocol_versions()
      ["2024-11-05", "2025-03-26"]
  """
  @callback supported_protocol_versions() :: [String.t()]

  @optional_callbacks [server_capabilities: 0]

  @doc """
  Checks if the given module implements the Hermes.Server.Behaviour interface.

  ## Parameters

  - `module`: The module to be checked.

  ## Returns

  - boolean

  ## Examples

      iex> Hermes.Server.Behaviour.impl_by?(MyApp.MCPServer)
      true

      iex> Hermes.Server.Behaviour.impl_by?(String)
      false
  """
  def impl_by?(module) when is_atom(module) do
    if Code.ensure_loaded?(module) do
      callbacks = __MODULE__.behaviour_info(:callbacks)
      functions = module.__info__(:functions)

      Enum.empty?(callbacks -- functions)
    end
  end
end
