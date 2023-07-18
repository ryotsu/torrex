defmodule Torrex.Torrent.Pool do
  @moduledoc false

  alias Torrex.Torrent.Supervisor, as: TorrentSupervisor

  @spec add_torrent(binary, String.t()) :: Supervisor.on_start_child()
  def add_torrent(info_hash, name) do
    torrent = %{start: {TorrentSupervisor, :start_link, [info_hash, name]}, id: info_hash}

    DynamicSupervisor.start_child(__MODULE__, torrent)
  end
end
