defmodule Hermes.Server.Base do
  @moduledoc false

  use GenServer
  use Hermes.Logging

  import Peri

  alias Hermes.MCP.Error
  alias Hermes.MCP.ID
  alias Hermes.MCP.Message
  alias Hermes.Server
  alias Hermes.Server.Frame
  alias Hermes.Server.Session
  alias Hermes.Server.Session.Supervisor, as: SessionSupervisor
  alias Hermes.Telemetry

  require Message
  require Server
  require Session

  @default_session_idle_timeout to_timeout(minute: 30)

  @type t :: %{
          module: module,
          server_info: map,
          capabilities: map,
          frame: Frame.t(),
          supported_versions: list(String.t()),
          transport: [layer: module, name: GenServer.name()],
          registry: module,
          sessions: %{required(String.t()) => {GenServer.name(), reference()}},
          session_idle_timeout: pos_integer(),
          expiry_timers: %{required(String.t()) => reference()},
          server_requests: %{
            required(String.t()) => %{
              method: String.t(),
              session_id: String.t(),
              metadata: map(),
              timer_ref: reference()
            }
          }
        }

  @typedoc """
  MCP server options

  - `:module` - The module implementing the server behavior (required)
  - `:name` - Optional name for registering the GenServer
  - `:session_idle_timeout` - Time in milliseconds before idle sessions expire (default: 30 minutes)
  """
  @type option ::
          {:module, GenServer.name()}
          | {:name, GenServer.name()}
          | {:session_idle_timeout, pos_integer()}
          | GenServer.option()

  defschema(:parse_options, [
    {:module, {:required, {:custom, &Hermes.genserver_name/1}}},
    {:name, {:required, {:custom, &Hermes.genserver_name/1}}},
    {:transport, {:required, {:custom, &Hermes.server_transport/1}}},
    {:registry, {:atom, {:default, Hermes.Server.Registry}}},
    {:session_idle_timeout, {{:integer, {:gte, 1}}, {:default, @default_session_idle_timeout}}}
  ])

  @spec start_link(Enumerable.t(option())) :: GenServer.on_start()
  def start_link(opts) do
    opts = parse_options!(opts)
    server_name = Keyword.fetch!(opts, :name)

    GenServer.start_link(__MODULE__, Map.new(opts), name: server_name)
  end

  # GenServer callbacks

  @impl GenServer
  def init(%{module: module} = opts) do
    server_info = module.server_info()
    capabilities = module.server_capabilities()
    protocol_versions = module.supported_protocol_versions()

    state = %{
      module: module,
      server_info: server_info,
      capabilities: capabilities,
      supported_versions: protocol_versions,
      transport: Map.new(opts.transport),
      registry: opts.registry,
      sessions: %{},
      session_idle_timeout: opts.session_idle_timeout,
      expiry_timers: %{},
      frame: Frame.new(),
      server_requests: %{}
    }

    Logging.server_event("starting", %{
      module: module,
      server_info: server_info,
      capabilities: capabilities
    })

    Telemetry.execute(
      Telemetry.event_server_init(),
      %{system_time: System.system_time()},
      %{module: module, server_info: server_info, capabilities: capabilities}
    )

    {:ok, state, :hibernate}
  end

  @impl GenServer
  def handle_call({:request, decoded, session_id, context}, _from, state) when is_map(decoded) do
    with {:ok, {%Session{} = session, state}} <-
           maybe_attach_session(session_id, context, state) do
      case handle_single_request(decoded, session, state) do
        {:reply, {:ok, %{"result" => result} = response}, new_state} ->
          request_id = response["id"]
          if request_id, do: Session.complete_request(session.name, request_id)

          {:reply, Message.encode_response(%{"result" => result}, response["id"]), new_state}

        {:reply, {:ok, %{"error" => error} = response}, new_state} ->
          request_id = response["id"]
          if request_id, do: Session.complete_request(session.name, request_id)

          {:reply, Message.encode_error(%{"error" => error}, response["id"]), new_state}

        {:reply, {:error, error}, new_state} ->
          request_id = decoded["id"]
          if request_id, do: Session.complete_request(session.name, request_id)
          {:reply, {:error, error}, new_state}
      end
    end
  end

  def handle_call(request, from, %{module: module} = state) do
    case module.handle_call(request, from, state.frame) do
      {:reply, reply, frame} ->
        {:reply, reply, %{state | frame: frame}}

      {:reply, reply, frame, cont} ->
        {:reply, reply, %{state | frame: frame}, cont}

      {:noreply, frame} ->
        {:noreply, %{state | frame: frame}}

      {:noreply, frame, cont} ->
        {:noreply, %{state | frame: frame}, cont}

      {:stop, reason, reply, frame} ->
        {:stop, reason, reply, %{state | frame: frame}}

      {:stop, reason, frame} ->
        {:stop, reason, %{state | frame: frame}}
    end
  end

  @impl GenServer
  def handle_cast({:notification, decoded, session_id, context}, state) when is_map(decoded) do
    with {:ok, {%Session{} = session, state}} <-
           maybe_attach_session(session_id, context, state) do
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

  def handle_cast({:response, decoded, _session_id, _context}, state) when is_map(decoded) do
    cond do
      Message.is_response(decoded) and server_request?(decoded["id"], state) ->
        handle_server_request_response(decoded, state)

      Message.is_error(decoded) and server_request?(decoded["id"], state) ->
        handle_server_request_error(decoded, state)

      true ->
        Logging.server_event(
          "unexpected_response",
          %{message: decoded},
          level: :warning
        )

        {:noreply, state}
    end
  end

  def handle_cast(request, %{module: module} = state) do
    case module.handle_cast(request, state.frame) do
      {:noreply, frame} -> {:noreply, %{state | frame: frame}}
      {:noreply, frame, cont} -> {:noreply, %{state | frame: frame}, cont}
      {:stop, reason, frame} -> {:stop, reason, %{state | frame: frame}}
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
        Logging.server_event("session_terminated", %{
          session_id: session_id,
          reason: reason
        })

        sessions = Map.delete(state.sessions, session_id)
        state = cancel_session_expiry(session_id, state)
        frame = state.frame

        frame =
          if frame.private[:session_id] == session_id,
            do: Frame.clear_session(frame),
            else: frame

        {:noreply, %{state | sessions: sessions, frame: frame}}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:send_notification, method, params}, state) do
    with {:ok, notification} <- encode_notification(method, params),
         :ok <- send_to_transport(state.transport, notification) do
      {:noreply, state}
    else
      {:error, err} ->
        Logging.server_event("failed_send_notification", %{method: method, error: err}, level: :error)

        {:noreply, state}
    end
  end

  def handle_info({:session_expired, session_id}, state) do
    if Map.get(state.sessions, session_id) do
      Logging.server_event("session_expired", %{session_id: session_id})
      SessionSupervisor.close_session(state.registry, state.module, session_id)
      {:noreply, %{state | sessions: Map.delete(state.sessions, session_id)}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:send_sampling_request, params, timeout}, state) do
    request_id = ID.generate_request_id()
    handle_sampling_request_send(request_id, params, timeout, state)
  end

  def handle_info({:sampling_request_timeout, request_id}, state) do
    handle_sampling_timeout(request_id, state)
  end

  def handle_info({:send_roots_request, timeout}, state) do
    request_id = ID.generate_request_id()
    handle_roots_request_send(request_id, timeout, state)
  end

  def handle_info({:roots_request_timeout, request_id}, state) do
    handle_roots_timeout(request_id, state)
  end

  def handle_info(event, %{module: module} = state) do
    if Hermes.exported?(module, :handle_info, 2) do
      case module.handle_info(event, state.frame) do
        {:noreply, frame} -> {:noreply, %{state | frame: frame}}
        {:noreply, frame, cont} -> {:noreply, %{state | frame: frame}, cont}
        {:stop, reason, frame} -> {:stop, reason, %{state | frame: frame}}
      end
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def terminate(reason, %{module: module, server_info: server_info} = state) do
    Logging.server_event("terminating", %{reason: reason, server_info: server_info})

    Telemetry.execute(
      Telemetry.event_server_terminate(),
      %{system_time: System.system_time()},
      %{reason: reason, server_info: server_info}
    )

    if Hermes.exported?(module, :terminate, 2) do
      module.terminate(reason, state.frame)
    else
      :ok
    end
  end

  @impl GenServer
  def format_status(status) do
    Map.new(status, fn
      {:state, state} ->
        {:state, format_state(state)}

      {:message, {:request, decoded, session_id, _ctx}} ->
        {:message, {:request, decoded, session_id}}

      {:message, {:notification, decoded, session_id, _ctx}} ->
        {:message, {:notification, decoded, session_id}}

      {:message, {:response, decoded, session_id, _ctx}} ->
        {:message, {:response, decoded, session_id}}

      other ->
        other
    end)
  end

  @non_printable_keys ~w(transport sessions expiry_timers server_requests)a

  defp format_state(state) do
    pending_requests = format_pending_requests(state.server_requests)
    sessions = format_sessions(state.sessions)

    state
    |> Map.reject(fn {k, _} -> k in @non_printable_keys end)
    |> Map.merge(%{
      transport: state.transport[:layer],
      pending_requests: pending_requests,
      active_sessions: sessions
    })
  end

  defp format_pending_requests(requests) do
    Enum.map(requests, fn {id, req} ->
      %{id: id, method: req[:method], session_id: req[:session_id]}
    end)
  end

  defp format_sessions(sessions) do
    sessions
    |> Enum.map(fn {_id, {name, _}} -> Session.get(name) end)
    |> Enum.reject(&is_nil/1)
  end

  defguardp is_server_initialized(decoded, session)
            when Message.is_initialize_lifecycle(decoded) or
                   Session.is_initialized(session)

  defp handle_single_request(decoded, session, state) do
    cond do
      Message.is_response(decoded) and server_request?(decoded["id"], state) ->
        handle_server_request_response(decoded, state)

      Message.is_error(decoded) and server_request?(decoded["id"], state) ->
        handle_server_request_error(decoded, state)

      Message.is_ping(decoded) ->
        handle_server_ping(decoded, state)

      not is_server_initialized(decoded, session) ->
        handle_server_not_initialized(state)

      Message.is_request(decoded) ->
        handle_request(decoded, session, state)

      true ->
        handle_invalid_request(state)
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

  defp handle_invalid_request(state) do
    error =
      Error.protocol(:invalid_request, %{
        message: "Expected request but got different message type"
      })

    {:reply, {:error, error}, state}
  end

  # Request handling

  defp handle_request(%{"params" => params} = request, session, state) when Message.is_initialize(request) do
    %{
      "clientInfo" => client_info,
      "capabilities" => client_capabilities,
      "protocolVersion" => requested_version
    } = params

    protocol_version =
      negotiate_protocol_version(state.supported_versions, requested_version)

    :ok =
      Session.update_from_initialization(
        session.name,
        protocol_version,
        client_info,
        client_capabilities
      )

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

  defp handle_request(%{"id" => request_id, "method" => method} = request, session, state) do
    Logging.server_event("handling_request", %{id: request_id, method: method})

    :ok = Session.track_request(session.name, request_id, method)

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

  defp handle_notification(%{"method" => "notifications/initialized"}, session, %{module: module} = state) do
    Logging.server_event("client_initialized", %{session_id: session.id})
    :ok = Session.mark_initialized(session.name)

    Logging.server_event("session_marked_initialized", %{
      session_id: session.id,
      initialized: true
    })

    frame = %{state.frame | initialized: true}

    {:ok, frame} =
      if Hermes.exported?(module, :init, 2),
        do: module.init(session.client_info, frame),
        else: {:ok, frame}

    {:noreply, %{state | frame: frame}}
  end

  defp handle_notification(%{"method" => "notifications/cancelled"} = notification, session, state) do
    params = notification["params"] || %{}
    request_id = params["requestId"]
    reason = Map.get(params, "reason", "cancelled")

    if Session.has_pending_request?(session.name, request_id) do
      request_info = Session.complete_request(session.name, request_id)

      Logging.server_event("request_cancelled", %{
        session_id: session.id,
        request_id: request_id,
        reason: reason,
        method: request_info[:method],
        duration_ms: System.system_time(:millisecond) - request_info[:started_at]
      })

      Telemetry.execute(
        Telemetry.event_server_notification(),
        %{system_time: System.system_time()},
        %{method: "cancelled", session_id: session.id, request_id: request_id}
      )

      {:noreply, state}
    else
      Logging.server_event("cancellation_for_unknown_request", %{
        session_id: session.id,
        request_id: request_id,
        reason: reason
      })

      {:noreply, state}
    end
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

  @spec maybe_attach_session(session_id :: String.t(), map, t) ::
          {:ok, {session :: Session.t(), t}}
  defp maybe_attach_session(session_id, context, %{sessions: sessions} = state) when is_map_key(sessions, session_id) do
    {session_name, _ref} = sessions[session_id]
    session = Session.get(session_name)
    state = reset_session_expiry(session_id, state)

    {:ok, {session, %{state | frame: populate_frame(state.frame, session, context, state)}}}
  end

  defp maybe_attach_session(session_id, context, %{sessions: sessions, registry: registry} = state) do
    session_name = registry.server_session(state.module, session_id)

    case SessionSupervisor.create_session(registry, state.module, session_id) do
      {:ok, pid} ->
        ref = Process.monitor(pid)

        state = %{
          state
          | sessions: Map.put(sessions, session_id, {session_name, ref})
        }

        state = reset_session_expiry(session_id, state)

        session = Session.get(session_name)

        {:ok, {session, %{state | frame: populate_frame(state.frame, session, context, state)}}}

      {:error, {:already_started, pid}} ->
        ref = Process.monitor(pid)

        state = %{
          state
          | sessions: Map.put(sessions, session_id, {session_name, ref})
        }

        state = reset_session_expiry(session_id, state)

        session = Session.get(session_name)

        {:ok, {session, %{state | frame: populate_frame(state.frame, session, context, state)}}}

      error ->
        error
    end
  end

  defp populate_frame(frame, %Session{} = session, context, state) do
    {assigns, context} = Map.pop(context, :assigns, %{})
    assigns = Map.merge(frame.assigns, assigns)

    frame
    |> Frame.put_transport(context)
    |> Frame.assign(assigns)
    |> Frame.put_private(%{
      session_id: session.id,
      client_info: session.client_info,
      client_capabilities: session.client_capabilities,
      protocol_version: session.protocol_version,
      server_registry: state.registry,
      server_module: state.module
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

  # Session expiry timer management

  defp schedule_session_expiry(session_id, timeout) do
    Process.send_after(self(), {:session_expired, session_id}, timeout)
  end

  defp reset_session_expiry(session_id, %{expiry_timers: timers, session_idle_timeout: timeout} = state) do
    if timer = Map.get(timers, session_id), do: Process.cancel_timer(timer)

    timer = schedule_session_expiry(session_id, timeout)
    %{state | expiry_timers: Map.put(timers, session_id, timer)}
  end

  defp cancel_session_expiry(session_id, %{expiry_timers: timers} = state) do
    if timer = Map.get(timers, session_id) do
      Process.cancel_timer(timer)
      %{state | expiry_timers: Map.delete(timers, session_id)}
    else
      state
    end
  end

  # Sampling request helpers

  defp handle_sampling_request_send(request_id, params, timeout, state) do
    timer_ref =
      Process.send_after(self(), {:sampling_request_timeout, request_id}, timeout)

    request_info = %{
      method: "sampling/createMessage",
      session_id: state.frame.private.session_id,
      timer_ref: timer_ref
    }

    state = put_in(state.server_requests[request_id], request_info)

    with :ok <- validate_client_capability(state, "sampling"),
         {:ok, request_data} <-
           encode_request("sampling/createMessage", params, request_id),
         :ok <- send_to_transport(state.transport, request_data) do
      Logging.server_event("sent_sampling_request", %{request_id: request_id})
      {:noreply, state}
    else
      {:error, error} ->
        Process.cancel_timer(timer_ref)

        state = %{
          state
          | server_requests: Map.delete(state.server_requests, request_id)
        }

        Logging.server_event(
          "failed_send_sampling_request",
          %{request_id: request_id, error: error},
          level: :error
        )

        {:noreply, state}
    end
  end

  defp validate_client_capability(%{frame: frame} = state, capability) do
    current_session = Frame.get_mcp_session_id(frame)

    session_name =
      Enum.find_value(state.sessions, fn {id, {name, _ref}} ->
        if id == current_session, do: name
      end)

    session = Session.get(session_name)

    if Map.has_key?(session.client_capabilities || %{}, capability) do
      :ok
    else
      {:error, "No session initialzied for sending sampling request"}
    end
  end

  defp handle_sampling_timeout(request_id, state) do
    case Map.pop(state.server_requests, request_id) do
      {nil, _} ->
        {:noreply, state}

      {_request_info, updated_requests} ->
        Logging.server_event("sampling_request_timeout", %{request_id: request_id}, level: :warning)

        {:noreply, %{state | server_requests: updated_requests}}
    end
  end

  defp encode_request(method, params, request_id) do
    request = %{
      "method" => method,
      "params" => params
    }

    Logging.message("outgoing", "request", request_id, request)
    Message.encode_request(request, request_id)
  end

  defp server_request?(request_id, %{server_requests: requests}) when is_binary(request_id) do
    Map.has_key?(requests, request_id)
  end

  defp server_request?(_, _), do: false

  defp handle_server_request_response(%{"id" => request_id, "result" => result}, state) do
    {request_info, updated_requests} = Map.pop(state.server_requests, request_id)
    Process.cancel_timer(request_info.timer_ref)

    state = %{state | server_requests: updated_requests}

    case request_info.method do
      "sampling/createMessage" ->
        handle_sampling(result, request_id, state)

      "roots/list" ->
        handle_roots(result["roots"] || [], request_id, state)

      _ ->
        {:noreply, state}
    end
  end

  defp handle_server_request_error(%{"id" => request_id, "error" => error}, state) do
    {request_info, updated_requests} = Map.pop(state.server_requests, request_id)
    Process.cancel_timer(request_info.timer_ref)

    state = %{state | server_requests: updated_requests}

    Logging.server_event(
      "server_request_error",
      %{
        request_id: request_id,
        method: request_info.method,
        error: error
      },
      level: :error
    )

    {:noreply, state}
  end

  defp handle_sampling(result, request_id, %{module: module, frame: frame} = state) do
    case module.handle_sampling(result, request_id, frame) do
      {:noreply, new_frame} ->
        {:noreply, %{state | frame: new_frame}}

      {:stop, reason, new_frame} ->
        {:stop, reason, %{state | frame: new_frame}}
    end
  end

  # Roots request helpers

  defp handle_roots_request_send(request_id, timeout, state) do
    timer_ref =
      Process.send_after(self(), {:roots_request_timeout, request_id}, timeout)

    request_info = %{
      id: request_id,
      method: "roots/list",
      session_id: state.frame.private.session_id,
      timer_ref: timer_ref
    }

    state = put_in(state.server_requests[request_id], request_info)

    with :ok <- validate_client_capability(state, "roots"),
         {:ok, request_data} <- encode_request("roots/list", %{}, request_id),
         :ok <- send_to_transport(state.transport, request_data) do
      Logging.server_event("sent_roots_request", %{request_id: request_id})
      {:noreply, state}
    else
      {:error, error} ->
        Process.cancel_timer(timer_ref)

        state = %{
          state
          | server_requests: Map.delete(state.server_requests, request_id)
        }

        Logging.server_event(
          "failed_send_roots_request",
          %{request_id: request_id, error: error},
          level: :error
        )

        {:noreply, state}
    end
  end

  defp handle_roots_timeout(request_id, state) when is_binary(request_id) do
    state.server_requests
    |> Map.pop(request_id)
    |> handle_roots_timeout(state)
  end

  defp handle_roots_timeout({nil, _}, state), do: {:noreply, state}

  defp handle_roots_timeout({%{id: request_id}, requests}, state) do
    with {:ok, notification} <-
           encode_notification("notifications/cancelled", %{
             "requestId" => request_id,
             "reason" => "timeout"
           }),
         :ok <- send_to_transport(state.transport, notification) do
      Logging.server_event(
        "roots_request_timeout_cancelled",
        %{request_id: request_id}
      )
    end

    Logging.server_event("roots_request_timeout", %{request_id: request_id}, level: :warning)

    {:noreply, %{state | server_requests: requests}}
  end

  defp handle_roots(roots, request_id, %{module: module} = state) do
    case module.handle_roots(roots, request_id, state.frame) do
      {:noreply, new_frame} ->
        {:noreply, %{state | frame: new_frame}}

      {:stop, reason, new_frame} ->
        {:stop, reason, %{state | frame: new_frame}}
    end
  end
end
