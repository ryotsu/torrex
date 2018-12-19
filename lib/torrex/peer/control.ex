defmodule Torrex.Peer.Control do
  use GenServer

  require Logger

  alias Torrex.Torrent.Control, as: TorrentControl
  alias Torrex.Peer.Pool, as: PeerPool
  alias Torrex.Peer.Worker, as: PeerWorker
  alias Torrex.Listener

  @pstr "BitTorrent protocol"
  @peer_limit 25
  @peer_id Application.get_env(:torrex, :peer_id)

  @spec start_link(binary, pid, pid, pid) :: GenServer.on_start()
  def start_link(info_hash, control_pid, file_worker, sup_pid) do
    GenServer.start_link(__MODULE__, [info_hash, control_pid, file_worker, sup_pid])
  end

  @spec add_peers(pid, list) :: :ok
  def add_peers(pid, peers) do
    GenServer.cast(pid, {:add_peers, peers})
  end

  def notify_saved(pid, index) do
    GenServer.cast(pid, {:saved, index})
  end

  def init([info_hash, control_pid, file_worker, sup_pid]) do
    state = %{
      info_hash: info_hash,
      control_pid: control_pid,
      file_worker_pid: file_worker,
      manager_pid: sup_pid,
      pool_pid: nil,
      queued: 0,
      peers_left: MapSet.new(),
      peers_used: MapSet.new(),
      finding_peers: true
    }

    {:ok, state, {:continue, :init}}
  end

  def handle_continue(:init, %{control_pid: control_pid, manager_pid: man_pid} = state) do
    :ok = TorrentControl.add_peer_control_pid(control_pid, self())

    pool_pid =
      case Torrex.Peer.Manager.start_peer_pool(man_pid) do
        {:ok, pool_pid} -> pool_pid
        {:error, {:already_started, pid}} -> pid
      end

    Listener.add_peer_pool(state.info_hash, pool_pid)
    Process.send_after(self(), :start_peers, 10_000)

    {:noreply, %{state | pool_pid: pool_pid}}
  end

  def handle_cast({:add_peers, peers}, %{peers_left: left, peers_used: used} = state) do
    peers_left =
      peers
      |> parse_peers()
      |> Enum.into(MapSet.new())
      |> MapSet.difference(used)
      |> MapSet.union(left)

    Process.send_after(self(), :find_peers, 60_000)

    {:noreply, %{state | finding_peers: false, peers_left: peers_left}}
  end

  def handle_cast({:saved, index}, %{pool_pid: pool_pid} = state) do
    PeerPool.get_children(pool_pid)
    |> Enum.each(fn {_, pid, _, _} -> PeerWorker.notify_have(pid, index) end)

    {:noreply, state}
  end

  def handle_info(:start_peers, %{pool_pid: pool_pid} = state) do
    %{active: active} = PeerPool.count_children(pool_pid)
    state = if active + state.queued < @peer_limit, do: start_peers(active, state), else: state
    Process.send_after(self(), :start_peers, 10_000)

    {:noreply, state}
  end

  def handle_info(:find_peers, %{finding_peers: false, control_pid: pid} = state) do
    state =
      if MapSet.equal?(state.peers_left, MapSet.new()) do
        TorrentControl.find_peers(pid)
        %{state | finding_peers: true}
      else
        state
      end

    Process.send_after(self(), :find_peers, 60_000)

    {:noreply, state}
  end

  def handle_info(:find_peers, state) do
    {:noreply, state}
  end

  def handle_info({ref, _result}, %{queued: queued} = state) do
    Process.demonitor(ref)
    {:noreply, %{state | queued: queued - 1}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _status}, state) do
    Process.demonitor(ref)
    {:noreply, state}
  end

  defp start_peers(active, %{peers_left: left, peers_used: used, pool_pid: pid} = state) do
    peers =
      left
      |> Enum.take(@peer_limit - active - state.queued)
      |> Enum.into(MapSet.new())

    left = MapSet.difference(left, peers)
    used = MapSet.union(used, peers)
    queued = state.queued + (peers |> Enum.to_list() |> length)

    for peer <- peers do
      Task.async(fn ->
        handshake(peer, state.info_hash, pid, state.control_pid, state.file_worker_pid)
      end)
    end

    %{state | peers_left: left, peers_used: used, queued: queued}
  end

  @spec parse_peers(binary, list) :: list
  defp parse_peers(peers, peer_list \\ [])

  defp parse_peers(<<a, b, c, d, port::16, rest::binary>>, peers) do
    parse_peers(rest, [{{a, b, c, d}, port} | peers])
  end

  defp parse_peers(<<>>, peers), do: peers

  defp handshake({ip, port}, info_hash, pool_pid, ctrl, file_worker) do
    with {:ok, socket} <- :gen_tcp.connect(ip, port, [:binary, active: false]) do
      message = compose_handshake(info_hash)
      :gen_tcp.send(socket, message)

      with {:ok, _peer_id} <- complete_handshake(socket, info_hash),
           {:ok, worker} <- PeerPool.start_peer(pool_pid, socket, ctrl, file_worker, info_hash) do
        :gen_tcp.controlling_process(socket, worker)
      end
    end
  end

  defp complete_handshake(socket, info_hash) do
    with {:ok, <<len::size(8)>>} <- :gen_tcp.recv(socket, 1),
         {:ok, pstr} <- :gen_tcp.recv(socket, len),
         {:ok, _reserved} <- :gen_tcp.recv(socket, 8),
         {:ok, info_hash_recv} <- :gen_tcp.recv(socket, 20),
         {:ok, peer_id} <- :gen_tcp.recv(socket, 20) do
      case {pstr, info_hash_recv} do
        {@pstr, ^info_hash} -> {:ok, peer_id}
        _ -> :error
      end
    end
  end

  defp compose_handshake(info_hash) do
    <<byte_size(@pstr)::size(8), @pstr::bytes, 0::size(64), info_hash::bytes, @peer_id::bytes>>
  end
end
