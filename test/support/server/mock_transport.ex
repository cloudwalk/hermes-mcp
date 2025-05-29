defmodule Hermes.Server.MockTransport do
  @moduledoc """
  Mock transport for testing server functionality.
  Records sent messages for verification in tests using Agent.
  """

  @behaviour Hermes.Transport.Behaviour

  use Agent

  @impl true
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  def get_messages do
    Agent.get(__MODULE__, & &1)
  end

  def clear_messages do
    Agent.update(__MODULE__, fn _ -> [] end)
  end

  @impl true
  def send_message(_, message) do
    Agent.update(__MODULE__, fn messages -> [message | messages] end)
  end

  @impl true
  def shutdown(_), do: :ok

  @impl true
  def supported_protocol_versions do
    ["2024-11-05", "2025-03-26"]
  end
end
