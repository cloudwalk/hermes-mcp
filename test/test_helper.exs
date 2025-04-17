ExUnit.start()

defmodule Hermes.MockTransportImpl do
  @moduledoc false
  @behaviour Hermes.Transport.Behaviour

  @impl true
  def start_link(_opts), do: {:ok, self()}

  @impl true
  def send_message(_, _), do: :ok

  @impl true
  def shutdown(_), do: :ok
end

defmodule Hermes.SlowMockTransportImpl do
  @moduledoc """
  A mock transport implementation that simulates a transport which is slower than the default
  gen server timeout (5s)
  """
  @behaviour Hermes.Transport.Behaviour

  @impl true
  def start_link(_opts), do: {:ok, self()}

  @impl true
  def send_message(_pid, _message) do
    # Simulate a slow transport by sleeping
    Process.sleep(6_000)
    :ok
  end

  @impl true
  def shutdown(_pid), do: :ok
end


Mox.defmock(Hermes.MockTransport, for: Hermes.Transport.Behaviour)
Mox.defmock(Hermes.SlowMockTransport, for: Hermes.Transport.Behaviour)

defmodule StubClient do
  @moduledoc false
  use GenServer

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok, []}
  end

  def get_messages do
    GenServer.call(__MODULE__, :get_messages)
  end

  def clear_messages do
    GenServer.call(__MODULE__, :clear_messages)
  end

  def handle_call(:get_messages, _from, messages) do
    {:reply, Enum.reverse(messages), messages}
  end

  def handle_call(:clear_messages, _from, _messages) do
    {:reply, :ok, []}
  end

  def handle_cast(msg, messages), do: handle_info(msg, messages)

  def handle_info(:initialize, messages), do: {:noreply, messages}

  def handle_info({:response, data}, messages) do
    {:noreply, [data | messages]}
  end
end
