defmodule Hermes.Transport.STDIO do
  @moduledoc """
  A transport implementation that uses standard input/output.

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

  @type params_t :: Enumerable.t(option)

  @typedoc """
  The options for the STDIO transport.

  - `:command` - The command to run, it will be searched in the system's PATH.
  - `:args` - The arguments to pass to the command, as a list of strings.
  - `:env` - The extra environment variables to set for the command, as a map.
  - `:cwd` - The working directory for the command.
  - `:client` - The client to send the messages to, respecting the `GenServer` "Name Registration" section

  And any other `GenServer` init option.
  """
  @type option ::
          {:command, Path.t()}
          | {:args, list(String.t()) | nil}
          | {:env, map() | nil}
          | {:cwd, Path.t() | nil}
          | {:client, GenServer.server()}
          | GenServer.option()

  defschema(:options_schema, %{
    name: {{:custom, &Hermes.genserver_name/1}, {:default, __MODULE__}},
    client: {:required, Hermes.get_schema(:process_name)},
    command: {:required, :string},
    args: {{:list, :string}, {:default, nil}},
    env: {:map, {:default, nil}},
    cwd: {:string, {:default, nil}}
  })

  @win32_default_env [
    "APPDATA",
    "HOMEDRIVE",
    "HOMEPATH",
    "LOCALAPPDATA",
    "PATH",
    "PROCESSOR_ARCHITECTURE",
    "SYSTEMDRIVE",
    "SYSTEMROOT",
    "TEMP",
    "USERNAME",
    "USERPROFILE"
  ]
  @unix_default_env ["HOME", "LOGNAME", "PATH", "SHELL", "TERM", "USER"]

  @impl Transport
  @spec start_link(params_t) :: GenServer.on_start()
  def start_link(opts \\ []) do
    opts = options_schema!(opts)
    GenServer.start_link(__MODULE__, Map.new(opts), name: opts[:name])
  end

  @impl Transport
  def send_message(pid \\ __MODULE__, message, _opts \\ []) when is_binary(message) do
    GenServer.call(pid, {:send, message})
  end

  @impl Transport
  def shutdown(pid \\ __MODULE__) do
    GenServer.cast(pid, :close_port)
  end

  @impl Transport
  def supported_protocol_versions, do: :all

  @impl GenServer
  def init(%{} = opts) do
    state = Map.merge(opts, %{port: nil, ref: nil})

    metadata = %{
      transport: :stdio,
      command: opts.command,
      args: opts.args,
      client: opts.client
    }

    Telemetry.execute(
      Telemetry.event_transport_init(),
      %{system_time: System.system_time()},
      metadata
    )

    {:ok, state, {:continue, :spawn}}
  end

  @impl GenServer
  def handle_continue(:spawn, state) do
    if cmd = System.find_executable(state.command) do
      port = spawn_port(cmd, state)
      ref = Port.monitor(port)

      GenServer.cast(state.client, :initialize)
      {:noreply, %{state | port: port, ref: ref}}
    else
      {:stop, {:error, "Command not found: #{state.command}"}, state}
    end
  end

  @impl GenServer
  def handle_call({:send, message}, _, %{port: port} = state) when is_port(port) do
    metadata = %{
      transport: :stdio,
      message_size: byte_size(message),
      command: state.command
    }

    Telemetry.execute(
      Telemetry.event_transport_send(),
      %{system_time: System.system_time()},
      metadata
    )

    Port.command(port, message)
    {:reply, :ok, state}
  end

  def handle_call({:send, message}, _, state) do
    Telemetry.execute(
      Telemetry.event_transport_error(),
      %{system_time: System.system_time()},
      %{
        transport: :stdio,
        error: :port_not_connected,
        message_size: byte_size(message)
      }
    )

    {:reply, {:error, :port_not_connected}, state}
  end

  @impl GenServer
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    Logging.transport_event("stdio_received", String.slice(data, 0, 100))

    Telemetry.execute(
      Telemetry.event_transport_receive(),
      %{system_time: System.system_time()},
      %{
        transport: :stdio,
        message_size: byte_size(data)
      }
    )

    GenServer.cast(state.client, {:response, data})
    {:noreply, state}
  end

  def handle_info({port, :closed}, %{port: port} = state) do
    Logging.transport_event(
      "stdio_closed",
      "Connection closed, transport will restart",
      level: :warning
    )

    Telemetry.execute(
      Telemetry.event_transport_disconnect(),
      %{system_time: System.system_time()},
      %{
        transport: :stdio,
        reason: :normal
      }
    )

    {:stop, :normal, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logging.transport_event("stdio_exit", %{status: status}, level: :warning)

    Telemetry.execute(
      Telemetry.event_transport_error(),
      %{system_time: System.system_time()},
      %{
        transport: :stdio,
        error: :exit_status,
        status: status
      }
    )

    {:stop, status, state}
  end

  def handle_info({:DOWN, ref, :port, port, reason}, %{ref: ref, port: port} = state) do
    Logging.transport_event("stdio_down", %{reason: reason}, level: :error)

    Telemetry.execute(
      Telemetry.event_transport_error(),
      %{system_time: System.system_time()},
      %{
        transport: :stdio,
        error: :port_down,
        reason: reason
      }
    )

    {:stop, reason, state}
  end

  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Logging.transport_event("stdio_exit", %{reason: reason}, level: :error)

    Telemetry.execute(
      Telemetry.event_transport_error(),
      %{system_time: System.system_time()},
      %{
        transport: :stdio,
        error: :port_exit,
        reason: reason
      }
    )

    {:stop, reason, state}
  end

  @impl GenServer
  def handle_cast(:close_port, %{port: port} = state) do
    Telemetry.execute(
      Telemetry.event_transport_disconnect(),
      %{system_time: System.system_time()},
      %{
        transport: :stdio,
        reason: :client_closed
      }
    )

    Port.close(port)
    {:stop, :normal, state}
  end

  @impl GenServer
  def terminate(reason, _state) do
    Telemetry.execute(
      Telemetry.event_transport_terminate(),
      %{system_time: System.system_time()},
      %{
        transport: :stdio,
        reason: reason
      }
    )

    :ok
  end

  defp spawn_port(cmd, state) do
    default_env = get_default_env()

    env =
      if is_nil(state.env), do: default_env, else: Map.merge(default_env, state.env)

    env = normalize_env_for_erlang(env)

    opts =
      [:binary]
      |> then(&if is_nil(state.args), do: &1, else: Enum.concat(&1, args: state.args))
      |> then(&if is_nil(state.env), do: &1, else: Enum.concat(&1, env: env))
      |> then(&if is_nil(state.cwd), do: &1, else: Enum.concat(&1, cd: state.cwd))

    Port.open({:spawn_executable, cmd}, opts)
  end

  defp get_default_env do
    default_env =
      if :os.type() == {:win32, :nt}, do: @win32_default_env, else: @unix_default_env

    System.get_env()
    |> Enum.filter(fn {k, _} -> Enum.member?(default_env, k) end)
    # remove functions, for security risks
    |> Enum.reject(fn {_, v} -> String.starts_with?(v, "()") end)
    |> Map.new()
  end

  defp normalize_env_for_erlang(%{} = env) do
    env
    |> Map.new(fn {k, v} -> {to_charlist(k), to_charlist(v)} end)
    |> Enum.to_list()
  end
end
