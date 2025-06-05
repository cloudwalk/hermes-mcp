defmodule Hermes.Server.ConfigurationError do
  @moduledoc """
  Raised when required MCP server configuration is missing or invalid.

  The MCP specification requires servers to provide:
  - `name`: A human-readable name for the server
  - `version`: The server's version string

  ## Examples

      # This will raise an error - missing required options
      defmodule BadServer do
        use Hermes.Server  # Raises Hermes.Server.ConfigurationError
      end
      
      # This is correct
      defmodule GoodServer do
        use Hermes.Server,
          name: "My Server",
          version: "1.0.0"
      end
  """

  defexception [:message, :module, :missing_key]

  @impl true
  def exception(opts) do
    module = Keyword.fetch!(opts, :module)
    missing_key = Keyword.fetch!(opts, :missing_key)

    message = build_message(module, missing_key)

    %__MODULE__{
      message: message,
      module: module,
      missing_key: missing_key
    }
  end

  defp build_message(module, :name) do
    """
    MCP server configuration error in #{inspect(module)}

    Missing required option: :name

    The MCP specification requires all servers to provide a name.
    Please add the :name option to your use statement:

        defmodule #{inspect(module)} do
          use Hermes.Server,
            name: "Your Server Name",    # <-- Add this
            version: "1.0.0"
        end

    The name should be a human-readable string that identifies your server.
    """
  end

  defp build_message(module, :version) do
    """
    MCP server configuration error in #{inspect(module)}

    Missing required option: :version

    The MCP specification requires all servers to provide a version.
    Please add the :version option to your use statement:

        defmodule #{inspect(module)} do
          use Hermes.Server,
            name: "Your Server",
            version: "1.0.0"              # <-- Add this
        end

    The version should follow semantic versioning (e.g., "1.0.0", "2.1.3").
    """
  end

  defp build_message(module, :both) do
    """
    MCP server configuration error in #{inspect(module)}

    Missing required options: :name and :version

    The MCP specification requires all servers to provide both name and version.
    Please add these options to your use statement:

        defmodule #{inspect(module)} do
          use Hermes.Server,
            name: "Your Server Name",     # <-- Add this
            version: "1.0.0"              # <-- Add this
        end

    Example:
        defmodule Calculator do
          use Hermes.Server,
            name: "Calculator Server",
            version: "1.0.0"
        end
    """
  end

  defp build_message(module, key) do
    """
    MCP server configuration error in #{inspect(module)}

    Invalid or missing required option: #{inspect(key)}
    """
  end
end
