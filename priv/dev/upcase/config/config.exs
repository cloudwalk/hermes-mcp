import Config

config :hermes_mcp, log: true

if config_env() == :dev do
  config :logger, level: :debug
end
