defmodule Torrex do
  @moduledoc false

  use Application

  def start(_type, _args) do
    peer_id = Application.get_env(:torrex, :peer_id)
    tcp_port = Application.get_env(:torrex, :tcp_port)
    udp_port = Application.get_env(:torrex, :udp_port)

    Torrex.Supervisor.start_link(peer_id, tcp_port, udp_port)
  end

  defdelegate add_torrent(path), to: Torrex.TorrentTable
end
