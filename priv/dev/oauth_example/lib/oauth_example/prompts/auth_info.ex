defmodule OauthExample.Prompts.AuthInfo do
  @moduledoc "Generate prompts about OAuth authentication status and requirements"

  use Hermes.Server.Component, type: :prompt

  alias Hermes.Server.Frame
  alias Hermes.Server.Response

  schema do
    %{
      detail_level: {{:enum, ["basic", "detailed", "technical"]}, {:default, "basic"}}
    }
  end

  @impl true
  def get_messages(%{detail_level: level}, frame) do
    auth_status = if Frame.authenticated?(frame), do: "authenticated", else: "not authenticated"

    message =
      case {auth_status, level} do
        {"authenticated", "basic"} ->
          """
          You are currently authenticated as: #{Frame.get_auth_subject(frame)}
          Available scopes: #{Frame.get_auth_scopes(frame) || "none"}
          """

        {"authenticated", "detailed"} ->
          auth = Frame.get_auth(frame)

          """
          Authentication Status: ✓ Authenticated

          User ID: #{auth.sub}
          Client ID: #{auth[:client_id] || "N/A"}
          Scopes: #{auth.scope || "none"}
          Token Active: #{auth.active}

          You have access to:
          - Read operations: #{if auth.scope && String.contains?(auth.scope, "read"), do: "✓", else: "✗"}
          - Write operations: #{if auth.scope && String.contains?(auth.scope, "write"), do: "✓", else: "✗"}
          - Admin operations: #{if auth.scope && String.contains?(auth.scope, "admin"), do: "✓", else: "✗"}
          """

        {"authenticated", "technical"} ->
          auth = Frame.get_auth(frame)

          """
          OAuth 2.1 Authentication Details:

          Token Claims:
          - Subject (sub): #{auth.sub}
          - Audience (aud): #{inspect(auth.aud)}
          - Scopes: #{auth.scope || "none"}
          - Expiration: #{format_unix_time(auth[:exp])}
          - Issued At: #{format_unix_time(auth[:iat])}
          - Client ID: #{auth[:client_id] || "N/A"}
          - Active: #{auth.active}

          Authorization Server: https://auth.example.com
          Resource Server: oauth://profile
          """

        {"not authenticated", _} ->
          """
          You are not currently authenticated.

          To access protected resources and tools, you need to authenticate with a valid OAuth token.

          Available demo tokens for testing:
          - "demo_read_token" - Read-only access
          - "demo_write_token" - Read and write access  
          - "demo_admin_token" - Full admin access

          Include the token in your Authorization header:
          Authorization: Bearer <token>
          """
      end

    {:reply, Response.user_message(Response.prompt(), message), frame}
  end

  defp format_unix_time(nil), do: "N/A"

  defp format_unix_time(timestamp) when is_integer(timestamp) do
    timestamp
    |> DateTime.from_unix!()
    |> DateTime.to_iso8601()
  end
end
