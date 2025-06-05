defmodule Hermes.Server.Base do
  @moduledoc """
  Base implementation of an MCP server.

  This module provides the core functionality for handling MCP messages,
  without any higher-level abstractions.
  """

  use GenServer

  import Hermes.Server.Base.State
  import Hermes.Server.Behaviour, only: [impl_by?: 1]
  import Peri

  alias Hermes.Logging
  alias Hermes.MCP.Error
  alias Hermes.MCP.Message
  alias Hermes.Server.Frame
  alias Hermes.Telemetry

  require Message

  @type t :: GenServer.server()

  @typedoc """
  MCP server options

  - `:module` - The module implementing the server behavior (required)
  - `:init_args` - Arguments passed to the module's init/1 callback
  - `:name` - Optional name for registering the GenServer
  """
  @type option ::
          {:module, GenServer.name()}
          | {:init_arg, keyword}
          | {:name, GenServer.name()}
          | GenServer.option()

  defschema(:parse_options, [
    {:module, {:required, {:custom, &Hermes.genserver_name/1}}},
    {:init_arg, {:required, :any}},
    {:name, {:required, {:custom, &Hermes.genserver_name/1}}},
    {:transport, {:required, {:custom, &Hermes.server_transport/1}}}
  ])

  @doc """
  Starts a new MCP server process.

  ## Parameters
    * `opts` - Keyword list of options:
      * `:module` - (required) The module implementing the `Hermes.Server.Behaviour`
      * `:init_arg` - Argument to pass to the module's `init/1` callback
      * `:protocol_version` - The protocol version to use
      * `:name` - Required name for the GenServer process
      * `:transport` - Transport configuration
        * `:layer` - The transport layer to be used (e.g. Hermes.Server.Transport.STDIO or Hermes.Server.Transport.StreamableHTTP)
        * `:name` - Optional transport layer process name for customization

  ## Examples

      iex> Hermes.Server.Base.start_link(module: MyServer, name: MyServer)
      {:ok, pid}
  """
  @spec start_link(Enumerable.t(option())) :: GenServer.on_start()
  def start_link(opts) do
    opts = parse_options!(opts)
    server_name = Keyword.fetch!(opts, :name)

    GenServer.start_link(__MODULE__, Map.new(opts), name: server_name)
  end

  @doc """
  Sends a notification to the client.

  ## Parameters
    * `server` - The server process
    * `method` - The notification method
    * `params` - Optional parameters for the notification

  ## Returns
    * `:ok` if notification was sent successfully
    * `{:error, reason}` otherwise
  """
  @spec send_notification(t(), String.t(), map()) :: :ok | {:error, term()}
  def send_notification(server, method, params \\ %{}) do
    GenServer.call(server, {:send_notification, method, params})
  end

  # GenServer callbacks

  @impl GenServer
  def init(%{module: module} = opts) do
    if not impl_by?(module) do
      raise ArgumentError, "Module #{inspect(module)} does not implement Hermes.Server.Behaviour"
    end

    server_info = module.server_info()
    capabilities = module.server_capabilities()
    protocol_versions = module.supported_protocol_versions()

    state =
      new(%{
        module: module,
        server_info: server_info,
        capabilities: capabilities,
        supported_versions: protocol_versions,
        transport: Map.new(opts.transport)
      })

    Logging.server_event("starting", %{module: module, server_info: server_info, capabilities: capabilities})

    Telemetry.execute(
      Telemetry.event_server_init(),
      %{system_time: System.system_time()},
      %{module: module, server_info: server_info, capabilities: capabilities}
    )

    case module.init(opts.init_arg, Frame.new()) do
      {:ok, %Frame{} = frame} ->
        state = put_frame(state, frame)
        {:ok, state, :hibernate}

      :ignore ->
        :ignore

      {:stop, reason} ->
        Logging.server_event("starting_failed", %{reason: reason}, level: :error)
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:message, message}, from, state) do
    case Message.decode(message) do
      {:ok, [decoded]} when Message.is_request(decoded) ->
        handle_request(decoded, state)

      {:ok, [decoded]} when Message.is_notification(decoded) ->
        handle_notification(decoded, from, state)

      {:error, reason} ->
        handle_decode_error(reason, state)
    end
  end

  @impl GenServer
  def handle_call({:send_notification, method, params}, _from, state) do
    case encode_notification(method, params) do
      {:ok, notification_data} ->
        {:reply, send_to_transport(state.transport, notification_data), state}

      error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def terminate(reason, %{server_info: server_info}) do
    Logging.server_event("terminating", %{reason: reason, server_info: server_info})

    Telemetry.execute(
      Telemetry.event_server_terminate(),
      %{system_time: System.system_time()},
      %{reason: reason, server_info: server_info}
    )

    :ok
  end

  # Request handling

  defp handle_request(%{"method" => "ping", "id" => request_id}, state) do
    {:reply, encode_response(%{}, request_id), state}
  end

  defp handle_request(%{"method" => method}, %{initialized: false} = state) when method != "initialize" do
    error = Error.invalid_request(%{data: %{message: "Server not initialized"}})

    Logging.server_event(
      "request_error",
      %{error: error, reason: "not_initialized"},
      level: :warning
    )

    {:reply, {:ok, Error.to_json_rpc!(error)}, state}
  end

  defp handle_request(%{"method" => "initialize"} = request, %{initialized: false} = state) do
    params = request["params"]
    requested_version = params["protocolVersion"]
    protocol_version = negotiate_protocol_version(state, requested_version)
    state = update_from_initialization(state, params)

    response = %{
      "protocolVersion" => protocol_version,
      "serverInfo" => state.server_info,
      "capabilities" => state.capabilities
    }

    Logging.server_event("initializing", %{
      client_info: params["clientInfo"],
      client_capabilities: params["capabilities"],
      protocol_version: protocol_version
    })

    Telemetry.execute(
      Telemetry.event_server_response(),
      %{system_time: System.system_time()},
      %{method: "initialize", status: :success}
    )

    {:reply, encode_response(response, request["id"]), state}
  end

  defp handle_request(%{"id" => request_id, "method" => "logging/setLevel"} = request, state)
       when is_supported_capability(state, "logging") do
    level = request["params"]["level"]
    {:reply, encode_response(%{}, request_id), %{state | log_level: level}}
  end

  defp handle_request(%{"method" => "notifications/cancelled"} = request, state) do
    # TODO(zoedsoupe): we need to actually keep track of running requests...
    Logging.server_event("handling_notiifcation_cancellation", %{params: request["params"]})
    {:noreply, state}
  end

  defp handle_request(%{"id" => request_id, "method" => method} = request, %{module: module} = state) do
    Logging.server_event("handling_request", %{id: request_id, method: method})

    Telemetry.execute(
      Telemetry.event_server_request(),
      %{system_time: System.system_time()},
      %{id: request_id, method: method}
    )

    case module.handle_request(request, state.frame) do
      {:reply, response, %Frame{} = frame} ->
        Telemetry.execute(
          Telemetry.event_server_response(),
          %{system_time: System.system_time()},
          %{id: request_id, method: method, status: :success}
        )

        {:reply, encode_response(response, request_id), put_frame(state, frame)}

      {:noreply, %Frame{} = frame} ->
        Telemetry.execute(
          Telemetry.event_server_response(),
          %{system_time: System.system_time()},
          %{id: request_id, method: method, status: :noreply}
        )

        {:reply, {:ok, nil}, put_frame(state, frame)}

      {:error, %Error{} = error, %Frame{} = frame} ->
        Logging.server_event(
          "request_error",
          %{id: request_id, method: method, error: error},
          level: :warning
        )

        Telemetry.execute(
          Telemetry.event_server_error(),
          %{system_time: System.system_time()},
          %{id: request_id, method: method, error: error}
        )

        {:reply, {:ok, Error.to_json_rpc!(error, request_id)}, put_frame(state, frame)}
    end
  end

  # Notification handling

  defp handle_notification(%{"method" => "notifications/initialized"}, from, state) do
    GenServer.reply(from, {:ok, nil})
    Logging.server_event("client_initialized", nil)
    {:noreply, %{state | initialized: true}}
  end

  defp handle_notification(notification, from, %{initialized: true, module: module} = state) do
    GenServer.reply(from, {:ok, nil})
    method = notification["method"]

    Logging.server_event("handling_notification", %{method: method})

    Telemetry.execute(
      Telemetry.event_server_notification(),
      %{system_time: System.system_time()},
      %{method: method}
    )

    case module.handle_notification(notification, state.frame) do
      {:noreply, %Frame{} = frame} ->
        {:noreply, put_frame(state, frame)}

      {:error, _error, %Frame{} = frame} ->
        Logging.server_event(
          "notification_handler_error",
          %{method: method},
          level: :warning
        )

        {:noreply, put_frame(state, frame)}
    end
  end

  # Helper functions

  defp handle_decode_error(:invalid_message, state) do
    error = Error.parse_error(%{data: %{message: "Invalid message format"}})

    Logging.server_event(
      "message_decode_error",
      %{reason: :invalid_message, error: error},
      level: :error
    )

    error_response = Error.to_json_rpc!(error)
    send_to_transport(state.transport, error_response)

    {:reply, {:error, error}, state}
  end

  defp handle_decode_error(errors, state) when is_list(errors) do
    errors = Enum.map(errors, &Peri.Error.error_to_map/1)
    error = Error.parse_error(%{data: %{errors: errors, message: "Failed to parse message"}})

    Logging.server_event(
      "message_decode_error",
      %{reason: errors, error: error},
      level: :error
    )

    {:reply, {:ok, Error.to_json_rpc!(error)}, state}
  end

  defp encode_notification(method, params) do
    notification = %{"method" => method, "params" => params}
    Logging.message("outgoing", "notification", nil, notification)
    Message.encode_notification(notification)
  end

  defp encode_response(result, id) do
    response = %{"result" => result, "id" => id}
    Logging.message("outgoing", "response", id, response)
    {:ok, response} = Message.encode_response(%{"result" => result}, id)
    {:ok, response}
  end

  defp send_to_transport(nil, _data) do
    {:error, Error.transport_error(:no_transport, %{data: %{message: "No transport configured"}})}
  end

  defp send_to_transport(%{layer: layer, name: name}, data) do
    with {:error, reason} <- layer.send_message(name, data) do
      {:error, Error.transport_error(:send_failure, %{original_reason: reason})}
    end
  end
end
