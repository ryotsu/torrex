defmodule Torrex.Supervisor do
  @moduledoc """
  Main supervisor for Torrex
  """

  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init([peer_id, tcp_port, udp_port]) do
    children = [
      supervisor(Torrex.Torrent.Pool, []),
      supervisor(Torrex.Tracker.Pool, [peer_id, tcp_port, udp_port]),
      worker(Torrex.TorrentTable, [peer_id]),
      worker(Torrex.UPnP, [tcp_port])
      # worker(Torrex.Listner, [tcp_port])
    ]

    supervise(children, strategy: :one_for_all)
  end
end
