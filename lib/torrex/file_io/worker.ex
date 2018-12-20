defmodule Torrex.FileIO.Worker do
  @moduledoc """
  GenServer for file worker
  """

  use GenServer

  require Logger

  alias Torrex.TorrentTable
  alias Torrex.Torrent.Control, as: TorrentControl
  alias Torrex.FileIO.Utils, as: FileUtils

  def start_link(info_hash, bitfield, control_pid) do
    GenServer.start_link(__MODULE__, [info_hash, bitfield, control_pid])
  end

  def save_piece(pid, index, piece) do
    GenServer.cast(pid, {:save_piece, index, piece})
  end

  def init([info_hash, bitfield, control_pid]) do
    {:ok, torrent} = TorrentTable.get_torrent(info_hash)

    state = %{
      bitfield: bitfield,
      files: torrent.files,
      pieces: torrent.pieces,
      info_hash: info_hash,
      control_pid: control_pid,
      open_files: []
    }

    {:ok, state}
  end

  def handle_cast({:save_piece, index, piece}, %{bitfield: bitfield} = state) do
    case index in bitfield do
      true -> {:noreply, state}
      false -> write_piece(index, piece, state)
    end
  end

  defp write_piece(index, piece, %{pieces: pieces, info_hash: info_hash} = state) do
    {hash, piece_info} = Map.get(pieces, index)

    case :crypto.hash(:sha, piece) do
      ^hash ->
        FileUtils.write_piece(piece, piece_info)
        bitfield = MapSet.put(state.bitfield, index)
        TorrentTable.saved(info_hash, byte_size(piece))
        TorrentControl.notify_saved(state.control_pid, index)
        {:noreply, %{state | bitfield: bitfield}}

      _ ->
        TorrentControl.failed_piece(state.control_pid, index)
        {:noreply, state}
    end
  end
end
