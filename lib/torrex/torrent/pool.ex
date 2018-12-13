defmodule Torrex.Torrent.Pool do
  use Supervisor

  alias Torrex.Torrent.Supervisor, as: TorrentSupervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def add_torrent(info_hash, name) do
    torrent = supervisor(TorrentSupervisor, [info_hash, name], id: info_hash, restart: :transient)

    Supervisor.start_child(__MODULE__, torrent)
  end

  def init([]) do
    children = []

    supervise(children, strategy: :one_for_one)
  end
end
