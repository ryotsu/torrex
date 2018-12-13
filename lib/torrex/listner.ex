defmodule Torrex.Listner do
  @moduledoc """
  Worker for listening on connections
  """

  use GenServer

  @pstr "BitTorrent protocol"

  def start_link(port) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  def init(port) do
    {:ok, listen} = :gen_tcp.listen(port, [:binary, active: false])
    {:ok, file} = File.open("messages", [:write, :delayed_write, :binary, :raw])
    {:ok, {listen, file}, 0}
  end

  def handle_info(:timeout, {listen, file}) do
    {:ok, socket} = :gen_tcp.accept(listen)
    IO.puts("Accepted")
    {:ok, <<len::size(8)>>} = :gen_tcp.recv(socket, 1)
    {:ok, pstr} = :gen_tcp.recv(socket, len)
    {:ok, reserved} = :gen_tcp.recv(socket, 8)
    {:ok, info_hash} = :gen_tcp.recv(socket, 20)
    :ok = IO.binwrite(file, <<len, pstr::bytes, reserved::bytes, info_hash::bytes>>)
    msg = handshake(info_hash)
    :ok = :gen_tcp.send(socket, msg)
    {:ok, peer_id} = :gen_tcp.recv(socket, 20)

    case :gen_tcp.recv(socket, 4) do
      {:ok, <<len::size(32)>>} ->
        :ok = remaining_message(len, socket, file, peer_id)
        File.close(file)
        IO.puts("saved")
        {:noreply, 0}

      {:error, _} ->
        IO.puts("connection closed")
        :file.position(file, 0)
        {:noreply, {listen, file}, 0}
    end
  end

  def remaining_message(len, socket, file, peer_id) do
    {:ok, <<5::size(8), bitfield::bytes>>} = :gen_tcp.recv(socket, len)
    :file.position(file, {:eof, 0})
    IO.binwrite(file, <<peer_id::bytes, len::size(32), 5::size(8), bitfield::bytes>>)
    :ok = :gen_tcp.send(socket, interested())
    doit(socket, 0)
  end

  def doit(socket, index \\ 0) do
    :ok = :gen_tcp.send(socket, request(index, 0))
    {:ok, <<len::size(32)>>} = :gen_tcp.recv(socket, 4)

    case handle_message(:gen_tcp.recv(socket, len)) do
      :ok ->
        :ok

      {:index, index} ->
        doit(socket, index)

      :error ->
        doit(socket)

      :quit ->
        IO.puts("Error")
        :ok
    end
  end

  defp handshake(info_hash) do
    peer_id = Application.get_env(:torrex, :peer_id)
    <<19::size(8), @pstr::bytes, 0::size(64), info_hash::bytes, peer_id::bytes>>
  end

  defp handle_message({:ok, <<7::size(8), _index::size(32), _begin::size(32), block::binary>>}) do
    IO.puts("Downloading")
    {:ok, f} = File.open("block", [:write, :binary, :raw])
    IO.binwrite(f, block)
    File.close(f)
  end

  defp handle_message({:ok, <<4::size(8), index::size(32)>>}) do
    IO.puts("Index: #{index}")
    {:index, index}
  end

  defp handle_message({:ok, <<id::size(8), _rest::binary>>}) do
    IO.inspect(id)
    :error
  end

  defp handle_message({:error, _reason}) do
    :quit
  end

  defp request(index, begin) do
    <<13::size(32), 6::size(8), index::size(32), begin::size(32), 16_000::size(32)>>
  end

  defp interested do
    <<1::size(32), 2::size(8)>>
  end
end
