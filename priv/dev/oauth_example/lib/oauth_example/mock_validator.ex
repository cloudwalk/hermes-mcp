defmodule OauthExample.MockValidator do
  @moduledoc """
  Mock token validator for demonstration purposes.

  In a real application, this would validate JWT tokens against a real
  authorization server or validate tokens using introspection.
  """

  @behaviour Hermes.Server.Authorization.Validator

  @impl true
  def validate_token(token, _config) do
    case token do
      # Demo tokens for testing
      "demo_read_token" ->
        {:ok,
         %{
           sub: "user_read_only",
           aud: "https://localhost:4001",
           scope: "read",
           exp: System.system_time(:second) + 3600,
           client_id: "demo_client",
           active: true
         }}

      "demo_write_token" ->
        {:ok,
         %{
           sub: "user_read_write",
           aud: "https://localhost:4001",
           scope: "read write",
           exp: System.system_time(:second) + 3600,
           client_id: "demo_client",
           active: true
         }}

      "demo_admin_token" ->
        {:ok,
         %{
           sub: "user_admin",
           aud: "https://localhost:4001",
           scope: "read write admin",
           exp: System.system_time(:second) + 3600,
           client_id: "admin_client",
           active: true
         }}

      "expired_token" ->
        {:error, :expired_token}

      _ ->
        {:error, :invalid_token}
    end
  end
end
