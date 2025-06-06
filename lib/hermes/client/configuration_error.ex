defmodule Hermes.Client.ConfigurationError do
  @moduledoc """
  Raised when client configuration is invalid or incomplete.
  """

  defexception [:message]

  @impl true
  def exception(opts) do
    module = opts[:module]
    missing_key = opts[:missing_key]

    message =
      case missing_key do
        :name ->
          "Client module #{inspect(module)} is missing required :name option"

        :version ->
          "Client module #{inspect(module)} is missing required :version option"

        :both ->
          "Client module #{inspect(module)} is missing both :name and :version options"

        _ ->
          "Client module #{inspect(module)} has invalid configuration"
      end

    %__MODULE__{message: message}
  end
end
