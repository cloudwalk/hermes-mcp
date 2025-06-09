import Config

config :echo, EchoWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "TfLxrJKWMpgSv68tfCDQc26jz0tZ4Hlz+kB3WgDhh1LiMov+JlOV6cx+LvDetMSX",
  watchers: []

# Enable dev routes for dashboard and mailbox
config :echo, dev_routes: true

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
