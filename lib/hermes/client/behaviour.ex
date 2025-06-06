defmodule Hermes.Client.Behaviour do
  @moduledoc """
  Behaviour definition for MCP client implementations.

  This behaviour defines callbacks that client modules must implement
  to provide configuration and customization.
  """

  @doc """
  Returns the client information including name and version.

  This information is sent to the server during initialization.
  """
  @callback client_info(state :: term()) :: %{String.t() => String.t()}

  @doc """
  Returns the client capabilities.

  These capabilities are advertised to the server during initialization.
  The return value should be a map with capability names as keys.

  ## Example

      def client_capabilities(_state) do
        %{
          "roots" => %{"listChanged" => true},
          "sampling" => %{}
        }
      end
  """
  @callback client_capabilities(state :: term()) :: map()

  @doc """
  Returns the preferred protocol version.

  This should be one of the supported MCP protocol versions.
  Defaults to the latest version if not specified.
  """
  @callback protocol_version(state :: term()) :: String.t()
end
