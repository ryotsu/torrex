defmodule Torrex.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    peer_id = Application.get_env(:torrex, :peer_id)
    tcp_port = Application.get_env(:torrex, :tcp_port)
    udp_port = Application.get_env(:torrex, :udp_port)

    children = [
      TorrexWeb.Endpoint,
      {Torrex.Supervisor, [peer_id, tcp_port, udp_port]}
    ]

    opts = [strategy: :one_for_one, name: Torrex.ApplicationSupervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    TorrexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

defmodule Torrex do
  defdelegate add_torrent(path), to: Torrex.TorrentTable
end
