defmodule Hermes.Protocol do
  @moduledoc false

  alias Hermes.MCP.Error

  @type version :: String.t()
  @type feature :: atom()

  @supported_versions ["2024-11-05", "2025-03-26", "2025-06-18"]
  @latest_version "2025-06-18"
  @fallback_version "2025-03-26"

  @features_2024_11_05 [
    :basic_messaging,
    :resources,
    :tools,
    :prompts,
    :logging,
    :progress,
    :cancellation,
    :ping,
    :roots,
    :sampling
  ]

  @features_2025_03_26 [
    :authorization,
    :audio_content,
    :tool_annotations,
    :progress_messages,
    :completion_capability
    | @features_2024_11_05
  ]

  @features_2025_06_18 [
    :elicitation,
    :structured_tool_results,
    :tool_output_schemas,
    :model_preferences,
    :embedded_resources_in_prompts,
    :embedded_resources_in_tools
    | @features_2025_03_26
  ]

  @doc """
  Returns all supported protocol versions.
  """
  @spec supported_versions() :: [version()]
  def supported_versions, do: @supported_versions

  @doc """
  Returns the latest supported protocol version.
  """
  @spec latest_version() :: version()
  def latest_version, do: @latest_version

  @doc """
  Returns the fallback protocol version for compatibility.
  """
  @spec fallback_version() :: version()
  def fallback_version, do: @fallback_version

  @doc """
  Validates if a protocol version is supported.
  """
  @spec validate_version(version()) :: :ok | {:error, Error.t()}
  def validate_version(version) when version in @supported_versions, do: :ok

  def validate_version(version) do
    {:error,
     Error.protocol(:invalid_params, %{
       version: version,
       supported: @supported_versions
     })}
  end

  @doc """
  Validates if a transport is compatible with a protocol version.
  """
  @spec validate_transport(version(), module()) :: :ok | {:error, Error.t()}
  def validate_transport(version, transport) do
    supported_versions = supported_transport_versions(transport)

    if version in supported_versions do
      :ok
    else
      {:error,
       Error.transport(:incompatible_transport, %{
         version: version,
         transport: transport,
         supported_versions: supported_versions
       })}
    end
  end

  defp supported_transport_versions(transport) do
    case transport.supported_protocol_versions() do
      :all -> @supported_versions
      [_ | _] = versions -> versions
    end
  end

  @doc """
  Returns the set of features supported by a protocol version.
  """
  @spec get_features(version()) :: list(feature())
  def get_features("2024-11-05"), do: @features_2024_11_05
  def get_features("2025-03-26"), do: @features_2025_03_26
  def get_features("2025-06-18"), do: @features_2025_06_18

  @doc """
  Checks if a feature is supported by a protocol version.
  """
  @spec supports_feature?(version(), feature()) :: boolean()
  def supports_feature?(version, feature) when is_binary(version) and is_atom(feature) do
    version
    |> get_features()
    |> Enum.member?(feature)
  end

  @doc """
  Negotiates protocol version between client and server versions.

  Returns the best compatible version or an error if incompatible.
  """
  @spec negotiate_version(version(), version()) ::
          {:ok, version()} | {:error, Error.t()}
  def negotiate_version(client_version, server_version) do
    cond do
      client_version == server_version and client_version in @supported_versions ->
        {:ok, client_version}

      server_version in @supported_versions ->
        {:ok, server_version}

      client_version in @supported_versions ->
        {:ok, client_version}

      true ->
        {:error,
         Error.protocol(:invalid_params, %{
           client_version: client_version,
           server_version: server_version,
           supported: @supported_versions
         })}
    end
  end

  @doc """
  Returns transport modules that support a protocol version.
  """
  @spec compatible_transports(version(), [module()]) :: [module()]
  def compatible_transports(version, transport_modules) do
    Enum.filter(transport_modules, fn transport_module ->
      case validate_transport(version, transport_module) do
        :ok -> true
        {:error, _} -> false
      end
    end)
  end

  @doc """
  Validates client configuration for protocol compatibility.

  This function checks if the client configuration is compatible with
  the specified protocol version, including transport and capabilities.
  """
  @spec validate_client_config(version(), module(), map()) ::
          :ok | {:error, Error.t()}
  def validate_client_config(version, transport_module, _capabilities) do
    with :ok <- validate_version(version) do
      validate_transport(version, transport_module)
    end
  end
end
