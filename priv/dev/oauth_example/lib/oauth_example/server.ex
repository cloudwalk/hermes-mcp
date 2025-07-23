defmodule OauthExample.Server do
  use Hermes.Server,
    name: "oauth-example",
    version: "1.0.0",
    capabilities: [:tools, :resources, :prompts]

  component(OauthExample.Tools.SecureOperation)
  component(OauthExample.Resources.UserProfile)
  component(OauthExample.Prompts.AuthInfo)

  alias Hermes.Server.Frame

  @impl true
  def init(_client_info, frame) do
    if Frame.authenticated?(frame) do
      IO.puts("🔐 Authenticated client connected!")
      IO.puts("   Subject: #{Frame.get_auth_subject(frame)}")
      IO.puts("   Scopes: #{Frame.get_auth_scopes(frame)}")
    else
      IO.puts("🔓 Client connected without authentication")
    end

    {:ok, frame}
  end

  @impl true
  def handle_info(:demo_notification, frame) do
    if Frame.authenticated?(frame) do
      send_log_message(frame, :info, "Hello authenticated user: #{Frame.get_auth_subject(frame)}")
    else
      send_log_message(frame, :warning, "Authentication required for full features")
    end

    {:noreply, frame}
  end
end
