defmodule Hermes.Server.Base do
  @moduledoc """
  Base implementation of an MCP server.

  This module provides the core functionality for handling MCP messages,
  managing the protocol lifecycle, and coordinating with transport layers.
  It implements the JSON-RPC message handling, session management, and
  protocol negotiation required by the MCP specification.

  ## Architecture

  The Base server acts as the central message processor in the server stack:
  - Receives messages from transport layers (STDIO, StreamableHTTP)
  - Manages protocol initialization and version negotiation
  - Delegates business logic to the implementation module
  - Maintains session state via Session agents
  - Handles errors and protocol violations

  ## Session Management

  For transports that support multiple sessions (like StreamableHTTP), the Base
  server maintains a registry of Session agents. Each session tracks:
  - Protocol version negotiated with that client
  - Client information and capabilities
  - Initialization state
  - Log level preferences

  ## Message Flow

  1. Transport receives raw message from client
  2. Transport calls Base with `{:message, data, session_id}`
  3. Base decodes and validates the message
  4. Base retrieves or creates session state
  5. Base delegates to implementation module callbacks
  6. Base encodes response and sends back through transport

  ## Example Implementation

      defmodule MyServer do
        use Hermes.Server

        def server_info do
          %{"name" => "My MCP Server", "version" => "1.0.0"}
        end

        def handle_request(%{"method" => "my_method"} = request, frame) do
          result = process_request(request["params"])
          {:reply, result, frame}
        end
      end
  """

  use GenServer

  import Hermes.Server.Behaviour, only: [impl_by?: 1]
  import Peri

  alias Hermes.Logging
  alias Hermes.MCP.Error
  alias Hermes.MCP.Message
  alias Hermes.Protocol
  alias Hermes.Server
  alias Hermes.Server.Frame
  alias Hermes.Server.Session
  alias Hermes.Server.Session.Supervisor, as: SessionSupervisor
  alias Hermes.Telemetry

  require Message
  require Server
  require Session

  @type t :: %{
          module: module,
          server_info: map,
          capabilities: map,
          frame: Frame.t(),
          supported_versions: list(String.t()),
          transport: [layer: module, name: GenServer.name()],
          init_arg: term,
          registry: module,
          sessions: %{required(String.t()) => {GenServer.name(), reference()}}
        }

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

  defschema :parse_options, [
    {:module, {:required, {:custom, &Hermes.genserver_name/1}}},
    {:init_arg, {:required, :any}},
    {:name, {:required, {:custom, &Hermes.genserver_name/1}}},
    {:transport, {:required, {:custom, &Hermes.server_transport/1}}},
    {:registry, {:atom, {:default, Hermes.Server.Registry}}}
  ]

  @doc """
  Starts a new MCP server process.

  ## Parameters
    * `opts` - Keyword list of options:
      * `:module` - (required) The module implementing the `Hermes.Server.Behaviour`
      * `:init_arg` - Argument to pass to the module's `init/2` callback
      * `:name` - (required) Name for the GenServer process
      * `registry` - The custom registry module to use to call related processes
      * `:transport` - (required) Transport configuration
        * `:layer` - The transport module (e.g., `Hermes.Server.Transport.STDIO`)
        * `:name` - The registered name of the transport process

  ## Examples

      # Start with explicit transport configuration
      Hermes.Server.Base.start_link(
        module: MyServer,
        init_arg: [],
        name: {:via, Registry, {MyRegistry, :my_server}},
        transport: [
          layer: Hermes.Server.Transport.STDIO,
          name: {:via, Registry, {MyRegistry, :my_transport}}
        ]
      )

      # Typical usage through Hermes.Server.Supervisor
      Hermes.Server.Supervisor.start_link(MyServer, [], transport: :stdio)
  """
  @spec start_link(Enumerable.t(option())) :: GenServer.on_start()
  def start_link(opts) do
    opts = parse_options!(opts)
    server_name = Keyword.fetch!(opts, :name)

    GenServer.start_link(__MODULE__, Map.new(opts), name: server_name)
  end

  @doc """
  Sends a notification to the client.

  Notifications are fire-and-forget messages that don't expect a response.
  This function is useful for server-initiated communication like progress
  updates or status changes.

  ## Parameters
    * `server` - The server process name or PID
    * `method` - The notification method (e.g., "notifications/message")
    * `params` - Optional parameters for the notification (defaults to `%{}`)

  ## Returns
    * `:ok` if notification was sent successfully
    * `{:error, reason}` if transport fails

  ## Examples

      # Send a log message notification
      Hermes.Server.Base.send_notification(
        server,
        "notifications/message",
        %{"level" => "info", "data" => "Processing started"}
      )

      # Send a custom notification
      Hermes.Server.Base.send_notification(
        server,
        "custom/status_changed",
        %{"status" => "active"}
      )
  """
  @spec send_notification(GenServer.name(), String.t(), map()) :: :ok | {:error, term()}
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

    state = %{
      module: module,
      server_info: server_info,
      capabilities: capabilities,
      supported_versions: protocol_versions,
      transport: Map.new(opts.transport),
      init_arg: opts.init_arg,
      registry: opts.registry,
      sessions: %{},
      frame: Frame.new()
    }

    Logging.server_event("starting", %{module: module, server_info: server_info, capabilities: capabilities})

    Telemetry.execute(
      Telemetry.event_server_init(),
      %{system_time: System.system_time()},
      %{module: module, server_info: server_info, capabilities: capabilities}
    )

    server_init(state)
  end

  @impl GenServer
  def handle_call({:request, decoded, session_id, context}, _from, state) when is_map(decoded) do
    with {:ok, {%Session{} = session, state}} <- maybe_attach_session(session_id, context, state) do
      case handle_single_request(decoded, session, state) do
        {:reply, {:ok, %{"result" => result} = response}, new_state} ->
          {:reply, Message.encode_response(%{"result" => result}, response["id"]), new_state}

        {:reply, {:ok, %{"error" => error} = response}, new_state} ->
          {:reply, Message.encode_error(%{"error" => error}, response["id"]), new_state}

        {:reply, {:error, error}, new_state} ->
          {:reply, {:error, error}, new_state}
      end
    end
  end

  def handle_call({:batch_request, messages, session_id, context}, _from, state) when is_list(messages) do
    with {:ok, {%Session{} = session, state}} <- maybe_attach_session(session_id, context, state) do
      handle_batch_request(messages, session, state)
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
  def handle_cast({:notification, decoded, session_id, context}, state) when is_map(decoded) do
    with {:ok, {%Session{} = session, state}} <- maybe_attach_session(session_id, context, state) do
      if Message.is_initialize_lifecycle(decoded) or Session.is_initialized(session) do
        handle_notification(decoded, session, state)
      else
        Logging.server_event("session_not_initialized_check", %{
          session_id: session.id,
          initialized: session.initialized,
          method: decoded["method"]
        })

        {:noreply, state}
      end
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    session_entry =
      Enum.find(state.sessions, fn
        {_id, {_name, ^ref}} -> true
        _ -> false
      end)

    case session_entry do
      {session_id, _} ->
        Logging.server_event("session_terminated", %{session_id: session_id, reason: reason})

        sessions = Map.delete(state.sessions, session_id)

        frame =
          if state.frame.private[:session_id] == session_id do
            Frame.clear_session(state.frame)
          else
            state.frame
          end

        {:noreply, %{state | sessions: sessions, frame: frame}}

      nil ->
        {:noreply, state}
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

  defp handle_single_request(decoded, session, state) do
    cond do
      Message.is_ping(decoded) ->
        handle_server_ping(decoded, state)

      not (Message.is_initialize_lifecycle(decoded) or Session.is_initialized(session)) ->
        Logging.server_event("session_not_initialized_check", %{
          session_id: session.id,
          initialized: session.initialized,
          method: decoded["method"]
        })

        handle_server_not_initialized(state)

      Message.is_request(decoded) ->
        handle_request(decoded, session, state)

      true ->
        error = Error.protocol(:invalid_request, %{message: "Expected request but got different message type"})
        {:reply, {:error, error}, state}
    end
  end

  defp handle_server_ping(%{"id" => request_id}, state) do
    {:reply, {:ok, Message.build_response(%{}, request_id)}, state}
  end

  defp handle_server_not_initialized(state) do
    error = Error.protocol(:invalid_request, %{message: "Server not initialized"})

    Logging.server_event(
      "request_error",
      %{error: error, reason: "not_initialized"},
      level: :warning
    )

    {:reply, {:ok, Error.build_json_rpc(error)}, state}
  end

  defp handle_batch_request([], _session, state) do
    error = Error.protocol(:invalid_request, %{message: "Batch cannot be empty"})
    {:reply, {:error, error}, state}
  end

  defp handle_batch_request(messages, session, state) do
    if Protocol.supports_feature?(session.protocol_version, :json_rpc_batching) do
      if Enum.any?(messages, &Message.is_initialize/1) do
        error = Error.protocol(:invalid_request, %{message: "Initialize request cannot be part of a batch"})
        {:reply, {:error, error}, state}
      else
        {responses, updated_state} = process_batch_messages(messages, session, state)
        {:reply, {:batch, responses}, updated_state}
      end
    else
      error =
        Error.protocol(:invalid_request, %{
          message: "Batch operations require protocol version 2025-03-26 or later",
          feature: "batch operations",
          protocol_version: session.protocol_version,
          required_version: "2025-03-26"
        })

      {:reply, {:error, error}, state}
    end
  end

  defp process_batch_messages(messages, session, state) do
    {responses, final_state} =
      Enum.reduce(messages, {[], state}, fn message, {acc_responses, acc_state} ->
        case process_single_message(message, session, acc_state) do
          {nil, new_state} -> {acc_responses, new_state}
          {response, new_state} -> {[response | acc_responses], new_state}
        end
      end)

    {Enum.reverse(responses), final_state}
  end

  defp process_single_message(message, session, state) do
    cond do
      Message.is_notification(message) ->
        {:noreply, new_state} = handle_notification(message, session, state)
        {nil, new_state}

      Message.is_ping(message) ->
        {:reply, {:ok, response}, new_state} = handle_server_ping(message, state)
        {response, new_state}

      not Session.is_initialized(session) ->
        {:reply, {:ok, response}, new_state} = handle_server_not_initialized(state)
        {response, new_state}

      Message.is_request(message) ->
        {:reply, {:ok, response}, new_state} = handle_request(message, session, state)
        {response, new_state}

      true ->
        error = Error.protocol(:invalid_request, %{message: "Invalid message in batch"})
        {Error.build_json_rpc(error, Map.get(message, "id")), state}
    end
  end

  # Request handling

  defp handle_request(%{"params" => params} = request, session, state) when Message.is_initialize(request) do
    %{"clientInfo" => client_info, "capabilities" => client_capabilities, "protocolVersion" => requested_version} = params

    protocol_version = negotiate_protocol_version(state.supported_versions, requested_version)
    :ok = Session.update_from_initialization(session.name, protocol_version, client_info, client_capabilities)

    result = %{
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

    {:reply, {:ok, Message.build_response(result, request["id"])}, state}
  end

  defp handle_request(%{"id" => request_id, "method" => "logging/setLevel"} = request, session, state)
       when Server.is_supported_capability(state.capabilities, "logging") do
    level = request["params"]["level"]
    :ok = Session.set_log_level(session.name, level)
    {:reply, {:ok, Message.build_response(%{}, request_id)}, state}
  end

  defp handle_request(%{"id" => request_id, "method" => method} = request, _session, state) do
    Logging.server_event("handling_request", %{id: request_id, method: method})

    Telemetry.execute(
      Telemetry.event_server_request(),
      %{system_time: System.system_time()},
      %{id: request_id, method: method}
    )

    frame =
      Frame.put_request(state.frame, %{
        id: request_id,
        method: method,
        params: request["params"] || %{}
      })

    server_request(request, %{state | frame: frame})
  end

  # Notification handling

  defp handle_notification(%{"method" => "notifications/initialized"}, session, state) do
    Logging.server_event("client_initialized", %{session_id: session.id})
    :ok = Session.mark_initialized(session.name)
    Logging.server_event("session_marked_initialized", %{session_id: session.id, initialized: true})
    {:noreply, %{state | frame: %{state.frame | initialized: true}}}
  end

  defp handle_notification(%{"method" => "notifications/cancelled"} = notification, _session, state) do
    # TODO(zoedsoupe): we need to actually keep track of running requests...
    Logging.server_event("handling_notiifcation_cancellation", %{params: notification["params"]})
    {:noreply, state}
  end

  defp handle_notification(notification, _session, state) do
    method = notification["method"]

    Logging.server_event("handling_notification", %{method: method})

    Telemetry.execute(
      Telemetry.event_server_notification(),
      %{system_time: System.system_time()},
      %{method: method}
    )

    server_notification(notification, state)
  end

  # Helper functions

  defp server_init(%{module: module, init_arg: init_arg} = state) do
    case module.init(init_arg, state.frame) do
      {:ok, %Frame{} = frame} ->
        {:ok, %{state | frame: frame}, :hibernate}

      :ignore ->
        :ignore

      {:stop, reason} ->
        Logging.server_event("starting_failed", %{reason: reason}, level: :error)
        {:stop, reason}
    end
  end

  defp server_request(%{"id" => request_id, "method" => method} = request, %{module: module} = state) do
    case module.handle_request(request, state.frame) do
      {:reply, response, %Frame{} = frame} ->
        Telemetry.execute(
          Telemetry.event_server_response(),
          %{system_time: System.system_time()},
          %{id: request_id, method: method, status: :success}
        )

        frame = Frame.clear_request(frame)
        {:reply, {:ok, Message.build_response(response, request_id)}, %{state | frame: frame}}

      {:noreply, %Frame{} = frame} ->
        Telemetry.execute(
          Telemetry.event_server_response(),
          %{system_time: System.system_time()},
          %{id: request_id, method: method, status: :noreply}
        )

        frame = Frame.clear_request(frame)
        {:reply, {:ok, nil}, %{state | frame: frame}}

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

        frame = Frame.clear_request(frame)
        {:reply, {:ok, Error.build_json_rpc(error, request_id)}, %{state | frame: frame}}
    end
  end

  defp server_notification(%{"method" => method} = notification, %{module: module} = state) do
    case module.handle_notification(notification, state.frame) do
      {:noreply, %Frame{} = frame} ->
        {:noreply, %{state | frame: frame}}

      {:error, _error, %Frame{} = frame} ->
        Logging.server_event(
          "notification_handler_error",
          %{method: method},
          level: :warning
        )

        {:noreply, %{state | frame: frame}}
    end
  end

  @spec maybe_attach_session(session_id :: String.t(), map, t) :: {:ok, {session :: Session.t(), t}}
  defp maybe_attach_session(session_id, context, %{sessions: sessions} = state) when is_map_key(sessions, session_id) do
    {session_name, _ref} = sessions[session_id]
    session = Session.get(session_name)
    {:ok, {session, %{state | frame: populate_frame(state.frame, session, context)}}}
  end

  defp maybe_attach_session(session_id, context, %{sessions: sessions, registry: registry} = state) do
    session_name = registry.server_session(state.module, session_id)

    case SessionSupervisor.create_session(state.module, session_id) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        state = %{state | sessions: Map.put(sessions, session_id, {session_name, ref})}
        session = Session.get(session_name)
        {:ok, {session, %{state | frame: populate_frame(state.frame, session, context)}}}

      {:error, {:already_started, pid}} ->
        ref = Process.monitor(pid)
        state = %{state | sessions: Map.put(sessions, session_id, {session_name, ref})}
        session = Session.get(session_name)
        {:ok, {session, %{state | frame: populate_frame(state.frame, session, context)}}}

      error ->
        error
    end
  end

  defp populate_frame(frame, %Session{} = session, context) do
    {assigns, context} = Map.pop(context, :assigns, %{})
    assigns = Map.merge(frame.assigns, assigns)

    frame
    |> Frame.put_transport(context)
    |> Frame.assign(assigns)
    |> Frame.put_private(%{
      session_id: session.id,
      client_info: session.client_info,
      client_capabilities: session.client_capabilities,
      protocol_version: session.protocol_version
    })
  end

  defp negotiate_protocol_version([latest | _] = supported_versions, requested_version) do
    if requested_version in supported_versions do
      requested_version
    else
      latest
    end
  end

  defp encode_notification(method, params) do
    notification = Message.build_notification(method, params)
    Logging.message("outgoing", "notification", nil, notification)
    Message.encode_notification(notification)
  end

  defp send_to_transport(nil, _data) do
    {:error, Error.transport(:no_transport, %{message: "No transport configured"})}
  end

  defp send_to_transport(%{layer: layer, name: name}, data) do
    with {:error, reason} <- layer.send_message(name, data) do
      {:error, Error.transport(:send_failure, %{original_reason: reason})}
    end
  end
end
