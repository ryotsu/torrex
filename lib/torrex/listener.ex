defmodule Torrex.Listener do
  @moduledoc """
  Worker for listening on connections
  """

  use GenServer

  require Logger

  alias Torrex.Peer.Pool, as: PeerPool

  @pstr "BitTorrent protocol"
  @peer_id Application.get_env(:torrex, :peer_id)

  def start_link(port) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  def add_torrent(info_hash, control_pid, file_worker) do
    GenServer.cast(__MODULE__, {:add_torrent, info_hash, control_pid, file_worker})
  end

  def add_peer_pool(info_hash, peer_pool) do
    GenServer.cast(__MODULE__, {:add_peer_pool, info_hash, peer_pool})
  end

  def init(port) do
    {:ok, listen} = :gen_tcp.listen(port, [:binary, active: false])

    state = %{
      listen: listen,
      torrents: %{}
    }

    Process.send_after(self(), :accept, 50)

    {:ok, state}
  end

  def handle_cast({:add_torrent, info_hash, control_pid, file_worker}, %{torrents: t} = state) do
    peer_pool = Map.get(t, info_hash) |> (fn i -> if i == nil, do: nil, else: i.peer_pool end).()

    torrent = %{
      control_pid: control_pid,
      file_worker: file_worker,
      peer_pool: peer_pool
    }

    torrents = Map.put(t, info_hash, torrent)

    {:noreply, %{state | torrents: torrents}}
  end

  def handle_cast({:add_peer_pool, info_hash, peer_pool}, %{torrents: torrents} = state) do
    torrents =
      case Map.fetch(torrents, info_hash) do
        {:ok, torrent} -> %{torrents | info_hash => %{torrent | peer_pool: peer_pool}}
        :error -> Map.put(torrents, info_hash, %{peer_pool: peer_pool})
      end

    {:noreply, %{state | torrents: torrents}}
  end

  def handle_info(:accept, %{listen: listen, torrents: torrents} = state) do
    case :gen_tcp.accept(listen, 2_000) do
      {:ok, socket} ->
        task = Task.async(fn -> handshake(socket, torrents) end)
        :gen_tcp.controlling_process(socket, task.pid)

      _ ->
        Process.send_after(self(), :accept, 50)
    end

    {:noreply, state}
  end

  def handle_info({ref, _result}, state) do
    Process.demonitor(ref)
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _status}, state) do
    Process.demonitor(ref)
    {:noreply, state}
  end

  defp handshake(socket, torrents) do
    case recieve_handshake(socket) do
      {:ok, info_hash} ->
        if Map.has_key?(torrents, info_hash) do
          complete_handshake(socket, info_hash, torrents)
        else
          :gen_tcp.close(socket)
        end

      _msg ->
        :gen_tcp.close(socket)
    end
  end

  defp recieve_handshake(socket) do
    with {:ok, <<len::size(8)>>} <- :gen_tcp.recv(socket, 1),
         {:ok, pstr} <- :gen_tcp.recv(socket, len),
         {:ok, _reserved} <- :gen_tcp.recv(socket, 8),
         {:ok, info_hash} <- :gen_tcp.recv(socket, 20) do
      case pstr do
        @pstr -> {:ok, info_hash}
        _ -> :error
      end
    end
  end

  defp complete_handshake(socket, info_hash, torrents) do
    %{peer_pool: pool, control_pid: control, file_worker: file} = Map.get(torrents, info_hash)
    message = compose_handshake(info_hash)
    :gen_tcp.send(socket, message)

    case :gen_tcp.recv(socket, 20) do
      {:ok, _peer_id} ->
        {:ok, peer_worker} = PeerPool.start_peer(pool, socket, control, file, info_hash)
        :gen_tcp.controlling_process(socket, peer_worker)

      _ ->
        :gen_tcp.close(socket)
    end
  end

  defp compose_handshake(info_hash) do
    <<byte_size(@pstr)::size(8), @pstr::bytes, 0::size(64), info_hash::bytes, @peer_id::bytes>>
  end
end
