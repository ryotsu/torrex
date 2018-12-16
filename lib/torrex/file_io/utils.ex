defmodule Torrex.FileIO.Utils do
  @moduledoc """
  Utilities for managing files
  """

  alias Torrex.TorrentTable

  @write_opts [:read, :write, :delayed_write, :binary, :raw]

  @read_opts [:read, :binary, :raw]

  @spec check_torrent(binary) :: MapSet.t()
  def check_torrent(info_hash) do
    {:ok, torrent} = TorrentTable.get_torrent(info_hash)
    true = ensure_torrent_paths(torrent.files) |> Enum.all?(&(&1 == :ok))

    check_all_pieces(torrent.pieces)
  end

  @spec ensure_torrent_paths([{Path.t(), integer}]) :: [:ok]
  def ensure_torrent_paths(files) do
    for {path, length} <- files do
      case File.exists?(path) do
        true ->
          size_on_disk = :filelib.file_size(path)
          if size_on_disk == length, do: :ok, else: fill_file(path, length - size_on_disk)

        false ->
          :ok = :filelib.ensure_dir(path)
          :ok = File.touch(path)
          fill_file(path, length)
      end
    end
  end

  @spec fill_file(Path.t(), integer) :: :ok
  def fill_file(path, missing) do
    {:ok, fd} = File.open(path, @write_opts)
    {:ok, _pos} = :file.position(fd, {:eof, missing - 1})
    :ok = IO.binwrite(fd, <<0>>)
    File.close(fd)
  end

  @spec check_piece({binary, [{Path.t(), integer, integer}]}) :: boolean
  def check_piece({hash, piece_parts}) do
    data =
      Enum.reduce(piece_parts, <<>>, fn {path, offset, bytes_to_read}, acc ->
        {:ok, fd} = File.open(path, @read_opts)
        {:ok, _pos} = :file.position(fd, offset)
        acc <> IO.binread(fd, bytes_to_read)
      end)

    :crypto.hash(:sha, data) == hash
  end

  def check_all_pieces(pieces) do
    {bitfield, {_path, fd}} =
      0..((Map.keys(pieces) |> length()) - 1)
      |> Stream.map(&Map.get(pieces, &1))
      |> Stream.with_index()
      |> Enum.reduce({MapSet.new(), nil}, fn {{hash, parts}, index}, {bitfield, last_file} ->
        {data, last_file} = read_data(parts, <<>>, last_file)

        bitfield =
          if :crypto.hash(:sha, data) == hash do
            MapSet.put(bitfield, index)
          else
            bitfield
          end

        {bitfield, last_file}
      end)

    File.close(fd)
    bitfield
  end

  def read_data([{path, _offset, bytes_to_read} | rest], <<>>, nil) do
    {:ok, fd} = File.open(path, @read_opts)
    read_data(rest, IO.binread(fd, bytes_to_read), {path, fd})
  end

  def read_data([{path, _offset, bytes_to_read} | rest], data, {path, fd}) do
    read_data(rest, data <> IO.binread(fd, bytes_to_read), {path, fd})
  end

  def read_data([{path, _offset, bytes_to_read} | rest], data, {_path, fd}) do
    File.close(fd)
    {:ok, fd} = File.open(path, @read_opts)
    read_data(rest, data <> IO.binread(fd, bytes_to_read), {path, fd})
  end

  def read_data([], data, {path, fd}) do
    {data, {path, fd}}
  end

  def write_piece(<<>>, []) do
    :ok
  end

  def write_piece(piece, [{path, offset, length} | rest]) do
    {:ok, fd} = File.open(path, @write_opts)
    {:ok, _pos} = :file.position(fd, offset)
    <<data::bytes-size(length), remaining::binary>> = piece
    IO.binwrite(fd, data)
    File.close(fd)
    write_piece(remaining, rest)
  end
end
