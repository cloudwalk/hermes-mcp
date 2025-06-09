import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :echo, EchoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "/DS+/sht01z+3iswMfL6gKCQ/nXTQOnFdiLq56hjfZufBLfgJw8pZJr0/NNUAbsx",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
