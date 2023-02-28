import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :torrex, TorrexWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "bRexDMF8nsmwetNvpoIDwyg07ZpLNCgQkVOhU++2N15awIz1Vr6vlLMMr2qD45l2",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
