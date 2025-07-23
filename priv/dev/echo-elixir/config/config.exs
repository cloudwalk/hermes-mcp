import Config

config :echo,
  generators: [timestamp_type: :utc_datetime],
  mcp_transport: :sse

config :echo, EchoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: EchoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Echo.PubSub,
  live_view: [signing_salt: "LpHUsU88"]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, JSON

config :mime, :types, %{
  "text/event-stream" => ["event-stream"]
}

import_config "#{config_env()}.exs"
