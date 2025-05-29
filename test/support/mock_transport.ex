defmodule Hermes.MockTransportImpl do
  @moduledoc false
  @behaviour Hermes.Transport.Behaviour

  @impl true
  def start_link(_opts), do: {:ok, self()}

  @impl true
  def send_message(_, _), do: :ok

  @impl true
  def shutdown(_), do: :ok

  @impl true
  def supported_protocol_versions do
    ["2024-11-05", "2025-03-26"]
  end
end
