defmodule Torrex.TorrentTable do
  @moduledoc """
  Stores data about torrents and manages addition/deletion
  """

  @dialyzer {:no_match, handle_call: 3}

  require Logger

  alias Torrex.Torrent

  @spec start_link(String.t()) :: GenServer.on_start()
  def start_link(peer_id) do
    GenServer.start_link(__MODULE__, peer_id, name: __MODULE__)
  end

  @spec add_torrent(Path.t()) :: :ok | :alread_started | {:error, term}
  def add_torrent(path) do
    GenServer.call(__MODULE__, {:add, path})
  end

  @spec get_torrent(binary) :: {:ok, Torrent.t()} | {:error, term}
  def get_torrent(info_hash) do
    GenServer.call(__MODULE__, {:get, info_hash})
  end

  @spec get_trackers(binary) :: {:ok, [String.t()]} | :error
  def get_trackers(info_hash) do
    GenServer.call(__MODULE__, {:get_trackers, info_hash})
  end

  @spec get_num_pieces(binary) :: {:ok, integer} | :error
  def get_num_pieces(info_hash) do
    GenServer.call(__MODULE__, {:num_pieces, info_hash})
  end

  @spec acquire_check :: :ok | :error
  def acquire_check do
    GenServer.call(__MODULE__, :check)
  end

  @spec release_check :: :ok
  def release_check do
    GenServer.call(__MODULE__, :release_check)
  end

  def init(peer_id) do
    {:ok, %{torrents: %{}, peer_id: peer_id, check_acquired: false}}
  end

  def handle_call({:add, path}, _from, %{torrents: torrents} = state) do
    case Torrex.Torrent.parse_file(path) do
      {:ok, torrent} ->
        case Map.has_key?(torrents, torrent.info_hash) do
          false ->
            {:ok, pid} = Torrex.Torrent.Pool.add_torrent(torrent.info_hash, torrent.name)
            torrents = Map.put(torrents, torrent.info_hash, {pid, torrent})
            {:reply, :ok, %{state | torrents: torrents}}

          true ->
            {:reply, :alread_started, state}
        end

      :error ->
        {:reply, {:error, "Error parsing file"}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get, info_hash}, _from, %{torrents: torrents} = state) do
    case Map.fetch(torrents, info_hash) do
      {:ok, {_pid, torrent}} ->
        {:reply, {:ok, torrent}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:get_trackers, info_hash}, _from, %{torrents: torrents} = state) do
    case Map.fetch(torrents, info_hash) do
      {:ok, {_pid, torrent}} ->
        {:reply, {:ok, torrent.trackers}, state}

      :error ->
        {:reply, :error, state}
    end
  end

  def handle_call(:check, _from, %{check_acquired: {true, _pid}} = state) do
    {:reply, :error, state}
  end

  def handle_call(:check, {pid, _ref}, %{check_acquired: false} = state) do
    {:reply, :ok, %{state | check_acquired: {true, pid}}}
  end

  def handle_call(:release_check, {pid, _ref}, %{check_acquired: {true, pid}} = state) do
    {:reply, :ok, %{state | check_acquired: false}}
  end

  def handle_call(:release_check, _from, state) do
    {:reply, :ok, state}
  end

  def handle_call({:num_pieces, info_hash}, _from, %{torrents: torrents} = state) do
    case Map.fetch(torrents, info_hash) do
      {:ok, {_pid, torrent}} ->
        pieces =
          div(torrent.size, torrent.piece_length) +
            case rem(torrent.size, torrent.piece_length) do
              0 -> 0
              _ -> 1
            end

        {:reply, {:ok, pieces}, state}

      :error ->
        {:reply, :error, state}
    end
  end
end
