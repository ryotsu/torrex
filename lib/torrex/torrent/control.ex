defmodule Torrex.Torrent.Control do
  @moduledoc """
  GenServer for controlling a torrent
  """

  use GenServer

  require Logger

  alias Torrex.Peer.Control, as: PeerControl
  alias Torrex.Torrent.Supervisor, as: TorrentSupervisor
  alias Torrex.FileIO.Utils, as: FileUtils
  alias Torrex.Listener
  alias Torrex.TorrentTable
  alias Torrex.Tracker

  @check_wait_time 3000

  @spec start_link(list) :: GenServer.on_start()
  def start_link([sup_pid, info_hash]) do
    GenServer.start_link(__MODULE__, [sup_pid, info_hash])
  end

  @spec add_peers(pid, binary) :: :ok
  def add_peers(pid, peers) do
    GenServer.cast(pid, {:add_peers, peers})
  end

  @spec add_peer_control_pid(pid, pid) :: :ok
  def add_peer_control_pid(pid, peer_control_pid) do
    GenServer.cast(pid, {:peer_control_pid, peer_control_pid})
  end

  @spec get_bitfield(pid) :: MapSet.t()
  def get_bitfield(pid) do
    GenServer.call(pid, :get_bitfield)
  end

  @spec next_piece(pid, MapSet.t()) :: {:ok, non_neg_integer, non_neg_integer} | {:error, term}
  def next_piece(pid, bitfield) do
    GenServer.call(pid, {:next_piece, bitfield})
  end

  @spec notify_saved(pid, non_neg_integer) :: :ok
  def notify_saved(pid, index) do
    GenServer.cast(pid, {:saved, index})
  end

  @spec find_peers(pid) :: :ok
  def find_peers(pid) do
    GenServer.cast(pid, :find_peers)
  end

  @spec failed_piece(pid, non_neg_integer) :: :ok
  def failed_piece(pid, index) do
    GenServer.cast(pid, {:failed_piece, index})
  end

  @spec get_num_pieces(pid) :: non_neg_integer
  def get_num_pieces(pid) do
    GenServer.call(pid, :num_pieces)
  end

  @impl true
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
      status: :initializing,
      have: 0
    }

    {:ok, state, {:continue, :initialize}}
  end

  @impl true
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

  @impl true
  def handle_call(:get_bitfield, _from, %{bitfield: bitfield} = state) do
    {:reply, bitfield, state}
  end

  @impl true
  def handle_call({:next_piece, peer_bitfield}, _from, %{bitfield: bitfield} = state) do
    diff = MapSet.difference(peer_bitfield, bitfield) |> MapSet.difference(state.downloading)

    case diff |> Enum.take_random(1) do
      [] ->
        {:reply, {:error, :no_available_piece}, state}

      [index] ->
        size =
          if index == state.num_pieces - 1, do: state.last_piece_length, else: state.piece_length

        downloading =
          if state.num_pieces - state.have <= 20 do
            MapSet.new()
          else
            MapSet.put(state.downloading, index)
          end

        {:reply, {:ok, index, size}, %{state | bitfield: bitfield, downloading: downloading}}
    end
  end

  @impl true
  def handle_call(:num_pieces, _from, %{num_pieces: num_pieces} = state) do
    {:reply, num_pieces, state}
  end

  @impl true
  def handle_cast({:add_peers, peers}, %{peer_control_pid: nil} = state) do
    {:noreply, Map.update!(state, :peers, &(&1 <> peers))}
  end

  @impl true
  def handle_cast({:add_peers, peers}, %{peer_control_pid: pid} = state) do
    PeerControl.add_peers(pid, peers)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:peer_control_pid, pid}, %{peers: peers} = state) do
    case peers do
      <<>> ->
        {:noreply, %{state | peer_control_pid: pid}}

      peers ->
        PeerControl.add_peers(pid, peers)
        {:noreply, %{state | peer_control_pid: pid, peers: <<>>}}
    end
  end

  @impl true
  def handle_cast({:saved, index}, %{bitfield: bitfield, downloading: downloading} = state) do
    PeerControl.notify_saved(state.peer_control_pid, index)
    bitfield = MapSet.put(bitfield, index)
    downloading = MapSet.delete(downloading, index)

    if state.num_pieces - state.have <= 20 do
      PeerControl.notify_cancel(state.peer_control_pid, index)
    end

    {:noreply, %{state | bitfield: bitfield, downloading: downloading, have: state.have + 1}}
  end

  @impl true
  def handle_cast(:find_peers, %{tracker_pid: pid} = state) do
    Tracker.find_peers(pid)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:failed_piece, index}, %{downloading: downloading} = state) do
    {:noreply, %{state | downloading: MapSet.delete(downloading, index)}}
  end

  @impl true
  def handle_info(:timeout, %{status: :initializing} = state) do
    {:noreply, state, {:continue, :initialize}}
  end

  @impl true
  def handle_info({ref, bitfield}, %{info_hash: info_hash, sup_pid: sup_pid} = state) do
    {:ok, tracker_pid} = TorrentSupervisor.add_tracker(sup_pid, info_hash, self())
    {:ok, file_worker} = TorrentSupervisor.start_file_worker(sup_pid, info_hash, bitfield, self())
    Listener.add_torrent(info_hash, self(), file_worker)

    have = MapSet.to_list(bitfield) |> length

    {:ok, _manager_pid} =
      TorrentSupervisor.start_peer_manager(sup_pid, info_hash, self(), file_worker)

    TorrentTable.size_on_disk(info_hash, calculate_size_on_disk(bitfield, state))
    :ok = TorrentTable.release_check()

    Process.demonitor(ref)
    state = %{state | bitfield: bitfield, have: have, status: :started, tracker_pid: tracker_pid}

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _status}, state) do
    Process.demonitor(ref)
    {:noreply, state}
  end

  @spec check_torrent(binary) :: MapSet.t()
  defp check_torrent(info_hash) do
    FileUtils.check_torrent(info_hash)
  end

  @spec calculate_size_on_disk(MapSet.t(), map) :: integer
  defp calculate_size_on_disk(bitfield, state) do
    count = bitfield |> Enum.to_list() |> length

    if (state.num_pieces - 1) in bitfield do
      (count - 1) * state.piece_length + state.last_piece_length
    else
      count * state.piece_length
    end
  end
end
