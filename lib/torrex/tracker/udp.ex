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

    connections =
      Map.put(state.connections, transaction_id, {info_hash, pid, event, {ip, port}, :connect})

    state = connect(ip, port, transaction_id, state, 0)

    {:noreply, %{state | connections: connections}}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  def handle_info({:udp, _socket, ip, port, <<0::size(32), response::binary>>}, state) do
    <<transaction_id::bytes-size(4), connection_id::bytes-size(8)>> = response

    case Map.pop(state.connections, transaction_id) do
      {{info_hash, pid, event, addr, _status}, connections} ->
        state = cancel_timeout(state, transaction_id)
        transaction_id = :crypto.strong_rand_bytes(4)
        info = {info_hash, pid, event, addr, {:announce, connection_id}}
        connections = Map.put(connections, transaction_id, info)
        state = announce(ip, port, transaction_id, connection_id, info_hash, event, state, 0)
        {:noreply, %{state | connections: connections}}

      {nil, _connections} ->
        {:noreply, state}
    end
  end

  def handle_info({:udp, _, _, _, <<1::size(32), tid::bytes-size(4), resp::binary>>}, state) do
    case Map.pop(state.connections, tid) do
      {{_info_hash, pid, _event, _addr, _status}, connections} ->
        state = cancel_timeout(state, tid)
        :ok = handle_success_response(resp, pid)
        {:noreply, %{state | connections: connections}}

      {nil, _connections} ->
        {:noreply, state}
    end
  end

  def handle_info({transaction_id, 3}, %{connections: connections, timers: timers} = state) do
    {{_info_hash, pid, _event, _addr, _sts}, connections} = Map.pop(connections, transaction_id)
    timers = Map.delete(timers, transaction_id)
    Tracker.error(pid, "timeout")

    {:noreply, %{state | connections: connections, timers: timers}}
  end

  def handle_info({transaction_id, count}, %{connections: conns} = state) do
    state = cancel_timeout(state, transaction_id)
    t_id = :crypto.strong_rand_bytes(4)

    case Map.pop(conns, transaction_id) do
      {{_ih, _pid, _event, {ip, port}, :connect} = conn, conns} ->
        state = %{state | connections: Map.put(conns, t_id, conn)}
        state = connect(ip, port, t_id, state, count + 1)
        {:noreply, state}

      {{info_hash, _pid, event, {ip, port}, {:announce, conn_id}} = conn, conns} ->
        state = %{state | connections: Map.put(conns, t_id, conn)}
        state = announce(ip, port, t_id, conn_id, info_hash, event, state, count + 1)
        {:noreply, state}

      _ ->
        Logger.debug("No transaction_id found: #{inspect(transaction_id)}")
        {:noreply, state}
    end
  end

  defp handle_success_response(response, pid) do
    <<interval::size(32), leachers::size(32), seeders::size(32), peers::binary>> = response

    Tracker.response(pid, {interval, nil}, {seeders, leachers, peers})
  end

  @spec connect(ip, integer, binary, map, integer) :: map
  defp connect(ip, port, transaction_id, %{socket: socket} = state, count) do
    msg = build_request(:connect, transaction_id)
    :gen_udp.send(socket, ip, port, msg)
    add_timeout(state, transaction_id, count)
  end

  @spec announce(ip, integer, binary, binary, binary, atom, map, integer) :: map
  defp announce(ip, port, tid, conn_id, info_hash, event, %{socket: socket} = state, count) do
    msg = build_request(:announce, tid, conn_id, info_hash, event, state.peer_id, state.port)
    :ok = :gen_udp.send(socket, ip, port, msg)
    add_timeout(state, tid, count)
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

  @spec add_timeout(map, binary, integer) :: map
  defp add_timeout(%{timers: timers} = state, transaction_id, count) do
    timer = Process.send_after(self(), {transaction_id, count}, @timeout)
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
