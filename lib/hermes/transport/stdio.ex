defmodule Hermes.Transport.STDIO do
  @moduledoc """
  A transport implementation that uses standard input/output.
  """

  use GenServer

  import Peri

  alias Hermes.Transport.Behaviour, as: Transport

  @behaviour Transport

  @type params_t :: Enumerable.t(option)
  @type option ::
          {:command, Path.t()}
          | {:args, list(String.t()) | nil}
          | {:env, map() | nil}
          | {:cwd, Path.t() | nil}
          | Supervisor.init_option()

  defschema :options_schema, %{
    name: {:atom, {:default, __MODULE__}},
    client: {:required, :atom},
    command: {:required, :string},
    args: {{:list, :string}, {:default, nil}},
    env: {:map, {:default, nil}},
    cwd: {:string, {:default, nil}}
  }

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
  @spec start_link(params_t) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    opts = options_schema!(opts)
    GenServer.start_link(__MODULE__, Map.new(opts), name: opts[:name])
  end

  @impl Transport
  def send_message(pid \\ __MODULE__, message) when is_binary(message) do
    GenServer.call(pid, {:send, message})
  end

  @impl GenServer
  def init(%{} = opts) do
    state = Map.merge(opts, %{port: nil, ref: nil})

    {:ok, state, {:continue, :spawn}}
  end

  @impl GenServer
  def handle_continue(:spawn, state) do
    if cmd = System.find_executable(state.command) do
      port = spawn_port(cmd, state)
      ref = Port.monitor(port)

      {:noreply, %{state | port: port, ref: ref}}
    else
      {:stop, {:error, "Command not found: #{state.command}"}, state}
    end
  end

  @impl GenServer
  def handle_call({:send, message}, _, %{port: port} = state) when is_port(port) do
    result = if Port.command(port, message), do: :ok, else: {:error, :port_not_connected}
    {:reply, result, state}
  end

  def handle_call({:send, _message}, _, state) do
    {:reply, {:error, :port_not_connected}, state}
  end

  @impl GenServer
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    IO.puts("Received data: #{inspect(data)}")
    Process.send(state.client, {:response, data}, [:noconnect])
    {:noreply, state}
  end

  def handle_info({port, :closed}, %{port: port} = state) do
    IO.puts("Port closed")
    {:stop, :normal, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    IO.puts("Port exited with status: #{status}")
    {:stop, status, state}
  end

  def handle_info({:DOWN, ref, :port, port, reason}, %{ref: ref, port: port} = state) do
    IO.puts("Port monitor DOWN: #{inspect(reason)}")
    {:stop, reason, state}
  end

  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    IO.puts("Port exited: #{inspect(reason)}")
    {:stop, reason, state}
  end

  @impl GenServer
  def handle_cast(:close_port, %{port: port} = state) do
    Port.close(port)
    {:stop, :normal, state}
  end

  defp spawn_port(cmd, state) do
    default_env = get_default_env()
    env = if is_nil(state.env), do: default_env, else: Map.merge(default_env, state.env)
    env = normalize_env_for_erlang(env)

    opts =
      [:binary]
      |> then(&if is_nil(state.args), do: &1, else: Enum.concat(&1, args: state.args))
      |> then(&if is_nil(state.env), do: &1, else: Enum.concat(&1, env: env))
      |> then(&if is_nil(state.cwd), do: &1, else: Enum.concat(&1, cd: state.cwd))

    Port.open({:spawn_executable, cmd}, opts)
  end

  defp get_default_env do
    default_env = if :os.type() == {:win32, :nt}, do: @win32_default_env, else: @unix_default_env

    System.get_env()
    |> Enum.filter(fn {k, _} -> Enum.member?(default_env, k) end)
    # remove functions, for security risks
    |> Enum.reject(fn {_, v} -> String.starts_with?(v, "()") end)
    |> Enum.into(%{})
  end

  defp normalize_env_for_erlang(%{} = env) do
    env
    |> Map.new(fn {k, v} -> {to_charlist(k), to_charlist(v)} end)
    |> Enum.into([])
  end
end
