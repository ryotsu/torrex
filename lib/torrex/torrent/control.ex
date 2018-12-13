defmodule Torrex.Torrent.Control do
  @moduledoc """
  GenServer for controlling a torrent
  """

  use GenServer

  require Logger

  alias Torrex.Peer.Control, as: PeerControl
  alias Torrex.Torrent.Supervisor, as: TorrentSupervisor
  alias Torrex.FileIO.Utils, as: FileUtils
  alias Torrex.TorrentTable
  alias Torrex.Tracker

  @check_wait_time 3000

  def start_link(sup_pid, info_hash) do
    GenServer.start_link(__MODULE__, [sup_pid, info_hash])
  end

  def init([sup_pid, info_hash]) do
    state = %{
      info_hash: info_hash,
      sup_pid: sup_pid,
      peer_control_pid: nil,
      piece_length: nil,
      num_pieces: nil,
      last_piece_length: nil,
      peers: <<>>,
      tracker_pid: nil,
      bitfield: MapSet.new(),
      downloading: MapSet.new(),
      status: :initializing
    }

    {:ok, state, {:continue, :initialize}}
  end

  def add_peers(pid, peers) do
    GenServer.cast(pid, {:add_peers, peers})
  end

  def add_peer_control_pid(pid, peer_control_pid) do
    GenServer.cast(pid, {:peer_control_pid, peer_control_pid})
  end

  def get_bitfield(pid) do
    GenServer.call(pid, :get_bitfield)
  end

  def next_piece(pid, bitfield) do
    GenServer.call(pid, {:next_piece, bitfield})
  end

  def notify_saved(pid, index) do
    GenServer.cast(pid, {:saved, index})
  end

  def find_peers(pid) do
    GenServer.cast(pid, :find_peers)
  end

  def failed_piece(pid, index) do
    GenServer.cast(pid, {:failed_piece, index})
  end

  def get_num_pieces(pid) do
    GenServer.call(pid, :num_pieces)
  end

  def handle_continue(:initialize, %{info_hash: info_hash} = state) do
    {:ok, torrent} = TorrentTable.get_torrent(info_hash)
    {:ok, num_pieces} = TorrentTable.get_num_pieces(info_hash)

    last_piece =
      case rem(torrent.size, torrent.piece_length) do
        0 -> torrent.piece_length
        len -> len
      end

    state = %{
      state
      | piece_length: torrent.piece_length,
        last_piece_length: last_piece,
        num_pieces: num_pieces
    }

    case TorrentTable.acquire_check() do
      :error ->
        {:noreply, state, @check_wait_time}

      :ok ->
        Task.async(fn -> check_torrent(info_hash) end)
        {:noreply, state}
    end
  end

  def handle_call(:get_bitfield, _from, %{bitfield: bitfield} = state) do
    {:reply, bitfield, state}
  end

  def handle_call({:next_piece, peer_bitfield}, _from, %{bitfield: bitfield} = state) do
    diff = MapSet.difference(peer_bitfield, bitfield) |> MapSet.difference(state.downloading)

    case diff |> Enum.take_random(1) do
      [] ->
        {:reply, {:error, :no_available_piece}, state}

      [index] ->
        size =
          if index == state.num_pieces - 1, do: state.last_piece_length, else: state.piece_length

        downloading = MapSet.put(state.downloading, index)
        {:reply, {:ok, index, size}, %{state | bitfield: bitfield, downloading: downloading}}
    end
  end

  def handle_call(:num_pieces, _from, %{num_pieces: num_pieces} = state) do
    {:reply, num_pieces, state}
  end

  def handle_cast({:add_peers, peers}, %{peer_control_pid: nil} = state) do
    {:noreply, Map.update!(state, :peers, &(&1 <> peers))}
  end

  def handle_cast({:add_peers, peers}, %{peer_control_pid: pid} = state) do
    PeerControl.add_peers(pid, peers)
    {:noreply, state}
  end

  def handle_cast({:peer_control_pid, pid}, %{peers: peers} = state) do
    case peers do
      <<>> ->
        {:noreply, %{state | peer_control_pid: pid}}

      peers ->
        PeerControl.add_peers(pid, peers)
        {:noreply, %{state | peer_control_pid: pid, peers: <<>>}}
    end
  end

  def handle_cast({:saved, index}, %{bitfield: bitfield, downloading: downloading} = state) do
    Logger.debug("Saved index #{index}")
    PeerControl.notify_saved(state.peer_control_pid, index)
    bitfield = MapSet.put(bitfield, index)
    downloading = MapSet.delete(downloading, index)

    {:noreply, %{state | bitfield: bitfield, downloading: downloading}}
  end

  def handle_cast(:find_peers, %{tracker_pid: pid} = state) do
    Tracker.find_peers(pid)

    {:noreply, state}
  end

  def handle_cast({:failed_piece, index}, %{downloading: downloading} = state) do
    {:noreply, %{state | downloading: MapSet.delete(downloading, index)}}
  end

  def handle_info(:timeout, %{status: :initializing} = state) do
    {:noreply, state, {:continue, :initialize}}
  end

  def handle_info({ref, bitfield}, %{info_hash: info_hash, sup_pid: sup_pid} = state) do
    {:ok, tracker_pid} = TorrentSupervisor.add_tracker(info_hash, self(), sup_pid)
    {:ok, file_worker} = TorrentSupervisor.start_file_worker(info_hash, self(), sup_pid)

    {:ok, _manager_pid} =
      TorrentSupervisor.start_peer_manager(info_hash, self(), file_worker, sup_pid)

    :ok = TorrentTable.release_check()
    Process.demonitor(ref)
    {:noreply, %{state | bitfield: bitfield, status: :started, tracker_pid: tracker_pid}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _status}, state) do
    Process.demonitor(ref)
    {:noreply, state}
  end

  defp check_torrent(info_hash) do
    FileUtils.check_torrent(info_hash)
  end
end
