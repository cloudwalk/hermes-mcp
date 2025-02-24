defmodule Hermes.Transport.STDIO do
  @moduledoc """
  A transport implementation that uses standard input/output.
  """

  use GenServer

  alias Hermes.Transport.Behaviour, as: Transport

  @behaviour Transport

  @type t :: %__MODULE__{port: port(), params: params_t, ref: reference()}

  defstruct [:port, :params, :ref]

  @type params_t :: Enumerable.t(option)
  @type option ::
          {:command, Path.t()}
          | {:args, list(String.t()) | nil}
          | {:env, map() | nil}
          | {:cwd, Path.t() | nil}

  @schema %{
    command: {:required, :string},
    args: {{:list, :string}, {:default, []}},
    env: {:map, {:default, %{}}},
    cwd: {:string, {:default, ""}}
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
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl Transport
  def send(pid, %{} = message) do
    GenServer.call(pid, {:send, message})
  end

  @impl Transport
  def subscribe(pid) do
    IO.puts("Subscribed to #{inspect(pid)}")
  end

  @impl Transport
  def notify(pid, notification) do
    GenServer.call(pid, {:notify, notification})
  end

  def shutdown(pid) do
    GenServer.cast(pid, :close_port)
  end

  @impl GenServer
  def init(opts) do
    changeset = Peri.to_changeset!(@schema, Map.new(opts))

    case Ecto.Changeset.apply_action(changeset, :parse) do
      {:ok, params} -> {:ok, %__MODULE__{params: params}, {:continue, :spawn}}
      {:error, changeset} -> {:stop, {:error, changeset}}
    end
  end

  @impl GenServer
  def handle_continue(:spawn, %{params: params} = state) do
    if cmd = System.find_executable(params.command) do
      env = Map.merge(get_default_env(), params.env)
      port = spawn_port(cmd, state)
      ref = Port.monitor(port)

      {:noreply, %{state | port: port, ref: ref, params: %{params | env: env}}}
    else
      {:stop, {:error, "Command not found: #{params.command}"}, state}
    end
  end

  @impl GenServer
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    IO.puts("Received data: #{inspect(data)}")
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

  defp spawn_port(cmd, %{params: params}) do
    env = Map.merge(get_default_env(), params.env) |> normalize_env_for_erlang()

    opts =
      [:binary]
      |> then(&if not Enum.empty?(params.args), do: Enum.concat(&1, args: params.args), else: &1)
      |> then(&if not Enum.empty?(env), do: Enum.concat(&1, env: env), else: &1)
      |> then(&if params.cwd != "", do: Enum.concat(&1, cd: params.cwd), else: &1)

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
