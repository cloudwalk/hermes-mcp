defmodule Hermes.Server.Authorization.IntrospectionValidator do
  @moduledoc """
  OAuth 2.0 Token Introspection validator for authorization.

  Validates tokens by calling an OAuth 2.0 Token Introspection endpoint (RFC 7662).
  This is useful when tokens are opaque (not JWTs) or when you need server-side
  token validation with real-time revocation checking.

  ## Configuration

      auth_config = [
        authorization_servers: ["https://auth.example.com"],
        realm: "my-app-realm",
        validator: Hermes.Server.Authorization.IntrospectionValidator,
        
        # Required
        token_introspection_endpoint: "https://auth.example.com/oauth/introspect",
        
        # Optional - for authenticating to the introspection endpoint
        introspection_client_id: "my-mcp-server",
        introspection_client_secret: "client-secret"
      ]

  ## Features

  - Real-time token validation
  - Support for opaque tokens
  - Immediate revocation detection
  - Client authentication support (Basic Auth)

  ## Token Info

  Returns token information based on the introspection response:

      %{
        sub: "user123",              # Subject from introspection
        aud: "https://api.example",  # Audience claim
        scope: "read write",         # OAuth scopes
        exp: 1234567890,            # Expiration timestamp
        iat: 1234567800,            # Issued at timestamp
        client_id: "app123",        # OAuth client ID
        active: true                # From introspection response
      }

  ## Security Note

  The introspection endpoint should be protected and only accessible by
  authorized resource servers. Use client credentials when required by
  your authorization server.
  """

  @behaviour Hermes.Server.Authorization.Validator

  @impl true
  def validate_token(token, config) do
    with {:ok, response} <- introspect_token(token, config) do
      parse_introspection_response(response)
    end
  end

  @doc """
  Introspects a token using the OAuth 2.0 Token Introspection endpoint.
  """
  def introspect_token(token, %{token_introspection_endpoint: endpoint} = config) when is_binary(endpoint) do
    body =
      URI.encode_query(%{
        "token" => token,
        "token_type_hint" => "access_token"
      })

    headers = build_introspection_headers(config)

    request = Hermes.HTTP.build(:post, endpoint, headers, body)

    with {:ok, %Finch.Response{status: 200, body: resp_body}} <- Finch.request(request, Hermes.Finch),
         {:ok, json} <- JSON.decode(resp_body) do
      {:ok, json}
    else
      {:ok, %Finch.Response{status: status}} ->
        {:error, {:introspection_failed, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def introspect_token(_, _), do: {:error, :no_introspection_endpoint}

  defp build_introspection_headers(config) do
    base_headers = %{
      "content-type" => "application/x-www-form-urlencoded",
      "accept" => "application/json"
    }

    # Add client authentication if configured
    case config do
      %{introspection_client_id: client_id, introspection_client_secret: secret} ->
        auth = Base.encode64("#{client_id}:#{secret}")
        Map.put(base_headers, "authorization", "Basic #{auth}")

      _ ->
        base_headers
    end
  end

  defp parse_introspection_response(%{"active" => false}) do
    {:error, :invalid_token}
  end

  defp parse_introspection_response(%{"active" => true} = response) do
    token_info = %{
      sub: response["sub"],
      aud: response["aud"],
      scope: response["scope"],
      exp: response["exp"],
      iat: response["iat"],
      client_id: response["client_id"],
      active: true
    }

    # Validate expiration if present
    case token_info do
      %{exp: exp} when is_integer(exp) ->
        now = System.system_time(:second)

        if now < exp do
          {:ok, token_info}
        else
          {:error, :expired_token}
        end

      _ ->
        {:ok, token_info}
    end
  end

  defp parse_introspection_response(_) do
    {:error, :invalid_introspection_response}
  end
end
