defmodule Hermes.Server.Behaviour do
  @moduledoc """
  Defines the core behavior that all MCP servers must implement.

  This module specifies the required callbacks that concrete server
  implementations must provide to handle MCP protocol interactions.
  """

  alias Hermes.Server.Frame

  @type request :: map()
  @type response :: map()
  @type notification :: map()
  @type mcp_error :: Hermes.MCP.Error.t()
  @type server_info :: map()
  @type server_capabilities :: map()

  @doc """
  Initializes the server state.

  This callback is invoked when the server is started and should perform
  any necessary setup, returning the initial state.

  ## Parameters
    * `init_arg` - Arguments passed from `start_link/3`
    * `frame` - Initial server frame

  ## Return Values
    * `{:ok, frame}` - Server initialized successfully with updated frame
    * `:ignore` - Server initialization ignored, process not started
    * `{:stop, reason}` - Server initialization failed

  ## Examples

      @impl Hermes.Server.Behaviour
      def init(_args, frame) do
        # Simple initialization
        {:ok, frame}
      end

      @impl Hermes.Server.Behaviour
      def init(%{config_file: path}, frame) do
        # Initialize with configuration
        case load_config(path) do
          {:ok, config} ->
            frame = Frame.assign(frame, :config, config)
            {:ok, frame}
          
          {:error, reason} ->
            {:stop, {:config_error, reason}}
        end
      end

      @impl Hermes.Server.Behaviour
      def init(%{port: port}, frame) when port < 1024 do
        # Validation example
        {:stop, {:invalid_port, port}}
      end
  """
  @callback init(init_arg :: term(), Frame.t()) :: {:ok, Frame.t()} | :ignore | {:stop, reason :: term()}

  @doc """
  Handles incoming requests from clients.

  This callback processes client requests and returns an appropriate response,
  along with updated server state.

  ## Parameters
    * `request` - Map containing:
      * `"id"` - Request ID
      * `"method"` - Method name (e.g., "tools/list", "prompts/get")
      * `"params"` - Optional parameters map
    * `frame` - Current server frame with state and metadata

  ## Return Values
    * `{:reply, response, frame}` - Send response to client
    * `{:noreply, frame}` - No response needed
    * `{:error, error, frame}` - Request failed with error

  ## Examples

      @impl Hermes.Server.Behaviour
      def handle_request(%{"method" => "custom/echo", "params" => params}, frame) do
        {:reply, params, frame}
      end

      @impl Hermes.Server.Behaviour
      def handle_request(%{"method" => "data/fetch", "params" => %{"id" => id}}, frame) do
        case fetch_data(id) do
          {:ok, data} ->
            {:reply, %{"data" => data}, frame}
          
          {:error, :not_found} ->
            error = Hermes.MCP.Error.invalid_params(%{message: "Data not found"})
            {:error, error, frame}
        end
      end

      @impl Hermes.Server.Behaviour
      def handle_request(%{"method" => "async/start"}, frame) do
        # Start async operation without immediate response
        Task.start(fn -> do_async_work() end)
        {:noreply, frame}
      end

      # Fallback for unknown methods
      @impl Hermes.Server.Behaviour
      def handle_request(_request, frame) do
        {:error, Hermes.MCP.Error.method_not_found(), frame}
      end
  """
  @callback handle_request(request :: request(), state :: Frame.t()) ::
              {:reply, response :: response(), new_state :: Frame.t()}
              | {:noreply, new_state :: Frame.t()}
              | {:error, error :: mcp_error(), new_state :: Frame.t()}

  @doc """
  Handles incoming notifications from clients.

  This callback processes client notifications, which don't require responses.

  ## Parameters
    * `notification` - Map containing:
      * `"method"` - Notification method name
      * `"params"` - Optional parameters map
    * `frame` - Current server frame

  ## Return Values
    * `{:noreply, frame}` - Notification processed successfully
    * `{:error, error, frame}` - Notification processing failed (error logged but not sent)

  ## Examples

      @impl Hermes.Server.Behaviour
      def handle_notification(%{"method" => "textDocument/didChange", "params" => params}, frame) do
        # Handle document change notification
        document_id = params["uri"]
        content = params["text"]
        
        frame = Frame.update(frame, :documents, fn docs ->
          Map.put(docs || %{}, document_id, content)
        end)
        
        {:noreply, frame}
      end

      @impl Hermes.Server.Behaviour
      def handle_notification(%{"method" => "progress/update", "params" => %{"token" => token}}, frame) do
        # Track progress updates
        Logger.info("Progress update for token: #{token}")
        {:noreply, frame}
      end

      # Ignore unknown notifications
      @impl Hermes.Server.Behaviour
      def handle_notification(_notification, frame) do
        {:noreply, frame}
      end
  """
  @callback handle_notification(notification :: notification(), state :: Frame.t()) ::
              {:noreply, new_state :: Frame.t()}
              | {:error, error :: mcp_error(), new_state :: Frame.t()}

  @doc """
  Returns server information for initialization response.

  ## Return Value
    Map containing:
    * `"name"` - Server name (required)
    * `"version"` - Server version (required)

  ## Examples

      @impl Hermes.Server.Behaviour
      def server_info do
        %{
          "name" => "My MCP Server",
          "version" => "1.0.0"
        }
      end
  """
  @callback server_info :: server_info()

  @doc """
  Returns server capabilities for initialization response.
  Optional callback with default implementation.

  ## Return Value
    Map containing capability configurations:
    * `"tools"` - Tool execution support
    * `"prompts"` - Prompt template support
    * `"resources"` - Resource provision support
    * `"logging"` - Log level configuration support

  ## Examples

      @impl Hermes.Server.Behaviour
      def server_capabilities do
        %{
          "tools" => %{},
          "prompts" => %{
            "listChanged" => true  # Notify on prompt list changes
          },
          "resources" => %{
            "subscribe" => true,    # Support resource subscriptions
            "listChanged" => true   # Notify on resource list changes
          },
          "logging" => %{}
        }
      end
  """
  @callback server_capabilities :: server_capabilities()

  @doc """
  Returns the list of MCP protocol versions supported by this server.

  ## Examples

      iex> MyServer.supported_protocol_versions()
      ["2024-11-05", "2025-03-26"]
  """
  @callback supported_protocol_versions() :: [String.t()]

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
