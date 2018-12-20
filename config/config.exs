# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

# You can configure your application as:
#
#     config :torrex, key: :value
#
# and access this configuration in your application as:
#
#     Application.get_env(:torrex, :key)
#
# You can also configure a 3rd-party app:
#
#     config :logger, level: :info
#

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
#     import_config "#{Mix.env}.exs"

config :torrex,
  peer_id: :crypto.strong_rand_bytes(20) |> Base.url_encode64() |> binary_part(0, 20),
  tcp_port: 6885,
  udp_port: Enum.random(21_001..22_000),
  download_dir: System.get_env("HOME") |> Path.join("Downloads")

config :torrex, TorrexWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "RTrRiDVZy2ZFkbpWPXw2+eEmGP0FRDwEen1TkfmbNn++rYYFNaPGTHxn2gCMtZc+",
  render_errors: [view: TorrexWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Torrex.PubSub, adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :logger,
  truncate: :infinity

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
