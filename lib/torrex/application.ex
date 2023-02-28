defmodule Torrex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    peer_id = Application.get_env(:torrex, :peer_id)
    tcp_port = Application.get_env(:torrex, :tcp_port)
    udp_port = Application.get_env(:torrex, :udp_port)

    children = [
      # Start the Telemetry supervisor
      TorrexWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Torrex.PubSub},
      # Start the Endpoint (http/https)
      TorrexWeb.Endpoint,
      # Start a worker by calling: Torrex.Worker.start_link(arg)
      # {Torrex.Worker, arg}
      {Torrex.Supervisor, [peer_id, tcp_port, udp_port]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Torrex.ApplicationSupervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TorrexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
