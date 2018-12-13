defmodule Torrex.Tracker.UDP do
  @moduledoc """
  Worker for handling UDP tracker communications
  """

  use GenServer

  require Logger

  alias Torrex.Tracker
  alias Torrex.TorrentTable

  @type ip :: {byte, byte, byte, byte}

  @protocol_id 0x41727101980

  @timeout 15_000

  @spec start_link(binary, integer, integer) :: GenServer.on_start()
  def start_link(peer_id, tcp_port, udp_port) do
    GenServer.start_link(__MODULE__, [peer_id, tcp_port, udp_port], name: __MODULE__)
  end

  @spec contact_tracker(pid, ip, integer, atom, binary) :: :ok
  def contact_tracker(pid, ip, port, event, info_hash) do
    port = if port == nil, do: 80, else: port
    GenServer.cast(__MODULE__, {:contact, pid, ip, port, event, info_hash})
  end

  def init([peer_id, tcp_port, udp_port]) do
    {:ok, socket} = :gen_udp.open(udp_port, [:binary, active: true])
    {:ok, %{connections: %{}, timers: %{}, peer_id: peer_id, port: tcp_port, socket: socket}}
  end

  def handle_cast({:contact, pid, ip, port, event, info_hash}, state) do
    transaction_id = :crypto.strong_rand_bytes(4)
    connections = Map.put(state.connections, transaction_id, {info_hash, pid, event})
    state = connect(ip, port, transaction_id, state)

    {:noreply, %{state | connections: connections}}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  def handle_info({:udp, _socket, ip, port, <<0::size(32), response::binary>>}, state) do
    <<transaction_id::bytes-size(4), connection_id::bytes-size(8)>> = response

    case Map.pop(state.connections, transaction_id) do
      {{info_hash, _pid, event} = info, connections} ->
        state = cancel_timeout(state, transaction_id)
        transaction_id = :crypto.strong_rand_bytes(4)
        connections = Map.put(connections, transaction_id, info)
        state = announce(ip, port, transaction_id, connection_id, info_hash, event, state)
        {:noreply, %{state | connections: connections}}

      {nil, _connections} ->
        {:noreply, state}
    end
  end

  def handle_info({:udp, _, _, _, <<1::size(32), tid::bytes-size(4), resp::binary>>}, state) do
    case Map.pop(state.connections, tid) do
      {{_info_hash, pid, _event}, connections} ->
        state = cancel_timeout(state, tid)
        :ok = handle_success_response(resp, pid)
        {:noreply, %{state | connections: connections}}

      {nil, _connections} ->
        {:noreply, state}
    end
  end

  def handle_info(transaction_id, %{connections: connections, timers: timers} = state) do
    {{_info_hash, pid, _event}, connections} = Map.pop(connections, transaction_id)
    timers = Map.delete(timers, transaction_id)
    Tracker.error(pid, "timeout")

    {:noreply, %{state | connections: connections, timers: timers}}
  end

  defp handle_success_response(response, pid) do
    <<interval::size(32), leachers::size(32), seeders::size(32), peers::binary>> = response

    Tracker.response(pid, {interval, nil}, {seeders, leachers, peers})
  end

  @spec connect(ip, integer, binary, map) :: map
  defp connect(ip, port, transaction_id, %{socket: socket} = state) do
    msg = build_request(:connect, transaction_id)
    :gen_udp.send(socket, ip, port, msg)
    add_timeout(state, transaction_id)
  end

  @spec announce(ip, integer, binary, binary, binary, atom, map) :: map
  defp announce(ip, port, tid, conn_id, info_hash, event, %{socket: socket} = state) do
    msg = build_request(:announce, tid, conn_id, info_hash, event, state.peer_id, state.port)
    :ok = :gen_udp.send(socket, ip, port, msg)
    add_timeout(state, tid)
  end

  @spec build_request(:connect, binary) :: binary
  defp build_request(:connect, transaction_id) do
    <<
      @protocol_id::size(64),
      0::size(32),
      transaction_id::bytes-size(4)
    >>
  end

  @spec build_request(:announce, binary, binary, binary, atom, binary, integer) :: binary
  defp build_request(:announce, transaction_id, conn_id, info_hash, event, peer_id, port) do
    {:ok, torrent} = TorrentTable.get_torrent(info_hash)

    key = :crypto.strong_rand_bytes(4)
    event = event_to_num(event)

    <<
      conn_id::bytes-size(8),
      1::size(32),
      transaction_id::bytes-size(4),
      info_hash::bytes-size(20),
      peer_id::bytes-size(20),
      torrent.downloaded::size(64),
      torrent.left::size(64),
      torrent.uploaded::size(64),
      event::size(32),
      0::size(32),
      key::bytes-size(4),
      -1::size(32),
      port::size(16)
    >>
  end

  @spec event_to_num(atom) :: integer
  defp event_to_num(event) do
    case event do
      :completed -> 1
      :started -> 2
      :stopped -> 3
      _ -> 0
    end
  end

  @spec add_timeout(map, binary) :: map
  defp add_timeout(%{timers: timers} = state, transaction_id) do
    timer = Process.send_after(self(), transaction_id, @timeout)
    timers = Map.put(timers, transaction_id, timer)
    %{state | timers: timers}
  end

  @spec cancel_timeout(map, binary) :: map
  defp cancel_timeout(%{timers: timers} = state, transaction_id) do
    {timer, timers} = Map.pop(timers, transaction_id)
    Process.cancel_timer(timer)
    %{state | timers: timers}
  end
end
