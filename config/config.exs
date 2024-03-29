# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configures the endpoint
config :torrex, TorrexWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: TorrexWeb.ErrorHTML, json: TorrexWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Torrex.PubSub,
  live_view: [signing_salt: "NIbyR+dB"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.2.7",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :mime, :types, %{
  "application/x-bittorrent" => ["torrent"]
}

config :torrex,
  peer_id: :crypto.strong_rand_bytes(20) |> Base.url_encode64() |> binary_part(0, 20),
  tcp_port: 6885,
  udp_port: Enum.random(21_001..22_000),
  download_dir: System.get_env("HOME") |> Path.join("Downloads")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
