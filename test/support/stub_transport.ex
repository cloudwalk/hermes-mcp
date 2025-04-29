defmodule Hermes.StubTransport do
  @moduledoc false
  @behaviour Hermes.Transport.Behaviour

  use Agent

  def start_link(opts) do
    Agent.start_link(fn -> %{messages: [], opts: opts} end, name: __MODULE__)
  end

  def send_message(_client, message) do
    Agent.update(__MODULE__, fn state ->
      %{state | messages: [message | state.messages]}
    end)

    :ok
  end

  def get_messages do
    Agent.get(__MODULE__, fn state -> state.messages end)
  end

  def clear_messages do
    Agent.update(__MODULE__, fn state -> %{state | messages: []} end)
  end

  def shutdown(_) do
    :ok
  end
end
