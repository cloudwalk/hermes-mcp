defmodule Hermes.Transport.STDIO do
  @moduledoc """
  A transport implementation that uses standard input/output.
  """

  use GenServer

  alias Hermes.Transport.Behaviour, as: Transport

  @behaviour Transport

  @type t :: %__MODULE__{stdin: IO.Stream.t(), stdout: IO.Stream.t(), subscribers: [pid()]}

  defstruct [:stdin, :stdout, :subscribers]

  @type params_t :: Enumerable.t(option)
  @type option ::
          {:command, Path.t()}
          | {:args, list(String.t()) | nil}
          | {:env, map() | nil}
          | {:cwd, Path.t() | nil}

  @schema %{
    command: {:required, :string},
    args: {:array, :string},
    env: {:map, :string},
    cwd: :string
  }

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
  end
end
