defmodule Hermes.Transport.Behaviour do
  @moduledoc """
  Defines the behavior that all transport implementations must follow.
  """

  alias Hermes.MCP.Error

  @type t :: GenServer.server()
  @typedoc "The JSON-RPC message encoded"
  @type message :: String.t()
  @type reason :: term() | Error.t()

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback send_message(t(), message()) :: :ok | {:error, reason()}
  @callback shutdown(t()) :: :ok | {:error, reason()}
end
