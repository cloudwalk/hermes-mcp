if Code.ensure_loaded?(:gun) do
  defmodule Hermes.Transport.WebSocket do
    @moduledoc """
    A transport implementation that uses WebSockets for bidirectional communication
    with the MCP server.

    > ## Notes {: .info}
    >
    > For initialization and setup, check our [Installation & Setup](./installation.html) and
    > the [Transport options](./transport_options.html) guides for reference.
    """

    @behaviour Hermes.Transport.Behaviour

    use GenServer
    use Hermes.Logging

    import Peri

    alias Hermes.Telemetry
    alias Hermes.Transport.Behaviour, as: Transport

    @type t :: GenServer.server()

    @typedoc """
    The options for the MCP server.

    - `:base_url` - The base URL of the MCP server (e.g. http://localhost:8000) (required).
    - `:base_path` - The base path of the MCP server (e.g. /mcp).
    - `:ws_path` - The path to the WebSocket endpoint (e.g. /mcp/ws) (default `:base_path` + `/ws`).
    """
    @type server ::
            Enumerable.t(
              {:base_url, String.t()}
              | {:base_path, String.t()}
              | {:ws_path, String.t()}
            )

    @type params_t :: Enumerable.t(option)
    @typedoc """
    The options for the WebSocket transport.

    - `:name` - The name of the transport process, respecting the `GenServer` "Name Registration" section.
    - `:client` - The client to send the messages to, respecting the `GenServer` "Name Registration" section.
    - `:server` - The server configuration.
    - `:headers` - The headers to send with the HTTP requests.
    - `:transport_opts` - The underlying transport options to pass to Gun.
    """
    @type option ::
            {:name, GenServer.name()}
            | {:client, GenServer.server()}
            | {:server, server}
            | {:headers, map()}
            | {:transport_opts, keyword}
            | GenServer.option()

    defschema(:options_schema, %{
      name: {{:custom, &Hermes.genserver_name/1}, {:default, __MODULE__}},
      client:
        {:required,
         {:oneof,
          [
            {:custom, &Hermes.genserver_name/1},
            :pid,
            {:tuple, [:atom, :any]}
          ]}},
      server: [
        base_url: {:required, {:string, {:transform, &URI.new!/1}}},
        base_path: {:string, {:default, "/"}},
        ws_path: {:string, {:default, "/ws"}}
      ],
      headers: {:map, {:default, %{}}},
      transport_opts: {:any, {:default, []}}
    })

    @impl Transport
    @spec start_link(params_t) :: GenServer.on_start()
    def start_link(opts \\ []) do
      opts = options_schema!(opts)
      GenServer.start_link(__MODULE__, Map.new(opts), name: opts[:name])
    end

    @impl Transport
    def send_message(pid, message, _opts \\ []) when is_binary(message) do
      GenServer.call(pid, {:send, message})
    end

    @impl Transport
    def shutdown(pid) do
      GenServer.cast(pid, :close_connection)
    end

    @impl Transport
    def supported_protocol_versions, do: :all

    @impl GenServer
    def init(%{} = opts) do
      server_url = URI.append_path(opts.server[:base_url], opts.server[:base_path])
      ws_url = URI.append_path(server_url, opts.server[:ws_path])

      state = Map.merge(opts, %{ws_url: ws_url, gun_pid: nil, stream_ref: nil})

      metadata = %{
        transport: :websocket,
        ws_url: URI.to_string(ws_url),
        client: opts.client
      }

      Telemetry.execute(
        Telemetry.event_transport_init(),
        %{system_time: System.system_time()},
        metadata
      )

      {:ok, state, {:continue, :connect}}
    end

    @impl GenServer
    def handle_continue(:connect, state) do
      uri = URI.parse(state.ws_url)
      protocol = if uri.scheme == "https", do: :https, else: :http
      port = uri.port || if protocol == :https, do: 443, else: 80

      state =
        Map.merge(state, %{
          host: uri.host,
          port: port,
          protocol: protocol
        })

      metadata = %{
        transport: :websocket,
        ws_url: URI.to_string(state.ws_url),
        host: uri.host,
        port: port,
        protocol: protocol
      }

      Telemetry.execute(
        Telemetry.event_transport_connect(),
        %{system_time: System.system_time()},
        metadata
      )

      gun_opts = %{
        protocols: [:http],
        http_opts: %{keepalive: :infinity}
      }

      gun_opts = Map.merge(gun_opts, Map.new(state.transport_opts))

      case open_connection(uri.host, port, gun_opts) do
        {:ok, gun_pid} ->
          handle_connection_established(gun_pid, uri, state)

        {:error, reason} ->
          Logging.transport_event("gun_open_failed", %{reason: reason}, level: :error)

          Telemetry.execute(
            Telemetry.event_transport_error(),
            %{system_time: System.system_time()},
            Map.put(metadata, :error, reason)
          )

          {:stop, {:gun_open_failed, reason}, state}
      end
    end

    defp open_connection(host, port, gun_opts) do
      :gun.open(to_charlist(host), port, gun_opts)
    end

    defp handle_connection_established(gun_pid, uri, state) do
      Logging.transport_event("gun_opened", %{host: uri.host, port: uri.port})
      Process.monitor(gun_pid)

      case :gun.await_up(gun_pid, 5000) do
        {:ok, _protocol} ->
          initiate_websocket_upgrade(gun_pid, uri, state)

        {:error, reason} ->
          Logging.transport_event("gun_await_up_failed", %{reason: reason}, level: :error)

          {:stop, {:gun_await_up_failed, reason}, state}
      end
    end

    defp initiate_websocket_upgrade(gun_pid, uri, state) do
      headers =
        state.headers
        |> Map.to_list()
        |> Enum.map(fn {k, v} -> {to_charlist(k), to_charlist(v)} end)

      path = uri.path || "/"
      path = if uri.query, do: "#{path}?#{uri.query}", else: path
      stream_ref = :gun.ws_upgrade(gun_pid, to_charlist(path), headers)
      Logging.transport_event("ws_upgrade_requested", %{path: path})

      {:noreply, %{state | gun_pid: gun_pid, stream_ref: stream_ref}}
    end

    @impl GenServer
    def handle_call({:send, message}, _from, %{gun_pid: pid, stream_ref: stream_ref} = state)
        when not is_nil(pid) and not is_nil(stream_ref) do
      metadata = %{
        transport: :websocket,
        message_size: byte_size(message)
      }

      Telemetry.execute(
        Telemetry.event_transport_send(),
        %{system_time: System.system_time()},
        metadata
      )

      :ok = :gun.ws_send(pid, stream_ref, {:text, message})
      Logging.transport_event("ws_message_sent", String.slice(message, 0, 100))
      {:reply, :ok, state}
    rescue
      e ->
        Logging.transport_event("ws_send_failed", %{error: Exception.message(e)}, level: :error)

        {:reply, {:error, :send_failed}, state}
    end

    def handle_call({:send, _message}, _from, state) do
      {:reply, {:error, :not_connected}, state}
    end

    @impl GenServer
    def handle_info(
          {:gun_ws, pid, stream_ref, {:text, data}},
          %{gun_pid: pid, stream_ref: stream_ref, client: client} = state
        ) do
      Logging.transport_event("ws_message_received", String.slice(data, 0, 100))

      Telemetry.execute(
        Telemetry.event_transport_receive(),
        %{system_time: System.system_time()},
        %{
          transport: :websocket,
          message_size: byte_size(data)
        }
      )

      GenServer.cast(client, {:response, data})
      {:noreply, state}
    end

    def handle_info({:gun_ws, pid, stream_ref, :close}, %{gun_pid: pid, stream_ref: stream_ref} = state) do
      Logging.transport_event("ws_closed", "Connection closed by server", level: :warning)

      Telemetry.execute(
        Telemetry.event_transport_disconnect(),
        %{system_time: System.system_time()},
        %{
          transport: :websocket,
          reason: :normal_close
        }
      )

      {:stop, :normal, state}
    end

    def handle_info({:gun_ws, pid, stream_ref, {:close, code, reason}}, %{gun_pid: pid, stream_ref: stream_ref} = state) do
      Logging.transport_event("ws_closed", %{code: code, reason: reason}, level: :warning)

      Telemetry.execute(
        Telemetry.event_transport_disconnect(),
        %{system_time: System.system_time()},
        %{
          transport: :websocket,
          code: code,
          reason: reason
        }
      )

      {:stop, {:ws_closed, code, reason}, state}
    end

    def handle_info(
          {:gun_upgrade, pid, stream_ref, ["websocket"], _headers},
          %{gun_pid: pid, stream_ref: stream_ref, client: client} = state
        ) do
      Logging.transport_event(
        "ws_upgrade_success",
        "WebSocket connection established"
      )

      GenServer.cast(client, :initialize)
      {:noreply, state}
    end

    def handle_info({:gun_response, pid, stream_ref, _, status, headers}, %{gun_pid: pid, stream_ref: stream_ref} = state) do
      Logging.transport_event(
        "ws_upgrade_rejected",
        %{status: status, headers: headers},
        level: :error
      )

      {:stop, {:ws_upgrade_rejected, status}, state}
    end

    def handle_info({:gun_error, pid, stream_ref, reason}, %{gun_pid: pid, stream_ref: stream_ref} = state) do
      Logging.transport_event("gun_error", %{reason: reason}, level: :error)
      {:stop, {:gun_error, reason}, state}
    end

    def handle_info({:DOWN, _ref, :process, pid, reason}, %{gun_pid: pid} = state) do
      Logging.transport_event("gun_down", %{reason: reason}, level: :error)

      Telemetry.execute(
        Telemetry.event_transport_error(),
        %{system_time: System.system_time()},
        %{
          transport: :websocket,
          error: :connection_down,
          reason: reason
        }
      )

      {:stop, {:gun_down, reason}, state}
    end

    def handle_info(msg, state) do
      Logging.transport_event("unexpected_message", %{message: msg})
      {:noreply, state}
    end

    @impl GenServer
    def handle_cast(:close_connection, %{gun_pid: pid} = state) when not is_nil(pid) do
      Telemetry.execute(
        Telemetry.event_transport_disconnect(),
        %{system_time: System.system_time()},
        %{
          transport: :websocket,
          reason: :client_closed
        }
      )

      :ok = :gun.close(pid)
      {:stop, :normal, state}
    end

    def handle_cast(:close_connection, state) do
      Telemetry.execute(
        Telemetry.event_transport_disconnect(),
        %{system_time: System.system_time()},
        %{
          transport: :websocket,
          reason: :client_closed_before_connected
        }
      )

      {:stop, :normal, state}
    end

    @impl GenServer
    def terminate(reason, %{gun_pid: pid} = _state) when not is_nil(pid) do
      Telemetry.execute(
        Telemetry.event_transport_terminate(),
        %{system_time: System.system_time()},
        %{
          transport: :websocket,
          reason: reason
        }
      )

      Telemetry.execute(
        Telemetry.event_transport_disconnect(),
        %{system_time: System.system_time()},
        %{
          transport: :websocket,
          reason: reason
        }
      )

      :gun.close(pid)
      :ok
    end

    def terminate(_reason, _state), do: :ok
  end
end
