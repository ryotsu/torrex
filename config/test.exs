import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :torrex, TorrexWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "2u1WO7LKVsEZJiynNbPpyzO7I0RpkhybCj+eLGpMjoU3rc9e+ce2cM2DfRZPGsGt",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
