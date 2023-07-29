defmodule Torrex.Torrent do
  @moduledoc """
  Defines Torrent struct
  """

  defstruct [
    :name,
    :info_hash,
    :files,
    :size,
    :trackers,
    :piece_length,
    :pieces,
    uploaded: 0,
    downloaded: 0,
    left: :unknown
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          info_hash: binary,
          files: [{String.t(), non_neg_integer}],
          size: non_neg_integer,
          trackers: [String.t()],
          piece_length: non_neg_integer,
          pieces: map,
          uploaded: non_neg_integer,
          downloaded: non_neg_integer,
          left: non_neg_integer | :unknown
        }

  @spec parse_file(Path.t()) :: {:ok, __MODULE__.t()} | {:error, term} | :error
  def parse_file(path) do
    with {:ok, file} <- File.read(path),
         {:ok, torrent} <- Bento.decode(file),
         {:ok, info} <- Map.fetch(torrent, "info"),
         {:ok, name} <- Map.fetch(info, "name"),
         {:ok, pieces} <- Map.fetch(info, "pieces"),
         {:ok, piece_length} <- Map.fetch(info, "piece length"),
         {:ok, trackers} <- get_trackers(torrent) do
      download_dir = Application.get_env(:torrex, :download_dir)
      files = get_files(info, Path.join(download_dir, name))
      size = Enum.reduce(files, 0, fn {_name, length}, total -> length + total end)
      piece_map = get_piece_map(piece_length, files, get_hashes(pieces))
      {:ok, bencoded_info} = Bento.encode(info)
      info_hash = :crypto.hash(:sha, bencoded_info)

      {:ok,
       %__MODULE__{
         name: name,
         info_hash: info_hash,
         files: files,
         size: size,
         trackers: trackers,
         piece_length: piece_length,
         pieces: piece_map,
         uploaded: 0,
         downloaded: 0,
         left: size
       }}
    end
  end

  @spec get_files(map, Path.t()) :: [{Path.t(), non_neg_integer}]
  defp get_files(%{"files" => files}, name) do
    Enum.map(files, fn %{"length" => length, "path" => path} ->
      {Path.join(name, path), length}
    end)
  end

  defp get_files(%{"length" => length}, name) do
    [{name, length}]
  end

  @spec get_trackers(map) :: {:ok, [String.t()]} | {:error, term}
  defp get_trackers(%{"announce-list" => announce_list}), do: {:ok, List.flatten(announce_list)}
  defp get_trackers(%{"announce" => announce}), do: {:ok, [announce]}
  defp get_trackers(_), do: {:error, :no_trackers}

  @spec get_hashes(binary, non_neg_integer, map) :: map
  defp get_hashes(hash, num \\ 0, acc \\ %{})

  defp get_hashes("", _num, acc) do
    acc
  end

  defp get_hashes(<<hash::bytes-size(20), rest::binary>>, num, acc) do
    get_hashes(rest, num + 1, Map.put(acc, num, hash))
  end

  # Parititon the files into indiviual pieces of `piece_length` size and store it with its hash.
  # The map is of the form of `%{piece_num => {hash, [{file_path, file_offset, bytes_to_read}]}}`.
  # A piece hash must be equal to hash of combined data read from the piece_info.
  @spec get_piece_map(non_neg_integer, [{Path.t(), integer}], map) :: map
  defp get_piece_map(piece_length, files, piece_hash) do
    piece_map(piece_length, files)
    |> Enum.reduce(%{}, fn {path, piece_num, offset, length}, acc ->
      prev = Map.get(acc, piece_num, [])
      piece_info = [{path, offset, length} | prev]
      Map.put(acc, piece_num, piece_info)
    end)
    |> Enum.map(fn {piece_num, piece_info} ->
      {piece_num, {Map.fetch!(piece_hash, piece_num), piece_info}}
    end)
    |> Enum.into(%{})
  end

  @spec piece_map(integer, integer, integer, integer, [{Path.t(), integer}], list) :: list
  defp piece_map(piece_len, piece_offset \\ 0, piece_num \\ 0, file_offset \\ 0, files, acc \\ [])

  defp piece_map(_piece_len, _piece_offset, _piece_num, _file_offset, [], acc) do
    acc
  end

  defp piece_map(piece_len, piece_offset, piece_num, file_offset, [file | rest] = files, acc) do
    {path, length} = file
    bytes_in_piece = piece_len - piece_offset

    case file_offset + bytes_in_piece do
      # Piece ends at the end of this file
      next_offset when next_offset == length ->
        entry = {path, piece_num, file_offset, bytes_in_piece}
        piece_map(piece_len, 0, piece_num + 1, 0, rest, [entry | acc])

      # Piece ends in the middle of this file
      next_offset when next_offset < length ->
        entry = {path, piece_num, file_offset, bytes_in_piece}
        piece_map(piece_len, 0, piece_num + 1, next_offset, files, [entry | acc])

      # Piece ends in next file
      next_offset when next_offset > length ->
        bytes_in_file = length - file_offset
        new_piece_offset = piece_offset + bytes_in_file
        entry = {path, piece_num, file_offset, bytes_in_file}
        piece_map(piece_len, new_piece_offset, piece_num, 0, rest, [entry | acc])
    end
  end
end
