ExUnit.start()

defmodule Hermes.MockTransportImpl do
  @behaviour Hermes.Transport.Behaviour

  @impl true
  def start_link(_opts), do: {:ok, self()}

  @impl true
  def send_message(_ \\ nil, _), do: :ok
end

Mox.defmock(Hermes.MockTransport, for: Hermes.Transport.Behaviour)
