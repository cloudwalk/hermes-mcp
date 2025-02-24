defmodule Hermes.Transport.Behaviour do
  @moduledoc """
  Defines the behavior that all transport implementations must follow.
  """

  @type message :: String.t()
  @type reason :: term()

  @callback start_link(keyword()) :: {:ok, pid()} | {:error, reason()}
  @callback send(pid(), message()) :: :ok | {:error, reason()}
  @callback subscribe(pid()) :: :ok | {:error, reason()}
end
