defmodule Torrex.TorrentTable do
  @moduledoc """
  Stores data about torrents and manages addition/deletion
  """

  # @dialyzer {:no_match, handle_call: 3}

  use GenServer

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

  @spec size_on_disk(binary, non_neg_integer) :: :ok
  def size_on_disk(info_hash, size) do
    GenServer.cast(__MODULE__, {:size_on_disk, info_hash, size})
  end

  @spec saved(binary, non_neg_integer) :: :ok
  def saved(info_hash, size) do
    GenServer.cast(__MODULE__, {:saved, info_hash, size})
  end

  @spec downloaded(binary, non_neg_integer) :: :ok
  def downloaded(info_hash, size) do
    GenServer.cast(__MODULE__, {:downloaded, info_hash, size})
  end

  def subscribe do
    GenServer.call(__MODULE__, :subscribe)
  end

  def init(peer_id) do
    state = %{
      torrents: %{},
      peer_id: peer_id,
      check_acquired: false,
      downloads: %{},
      subscribers: %{}
    }

    Process.send_after(self(), :send_update, 1_000)

    {:ok, state}
  end

  def handle_call({:add, path}, _from, %{torrents: torrents, downloads: downloads} = state) do
    case Torrex.Torrent.parse_file(path) do
      {:ok, torrent} ->
        case Map.has_key?(torrents, torrent.info_hash) do
          false ->
            {:ok, pid} = Torrex.Torrent.Pool.add_torrent(torrent.info_hash, torrent.name)
            torrents = Map.put(torrents, torrent.info_hash, {pid, torrent})
            downloads = Map.put(downloads, torrent.info_hash, [0, 0, 0, 0, 0])
            notify_added(torrent, state)

            {:reply, :ok, %{state | torrents: torrents, downloads: downloads}}

          true ->
            {:reply, :alread_downloading, state}
        end

      :error ->
        {:reply, {:error, "Error parsing file"}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get, info_hash}, _from, state) do
    with {:ok, {_pid, torrent}} <- find_torrent(state, info_hash) do
      {:reply, {:ok, torrent}, state}
    end
  end

  def handle_call({:get_trackers, info_hash}, _from, state) do
    with {:ok, {_pid, torrent}} <- find_torrent(state, info_hash) do
      {:reply, {:ok, torrent.trackers}, state}
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

  def handle_call({:num_pieces, info_hash}, _from, state) do
    with {:ok, {_pid, torrent}} <- find_torrent(state, info_hash) do
      pieces = (torrent.size / torrent.piece_length) |> :math.ceil() |> trunc
      {:reply, {:ok, pieces}, state}
    end
  end

  def handle_call(:subscribe, {pid, _tag}, %{subscribers: subs} = state) do
    ref = Process.monitor(pid)
    subs = Map.put(subs, ref, pid)

    {:reply, make_init_payload(state), %{state | subscribers: subs}}
  end

  def handle_cast({:size_on_disk, info_hash, size}, %{torrents: torrents} = state) do
    with {:ok, {pid, torrent}} <- find_torrent(state, info_hash, :noreply) do
      torrent = %Torrent{torrent | left: torrent.size - size}
      notify_left(torrent.left, info_hash, state)

      {:noreply, %{state | torrents: %{torrents | info_hash => {pid, torrent}}}}
    end
  end

  def handle_cast({:saved, info_hash, size}, %{torrents: torrents} = state) do
    with {:ok, {pid, torrent}} <- find_torrent(state, info_hash, :noreply) do
      torrent = %Torrent{
        torrent
        | downloaded: torrent.downloaded + size,
          left: torrent.left - size
      }

      state = %{state | torrents: %{torrents | info_hash => {pid, torrent}}}

      notify_saved(size, info_hash, state)

      {:noreply, state}
    end
  end

  def handle_cast({:downloaded, info_hash, size}, state) do
    with {:ok, [recent | rest]} <- find_download(state, info_hash) do
      state = %{state | downloads: %{state.downloads | info_hash => [recent + size | rest]}}
      {:noreply, state}
    end
  end

  def handle_info(:send_update, state) do
    state = notify_speed(state)
    Process.send_after(self(), :send_update, 1_000)

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{subscribers: subs} = state) do
    Process.demonitor(ref)
    subs = Map.delete(subs, ref)
    {:noreply, %{state | subscribers: subs}}
  end

  defp find_torrent(%{torrents: torrents} = state, info_hash, reply \\ :reply) do
    case Map.fetch(torrents, info_hash) do
      {:ok, torrent} ->
        {:ok, torrent}

      :error ->
        case reply do
          :reply -> {:reply, :error, state}
          :noreply -> {:noreply, state}
        end
    end
  end

  defp find_download(%{downloads: downloads} = state, info_hash) do
    case Map.fetch(downloads, info_hash) do
      {:ok, result} -> {:ok, result}
      :error -> {:noreply, state}
    end
  end

  defp notify_saved(size, info_hash, %{subscribers: subs}) do
    for {_ref, pid} <- subs do
      send(pid, {:saved, %{info_hash => size}})
    end
  end

  defp notify_speed(%{subscribers: subs, downloads: downloads} = state) do
    payload = calc_download_speed(downloads)

    downloads =
      downloads
      |> Enum.map(fn {info_hash, data} -> {info_hash, [0 | data] |> Enum.take(5)} end)
      |> Enum.into(%{})

    for {_ref, pid} <- subs do
      send(pid, {:update, payload})
    end

    %{state | downloads: downloads}
  end

  defp notify_added(torrent, %{subscribers: subs}) do
    payload = make_torrent_payload(torrent)

    for {_ref, pid} <- subs do
      send(pid, {:added, payload})
    end
  end

  defp notify_left(size, info_hash, %{subscribers: subs}) do
    payload = %{info_hash => size}

    for {_ref, pid} <- subs do
      send(pid, {:left, payload})
    end
  end

  defp make_torrent_payload(torrent) do
    %{
      torrent.info_hash => %{
        name: torrent.name,
        size: torrent.size,
        downloaded: torrent.downloaded,
        uploaded: torrent.uploaded,
        left: torrent.left,
        download_speed: 0
      }
    }
  end

  defp calc_download_speed(downloads) do
    downloads
    |> Enum.map(fn {info_hash, data} -> {info_hash, Enum.sum(data) / 5} end)
    |> Enum.into(%{})
  end

  defp make_init_payload(%{torrents: torrents, downloads: downloads}) do
    downloads
    |> calc_download_speed
    |> Enum.map(fn {info_hash, speed} ->
      {_pid, torrent} = torrents[info_hash]

      {info_hash,
       %{
         name: torrent.name,
         size: torrent.size,
         downloaded: torrent.downloaded,
         uploaded: torrent.uploaded,
         left: torrent.left,
         download_speed: speed
       }}
    end)
    |> Enum.into(%{})
  end
end
