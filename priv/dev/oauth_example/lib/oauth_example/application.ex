defmodule OauthExample.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # OAuth configuration
    auth_config = [
      authorization_servers: ["https://auth.example.com"],
      realm: "oauth-example-realm",
      scopes_supported: ["read", "write", "admin"],
      validator: OauthExample.MockValidator
    ]

    children = [
      Hermes.Server.Registry,
      {OauthExample.Server, transport: {:streamable_http, authorization: auth_config}},
      {Bandit, plug: OauthExample.Router, port: 4001}
    ]

    opts = [strategy: :one_for_one, name: OauthExample.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
