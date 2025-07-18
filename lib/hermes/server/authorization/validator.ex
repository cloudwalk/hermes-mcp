defmodule Hermes.Server.Authorization.Validator do
  @moduledoc """
  Behaviour for implementing OAuth 2.1 token validators.

  Token validators are responsible for verifying access tokens and extracting
  token information such as subject, audience, scopes, and expiration.

  ## Implementing a Custom Validator

      defmodule MyApp.CustomValidator do
        @behaviour Hermes.Server.Authorization.Validator
        
        @impl true
        def validate_token(token, config) do
          # Custom validation logic
          {:ok, %{
            sub: "user123",
            aud: "https://mcp.example.com",
            scope: "read write",
            exp: 1234567890,
            active: true
          }}
        end
      end
  """

  alias Hermes.Server.Authorization

  @doc """
  Validates an access token and returns token information.

  The validator should verify the token's signature, expiration, and other
  claims according to the chosen validation method (JWT, introspection, etc.).

  ## Return Values

  - `{:ok, token_info}` - Token is valid with extracted information
  - `{:error, :invalid_token}` - Token is invalid or malformed
  - `{:error, :expired_token}` - Token has expired
  - `{:error, reason}` - Other validation errors
  """
  @callback validate_token(token :: String.t(), config :: Authorization.config()) ::
              {:ok, Authorization.token_info()} | {:error, atom() | String.t()}

  @doc """
  Optional callback for refreshing tokens.

  If the validator supports token refresh, implement this callback to
  exchange a refresh token for a new access token.
  """
  @callback refresh_token(refresh_token :: String.t(), config :: Authorization.config()) ::
              {:ok, %{access_token: String.t(), expires_in: integer()}} | {:error, term()}

  @optional_callbacks refresh_token: 2
end
