defmodule Hermes.Server.Authorization do
  @moduledoc false

  import Peri

  @type token :: String.t()
  @type authorization_server :: String.t()

  @type token_info :: %{
          sub: String.t(),
          aud: String.t() | list(String.t()) | nil,
          scope: String.t() | nil,
          exp: integer() | nil,
          iat: integer() | nil,
          client_id: String.t() | nil,
          active: boolean()
        }

  @type config :: %{
          authorization_servers: list(authorization_server()),
          resource_metadata_url: String.t() | nil,
          realm: String.t(),
          scopes_supported: list(String.t()) | nil,
          validator: module() | nil
        }

  @type www_authenticate_params :: %{
          realm: String.t(),
          resource_metadata: String.t() | nil,
          authorization_servers: list(String.t()) | nil,
          scope: String.t() | nil,
          error: String.t() | nil,
          error_description: String.t() | nil,
          error_uri: String.t() | nil
        }

  defschema(:config_schema, %{
    authorization_servers: {:required, {:list, :string}},
    resource_metadata_url: {:string, {:default, nil}},
    realm: {:string, {:default, "mcp-server"}},
    scopes_supported: {{:list, :string}, {:default, []}},
    validator: {:atom, {:default, nil}}
  })

  @doc """
  Parses and validates authorization configuration.
  """
  @spec parse_config!(keyword() | map()) :: config()
  def parse_config!(opts), do: config_schema!(Map.new(opts))

  @doc """
  Builds a WWW-Authenticate header value for 401 responses per RFC 9728.

  The header format follows:
  WWW-Authenticate: Bearer realm="example",
                          resource_metadata="https://server.example.com/.well-known/oauth-protected-resource",
                          authorization_servers="https://as.example.com https://as2.example.com"
  """
  @spec build_www_authenticate_header(config(), keyword()) :: String.t()
  def build_www_authenticate_header(config, opts \\ []) do
    params = build_www_authenticate_params(config, opts)

    param_string =
      params
      |> Enum.map(&format_www_authenticate_param/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    "Bearer " <> param_string
  end

  @doc """
  Builds Protected Resource Metadata response per RFC 9728.

  This should be served at /.well-known/oauth-protected-resource
  """
  @spec build_resource_metadata(config()) :: map()
  def build_resource_metadata(config) do
    %{
      "resource" => get_canonical_server_uri(),
      "authorization_servers" => config.authorization_servers,
      "scopes_supported" => config.scopes_supported,
      "bearer_methods_supported" => ["header"],
      "resource_documentation" => "https://modelcontextprotocol.io",
      "resource_signing_alg_values_supported" => ["RS256", "ES256"]
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Validates that a token is intended for this resource server.

  Checks the audience claim to ensure the token was issued for this specific
  MCP server, preventing token confusion attacks.
  """
  @spec validate_audience(token_info(), String.t()) :: :ok | {:error, :invalid_audience}
  def validate_audience(%{aud: aud}, expected_audience) when is_binary(aud) do
    if aud == expected_audience, do: :ok, else: {:error, :invalid_audience}
  end

  def validate_audience(%{aud: aud_list}, expected_audience) when is_list(aud_list) do
    if expected_audience in aud_list, do: :ok, else: {:error, :invalid_audience}
  end

  def validate_audience(_, _), do: {:error, :invalid_audience}

  @doc """
  Checks if a token has expired based on the exp claim.
  """
  @spec validate_expiry(token_info()) :: :ok | {:error, :expired_token}
  def validate_expiry(%{exp: exp}) when is_integer(exp) do
    now = System.system_time(:second)
    if now < exp, do: :ok, else: {:error, :expired_token}
  end

  def validate_expiry(_), do: :ok

  @doc """
  Validates token has required scopes.
  """
  @spec validate_scopes(token_info(), list(String.t())) :: :ok | {:error, :insufficient_scope}
  def validate_scopes(%{scope: token_scope}, required_scopes) when is_binary(token_scope) do
    token_scopes = String.split(token_scope, " ", trim: true)

    if Enum.all?(required_scopes, &(&1 in token_scopes)) do
      :ok
    else
      {:error, :insufficient_scope}
    end
  end

  def validate_scopes(_, []), do: :ok
  def validate_scopes(_, _), do: {:error, :insufficient_scope}

  # Private functions

  defp build_www_authenticate_params(config, opts) do
    %{
      realm: config.realm,
      resource_metadata: config.resource_metadata_url,
      authorization_servers: Enum.join(config.authorization_servers, " "),
      scope: Keyword.get(opts, :scope),
      error: Keyword.get(opts, :error),
      error_description: Keyword.get(opts, :error_description),
      error_uri: Keyword.get(opts, :error_uri)
    }
  end

  defp format_www_authenticate_param({:realm, value}) when is_binary(value) do
    ~s(realm="#{escape_quotes(value)}")
  end

  defp format_www_authenticate_param({:resource_metadata, value}) when is_binary(value) do
    ~s(resource_metadata="#{escape_quotes(value)}")
  end

  defp format_www_authenticate_param({:authorization_servers, value}) when is_binary(value) and value != "" do
    ~s(authorization_servers="#{escape_quotes(value)}")
  end

  defp format_www_authenticate_param({:scope, value}) when is_binary(value) do
    ~s(scope="#{escape_quotes(value)}")
  end

  defp format_www_authenticate_param({:error, value}) when is_binary(value) do
    ~s(error="#{escape_quotes(value)}")
  end

  defp format_www_authenticate_param({:error_description, value}) when is_binary(value) do
    ~s(error_description="#{escape_quotes(value)}")
  end

  defp format_www_authenticate_param({:error_uri, value}) when is_binary(value) do
    ~s(error_uri="#{escape_quotes(value)}")
  end

  defp format_www_authenticate_param(_), do: nil

  defp escape_quotes(string) do
    String.replace(string, ~s("), ~s(\\"))
  end

  defp get_canonical_server_uri do
    # This should be configured based on the actual server URL
    # For now, return a placeholder that should be overridden
    System.get_env("MCP_SERVER_URI", "https://mcp.example.com")
  end
end
