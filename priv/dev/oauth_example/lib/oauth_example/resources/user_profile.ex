defmodule OauthExample.Resources.UserProfile do
  @moduledoc "Resource that returns authenticated user's profile information"

  use Hermes.Server.Component,
    type: :resource,
    uri: "oauth://profile",
    mime_type: "application/json"

  alias Hermes.Server.Frame
  alias Hermes.Server.Response

  @impl true
  def read(_params, frame) do
    case Frame.get_auth(frame) do
      nil ->
        error =
          Hermes.MCP.Error.execution("unauthorized", %{
            message: "Authentication required to view profile"
          })

        {:error, error, frame}

      auth_info ->
        profile = %{
          user_id: auth_info.sub,
          authenticated: true,
          scopes: String.split(auth_info.scope || "", " ", trim: true),
          client_id: auth_info[:client_id],
          token_expires_at: format_expiry(auth_info[:exp]),
          metadata: %{
            retrieved_at: DateTime.utc_now() |> DateTime.to_iso8601()
          }
        }

        {:reply, Response.json(Response.resource(), profile), frame}
    end
  end

  defp format_expiry(nil), do: nil

  defp format_expiry(exp) when is_integer(exp) do
    exp
    |> DateTime.from_unix!()
    |> DateTime.to_iso8601()
  end
end
