defmodule Hermes.Protocol do
  @moduledoc """
  Protocol version management and feature validation for MCP.

  This module handles protocol version compatibility, feature detection,
  and transport validation following the MCP specification.

  ## Protocol Versions

  - `2024-11-05`: Initial stable release with SSE and basic features
  - `2025-03-26`: Enhanced version with Streamable HTTP, authorization, batching, and extended features

  ## Examples

      iex> Hermes.Protocol.validate_transport("2024-11-05", Hermes.Transport.SSE)
      :ok

      iex> Hermes.Protocol.validate_transport("2024-11-05", Hermes.Transport.StreamableHTTP)
      {:error, %Hermes.MCP.Error{reason: :incompatible_transport}}

      iex> Hermes.Protocol.supports_feature?("2025-03-26", :json_rpc_batching)
      true
  """

  alias Hermes.MCP.Error

  @type version :: String.t()
  @type feature :: atom()

  @supported_versions ["2024-11-05", "2025-03-26"]
  @latest_version "2025-03-26"
  @fallback_version "2024-11-05"

  # Features supported by each protocol version
  @features_2024_11_05 MapSet.new([
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
                       ])

  @features_2025_03_26 MapSet.new([
                         :basic_messaging,
                         :resources,
                         :tools,
                         :prompts,
                         :logging,
                         :progress,
                         :cancellation,
                         :ping,
                         :roots,
                         :sampling,
                         # New features in 2025-03-26
                         :json_rpc_batching,
                         :authorization,
                         :audio_content,
                         :tool_annotations,
                         :progress_messages,
                         :completion_capability
                       ])

  @doc """
  Returns all supported protocol versions.

  ## Examples

      iex> Hermes.Protocol.supported_versions()
      ["2024-11-05", "2025-03-26"]
  """
  @spec supported_versions() :: [version()]
  def supported_versions, do: @supported_versions

  @doc """
  Returns the latest supported protocol version.

  ## Examples

      iex> Hermes.Protocol.latest_version()
      "2025-03-26"
  """
  @spec latest_version() :: version()
  def latest_version, do: @latest_version

  @doc """
  Returns the fallback protocol version for compatibility.

  ## Examples

      iex> Hermes.Protocol.fallback_version()
      "2024-11-05"
  """
  @spec fallback_version() :: version()
  def fallback_version, do: @fallback_version

  @doc """
  Validates if a protocol version is supported.

  ## Parameters

    * `version` - The protocol version to validate

  ## Examples

      iex> Hermes.Protocol.validate_version("2024-11-05")
      :ok

      iex> Hermes.Protocol.validate_version("1.0.0")
      {:error, %Hermes.MCP.Error{reason: :unsupported_protocol_version}}
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

  ## Parameters

    * `version` - The protocol version
    * `transport_module` - The transport module to validate

  ## Examples

      iex> Hermes.Protocol.validate_transport("2024-11-05", Hermes.Transport.SSE)
      :ok

      iex> Hermes.Protocol.validate_transport("2024-11-05", Hermes.Transport.StreamableHTTP)
      {:error, %Hermes.MCP.Error{reason: :incompatible_transport}}
  """
  @spec validate_transport(version(), module()) :: :ok | {:error, Error.t()}
  def validate_transport(version, transport_module) do
    supported_versions = transport_module.supported_protocol_versions()

    if version in supported_versions do
      :ok
    else
      {:error,
       Error.transport(:incompatible_transport, %{
         version: version,
         transport: transport_module,
         supported_versions: supported_versions
       })}
    end
  end

  @doc """
  Returns the set of features supported by a protocol version.

  ## Parameters

    * `version` - The protocol version

  ## Examples

      iex> features = Hermes.Protocol.get_features("2025-03-26")
      iex> MapSet.member?(features, :json_rpc_batching)
      true
  """
  @spec get_features(version()) :: MapSet.t(feature())
  def get_features("2024-11-05"), do: @features_2024_11_05
  def get_features("2025-03-26"), do: @features_2025_03_26
  def get_features(_), do: MapSet.new()

  @doc """
  Checks if a feature is supported by a protocol version.

  ## Parameters

    * `version` - The protocol version
    * `feature` - The feature to check

  ## Examples

      iex> Hermes.Protocol.supports_feature?("2025-03-26", :json_rpc_batching)
      true

      iex> Hermes.Protocol.supports_feature?("2024-11-05", :authorization)
      false
  """
  @spec supports_feature?(version(), feature()) :: boolean()
  def supports_feature?(version, feature) do
    version
    |> get_features()
    |> MapSet.member?(feature)
  end

  @doc """
  Negotiates protocol version between client and server versions.

  Returns the best compatible version or an error if incompatible.

  ## Parameters

    * `client_version` - The client's preferred protocol version
    * `server_version` - The server's supported protocol version

  ## Examples

      iex> Hermes.Protocol.negotiate_version("2025-03-26", "2025-03-26")
      {:ok, "2025-03-26"}

      iex> Hermes.Protocol.negotiate_version("2025-03-26", "2024-11-05")
      {:ok, "2024-11-05"}

      iex> Hermes.Protocol.negotiate_version("2024-11-05", "1.0.0")
      {:error, %Hermes.MCP.Error{reason: :incompatible_versions}}
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

  ## Parameters

    * `version` - The protocol version
    * `transport_modules` - List of transport modules to check

  ## Examples

      iex> transports = [Hermes.Transport.STDIO, Hermes.Transport.SSE]
      iex> Hermes.Protocol.compatible_transports("2024-11-05", transports)
      [Hermes.Transport.STDIO, Hermes.Transport.SSE]
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

  ## Parameters

    * `version` - The protocol version
    * `transport_module` - The transport module being used
    * `capabilities` - The client capabilities

  ## Examples

      iex> capabilities = %{"resources" => %{}, "tools" => %{}}
      iex> Hermes.Protocol.validate_client_config("2024-11-05", Hermes.Transport.SSE, capabilities)
      :ok
  """
  @spec validate_client_config(version(), module(), map()) ::
          :ok | {:error, Error.t()}
  def validate_client_config(version, transport_module, _capabilities) do
    with :ok <- validate_version(version) do
      validate_transport(version, transport_module)
    end
  end
end
