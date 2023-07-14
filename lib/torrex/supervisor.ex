defmodule Torrex.Supervisor do
  @moduledoc """
  Main supervisor for Torrex
  """

  use Supervisor

  @spec start_link(list) :: Supervisor.on_start()
  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init([peer_id, tcp_port, udp_port]) do
    children = [
      {DynamicSupervisor, name: Torrex.Torrent.Pool, strategy: :one_for_one},
      # Torrex.Torrent.Pool,
      {Torrex.Tracker.Pool, [peer_id, tcp_port, udp_port]},
      {Torrex.TorrentTable, [peer_id]},
      {Torrex.Listener, [tcp_port]}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
