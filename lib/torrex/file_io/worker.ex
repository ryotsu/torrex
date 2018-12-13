defmodule Torrex.FileIO.Worker do
  @moduledoc """
  GenServer for file worker
  """

  use GenServer

  require Logger

  alias Torrex.TorrentTable
  alias Torrex.Torrent.Control, as: TorrentControl
  alias Torrex.FileIO.Utils, as: FileUtils

  def start_link(info_hash, control_pid) do
    GenServer.start_link(__MODULE__, [info_hash, control_pid])
  end

  def init([info_hash, control_pid]) do
    {:ok, torrent} = TorrentTable.get_torrent(info_hash)

    state = %{
      files: torrent.files,
      pieces: torrent.pieces,
      info_hash: info_hash,
      control_pid: control_pid,
      open_files: []
    }

    {:ok, state}
  end

  def save_piece(pid, index, piece) do
    GenServer.cast(pid, {:save_piece, index, piece})
  end

  def handle_cast({:save_piece, index, piece}, %{pieces: pieces, info_hash: info_hash} = state) do
    {hash, piece_info} = Map.get(pieces, index)

    case :crypto.hash(:sha, piece) do
      ^hash ->
        write_piece(piece, piece_info)
        TorrentTable.saved(info_hash, byte_size(piece))
        {:noreply, state}

      _ ->
        TorrentControl.failed_piece(state.control_pid, index)
        {:noreply, state}
    end
  end

  def write_piece(piece, piece_info) do
    FileUtils.write_piece(piece, piece_info)
  end
end
