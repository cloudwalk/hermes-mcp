defmodule Hermes.Transport.STDIO do
  @moduledoc """
  A transport implementation that uses standard input/output.
  """

  use GenServer

  alias Hermes.Transport.Behaviour, as: Transport

  @behaviour Transport

  @type t :: %__MODULE__{port: Port.t(), params: params_t}

  defstruct [:port, :params]

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
  def send(pid, _) do
    IO.puts("Sending message to #{inspect(pid)}")
  end

  @impl Transport
  def subscribe(pid) do
    IO.puts("Subscribed to #{inspect(pid)}")
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

      port =
        Port.open({:spawn_executable, cmd}, [
          :binary,
          {:args, params.args},
          {:env, Map.to_list(env)}
          # {:cd, params.cwd}
        ])

      Process.monitor(port)

      {:ok, %{state | port: port, env: env}}
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

  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    IO.puts("Port exited: #{inspect(reason)}")
    {:stop, reason, state}
  end

  def get_default_env do
    default_env = if :os.type() == {:win32, :nt}, do: @win32_default_env, else: @unix_default_env

    System.get_env()
    |> Enum.filter(fn {k, _} -> Enum.member?(default_env, k) end)
    # remove functions, for security risks
    |> Enum.reject(fn {_, v} -> String.starts_with?(v, "()") end)
    |> Enum.into(%{})
  end
end
