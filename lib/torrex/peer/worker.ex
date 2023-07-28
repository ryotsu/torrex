defmodule Torrex.Peer.Worker do
  @moduledoc """
  Peer worker for communicating with peers
  """

  use GenServer, restart: :temporary

  require Logger

  alias Torrex.Torrent.Control, as: TorrentControl
  alias Torrex.FileIO.Worker, as: FileWorker
  alias Torrex.TorrentTable

  @spec start_link(list) :: GenServer.on_start()
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @spec notify_have(pid, non_neg_integer) :: :ok
  def notify_have(pid, index) do
    GenServer.cast(pid, {:have, index})
  end

  @spec notify_cancel(pid, non_neg_integer) :: :ok
  def notify_cancel(pid, index) do
    GenServer.cast(pid, {:cancel, index})
  end

  @impl true
  def init([socket, control_pid, file_worker, info_hash]) do
    bitfield = TorrentControl.get_bitfield(control_pid)
    num_pieces = TorrentControl.get_num_pieces(control_pid)

    peer_state = %{
      control_pid: control_pid,
      file_worker_pid: file_worker,
      socket: socket,
      info_hash: info_hash,
      num_pieces: num_pieces,
      piece: {nil, nil, nil},
      status: :idle,
      am_choking: true,
      am_interested: false,
      am_bitfield: bitfield,
      peer_choking: true,
      peer_interested: false,
      peer_bitfield: MapSet.new()
    }

    {:ok, peer_state, {:continue, :post_handshake}}
  end

  @impl true
  def handle_continue(:post_handshake, state) do
    bitfield(state)
    receive_message(state)
  end

  @impl true
  def handle_continue(:downloading, %{piece: {index, data, 0}} = state) do
    FileWorker.save_piece(state.file_worker_pid, index, IO.iodata_to_binary(data))
    state = %{state | status: :idle, piece: {nil, nil, nil}}
    Process.send_after(self(), :next_tick, 0)
    {:noreply, state}
  end

  @impl true
  def handle_continue(:downloading, state) do
    receive_message(state)
  end

  @impl true
  def handle_cast({:have, index}, state) do
    have(index, state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:cancel, index}, %{piece: {index, data, left}} = state) do
    size =
      Enum.reduce(data, left, fn bin, total ->
        if is_binary(bin), do: total + byte_size(bin), else: total
      end)

    data = make_cancel_data(index, 0, size)
    :gen_tcp.send(state.socket, data)

    {:noreply, %{state | piece: {nil, nil, nil}}}
  end

  @impl true
  def handle_cast({:cancel, _index}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:next_tick, %{status: :idle, am_interested: false} = state) do
    state = interested(state)
    receive_message(state)
  end

  @impl true
  def handle_info(:next_tick, %{status: :idle, am_interested: true, peer_choking: false} = st) do
    case TorrentControl.next_piece(st.control_pid, st.peer_bitfield) do
      {:ok, index, size} ->
        request(index, 0, size, st)
        data = [0] |> Stream.cycle() |> Enum.take(trunc(:math.ceil(size / 16_384)))
        receive_message(%{st | status: :downloading, piece: {index, data, size}})

      {:error, :no_available_piece} ->
        {:stop, :normal, st}
    end
  end

  @impl true
  def handle_info(:next_tick, %{status: :downloading, peer_choking: false} = state) do
    {:noreply, state, {:continue, :downloading}}
  end

  @impl true
  def handle_info(:next_tick, state) do
    receive_message(state)
  end

  @impl true
  def handle_info({:have, index}, state) do
    have(index, state)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{piece: {index, _, _}, control_pid: pid}) do
    TorrentControl.failed_piece(pid, index)
    :ok
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  # @spec keep_alive(map) :: :ok
  # defp keep_alive(%{socket: socket}) do
  #   :gen_tcp.send(socket, <<0::size(32)>>)
  # end

  # @spec choke(map) :: map
  # defp choke(%{socket: socket} = state) do
  #   :gen_tcp.send(socket, <<1::size(32), 0::size(8)>>)
  #   %{state | am_choking: true}
  # end

  # @spec unchoke(map) :: map
  # defp unchoke(%{socket: socket} = state) do
  #   :gen_tcp.send(socket, <<1::size(32), 1::size(8)>>)
  #   %{state | am_choking: false}
  # end

  @spec interested(map) :: map
  defp interested(%{socket: socket} = state) do
    :gen_tcp.send(socket, <<1::size(32), 2::size(8)>>)
    %{state | am_interested: true}
  end

  # @spec not_interested(map) :: map
  # defp not_interested(%{socket: socket} = state) do
  #   :gen_tcp.send(socket, <<1::size(32), 3::size(8)>>)
  #   %{state | am_interested: false}
  # end

  @spec have(non_neg_integer, map) :: :ok
  defp have(index, %{socket: socket}) do
    :gen_tcp.send(socket, <<5::size(32), 4::size(8), index::size(32)>>)
  end

  defp have(index, state) do
    Logger.debug("#{index}: #{inspect(state)}")
  end

  @spec bitfield(map) :: :ok
  defp bitfield(%{socket: socket, am_bitfield: bitfield} = state) do
    bitfield = make_bitfield(bitfield, state.num_pieces)
    :gen_tcp.send(socket, <<1 + byte_size(bitfield)::size(32), 5::size(8), bitfield::binary>>)
  end

  @spec request(non_neg_integer, non_neg_integer, non_neg_integer, map) :: :ok
  defp request(index, begin, len, %{socket: socket}) do
    request_data = make_request_data(index, begin, len)
    :gen_tcp.send(socket, request_data)
  end

  @spec make_request_data(non_neg_integer, non_neg_integer, non_neg_integer, binary) :: binary
  defp make_request_data(index, begin, len, data \\ <<>>)

  defp make_request_data(_index, _begin, 0, data) do
    data
  end

  defp make_request_data(index, begin, len, data) do
    req_len = min(len, 16 * 1024)
    data = data <> <<13::32, 6::8, index::32, begin::32, req_len::32>>
    make_request_data(index, begin + req_len, len - req_len, data)
  end

  # @spec piece(non_neg_integer, non_neg_integer, binary, map) :: map
  # defp piece(index, begin, block, %{socket: socket, requested: requested} = state) do
  #   :gen_tcp.send(socket, <<9 + byte_size(block)::32, 7::8, index::32, begin::32, block::binary>>)
  #   %{state | requested: MapSet.delete(requested, {index, begin, byte_size(block)})}
  # end

  # @spec cancel(non_neg_integer, non_neg_integer, non_neg_integer, map) :: :ok
  # defp cancel(index, begin, len, %{socket: socket}) do
  #   :gen_tcp.send(socket, <<13::32, 8::8, index::32, begin::32, len::32>>)
  # end

  @spec make_cancel_data(non_neg_integer, non_neg_integer, non_neg_integer, binary) :: binary
  defp make_cancel_data(index, begin, len, data \\ <<>>)

  defp make_cancel_data(_index, _begin, 0, data) do
    data
  end

  defp make_cancel_data(index, begin, len, data) do
    req_len = min(len, 16 * 1024)
    data = data <> <<13::32, 8::8, index::32, begin::32, req_len::32>>
    make_cancel_data(index, begin + req_len, len - req_len, data)
  end

  @spec receive_message(map) :: {:noreply, map} | {:stop, :normal, map}
  defp receive_message(%{socket: socket} = state) do
    case receive_msg(:gen_tcp.recv(socket, 4, 1_000), socket) do
      {:ok, id, len} ->
        case handle_message(id, len, state) do
          {:ok, state} ->
            Process.send_after(self(), :next_tick, 0)
            {:noreply, state}

          {:downloading, state} ->
            {:noreply, state, {:continue, :downloading}}

          _message ->
            :gen_tcp.close(state.socket)
            {:stop, :normal, state}
        end

      :keep_alive ->
        Process.send_after(self(), :next_tick, 0)
        {:noreply, state}

      {:error, :timeout} ->
        Process.send_after(self(), :next_tick, 100)
        {:noreply, state}

      {:error, :closed} ->
        :gen_tcp.close(state.socket)
        {:stop, :normal, state}
    end
  end

  @spec receive_msg({:ok, binary} | {:error, :timeout}, port) ::
          {:ok, non_neg_integer, non_neg_integer} | :keep_alive | {:error, term}
  defp receive_msg({:ok, <<0::size(32)>>}, _) do
    :keep_alive
  end

  defp receive_msg({:ok, <<len::size(32)>>}, socket) do
    with {:ok, <<id::size(8)>>} <- :gen_tcp.recv(socket, 1) do
      {:ok, id, len - 1}
    end
  end

  defp receive_msg({:error, :timeout}, _socket) do
    {:error, :timeout}
  end

  defp receive_msg(msg, _socket) do
    msg
  end

  # Handles choke
  @spec handle_message(non_neg_integer, non_neg_integer, map) ::
          {:ok, :normal, map} | {:ok, map} | {:downloading, map}
  defp handle_message(0, _, state) do
    {:ok, :normal, %{state | peer_choking: true}}
  end

  # Handles unchoke
  defp handle_message(1, _, state) do
    {:ok, %{state | peer_choking: false}}
  end

  # Handles interested
  defp handle_message(2, _, %{status: _status} = state) do
    {:ok, %{state | peer_interested: true}}
  end

  # Handles not interested
  defp handle_message(3, _, %{status: _status} = state) do
    {:ok, %{state | peer_interested: false}}
  end

  # Handles have
  defp handle_message(4, _, %{socket: socket, peer_bitfield: peer_bitfield} = state) do
    with {:ok, <<index::size(32)>>} <- :gen_tcp.recv(socket, 4) do
      {:ok, %{state | peer_bitfield: MapSet.put(peer_bitfield, index)}}
    end
  end

  # Handles bitfield
  defp handle_message(5, len, %{socket: socket} = state) do
    with {:ok, data} <- :gen_tcp.recv(socket, len) do
      {:ok, %{state | peer_bitfield: make_map(data)}}
    end
  end

  # Handles request
  defp handle_message(6, _, %{socket: socket, requested: requested} = state) do
    with {:ok, <<index::32, begin::32, len::32>>} <- :gen_tcp.recv(socket, 12) do
      {:ok, %{state | requested: MapSet.put(requested, {index, begin, len})}}
    end
  end

  # Handles piece
  defp handle_message(7, len, %{socket: socket, piece: {index, data, size}} = state) do
    with {:ok, <<^index::32, begin::32, block::binary>>} <- :gen_tcp.recv(socket, len) do
      TorrentTable.downloaded(state.info_hash, byte_size(block))
      data = List.replace_at(data, div(begin, 16 * 1024), block)
      size = size - byte_size(block)
      {:downloading, %{state | piece: {index, data, size}}}
    end
  end

  # Handles cancel
  defp handle_message(8, _, %{socket: socket, requested: requested} = state) do
    with {:ok, <<index::32, begin::32, len::32>>} <- :gen_tcp.recv(socket, 12) do
      {:ok, %{state | requested: MapSet.delete(requested, {index, begin, len})}}
    end
  end

  # Handles other messages
  defp handle_message(id, len, state) do
    Logger.warning("Unknown id: #{id} with length: #{len}")
    {:ok, state}
  end

  @spec make_map(binary, non_neg_integer, MapSet.t()) :: MapSet.t()
  defp make_map(bitfield, index \\ 0, data \\ MapSet.new())

  defp make_map(<<i::size(1), bitfield::bitstring>>, index, data) do
    data = if i == 1, do: MapSet.put(data, index), else: data
    make_map(bitfield, index + 1, data)
  end

  defp make_map(<<>>, _, data) do
    data
  end

  @spec make_bitfield(MapSet.t(), non_neg_integer) :: binary
  defp make_bitfield(bitfield, pieces) do
    pieces =
      case rem(pieces, 8) do
        0 -> pieces
        r -> pieces + 8 - r
      end

    0..(pieces - 1)
    |> Stream.map(&if &1 in bitfield, do: 1, else: 0)
    |> Enum.reduce(<<>>, fn i, acc -> <<acc::bitstring, i::size(1)>> end)
  end
end
