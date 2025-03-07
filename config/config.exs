import Config

config :logger, :default_formatter,
  format: "[$level] $message $metadata\n",
  metadata: [:module, :mcp_client, :mcp_transport]
