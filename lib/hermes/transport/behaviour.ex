defmodule Hermes.Transport.Behaviour do
  @moduledoc """
  Defines the behavior that all transport implementations must follow.
  """

  @type t :: pid | module
  @type message :: String.t()
  @type reason :: term()

  @callback start_link(keyword()) :: Supervisor.on_start()
  @callback send_message(message()) :: :ok | {:error, reason()}
  @callback send_message(t(), message()) :: :ok | {:error, reason()}
  @callback shutdown(t()) :: :ok | {:error, reason()}

  @optional_callbacks send_message: 1
end
