defmodule Torrex.Tracker.HTTP do
  @moduledoc """
  Handle HTTP tracker communication
  """

  use GenServer

  require Logger

  alias Torrex.Tracker
  alias Torrex.TorrentTable

  @spec start_link(list) :: GenServer.on_start()
  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @spec store_id(String.t(), String.t()) :: :ok
  def store_id(url, tracker_id) do
    GenServer.cast(__MODULE__, {:store_id, url, tracker_id})
  end

  @spec get_id(String.t()) :: {:ok, String.t()} | :error
  def get_id(url) do
    GenServer.call(__MODULE__, {:get_id, url})
  end

  @spec contact_tracker(pid, String.t(), atom, binary) :: :ok
  def contact_tracker(pid, url, event, info_hash) do
    GenServer.cast(__MODULE__, {:contact, pid, url, event, info_hash})
  end

  @impl true
  def init([peer_id, port]) do
    {:ok, %{tracker_ids: %{}, peer_id: peer_id, port: port}}
  end

  @impl true
  def handle_call({:get_id, url}, _from, %{tracker_ids: ids} = state) do
    {:reply, Map.fetch(ids, url), state}
  end

  @impl true
  def handle_cast({:store_id, url, tracker_id}, %{tracker_ids: ids} = state) do
    {:noreply, %{state | tracker_ids: Map.put(ids, url, tracker_id)}}
  end

  @impl true
  def handle_cast({:contact, pid, url, event, info_hash}, state) do
    spawn_link(__MODULE__, :make_request, [pid, url, event, info_hash, state.peer_id, state.port])
    {:noreply, state}
  end

  @spec make_request(pid, String.t(), atom, binary, binary, integer) :: :ok
  def make_request(pid, url, event, info_hash, peer_id, port) do
    request = build_request(url, event, info_hash, peer_id, port)

    case HTTPoison.get(request) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body |> Bento.decode() |> handle_response(url, pid)

      {:ok, _resp} ->
        Tracker.error(pid, "bad request")

      {:error, _reason} ->
        Tracker.error(pid, "bad request")
    end
  end

  @spec handle_response({:ok, map} | {:error | term}, String.t(), pid) :: :ok
  defp handle_response({:ok, response}, url, pid) do
    handle_response(response, url, response["failure reason"], response["warning message"], pid)
  end

  defp handle_response({:error, _reason}, _url, pid) do
    Tracker.error(pid, "bad response")
  end

  @spec handle_response(map, String.t(), binary | nil, binary | nil, pid) :: :ok
  defp handle_response(_response, _url, error, _warning, pid) when is_binary(error) do
    Tracker.error(pid, error)
  end

  defp handle_response(response, url, nil, warning, pid) when is_binary(warning) do
    Tracker.warning(pid, url, warning)
    handle_response(response, url, nil, nil, pid)
  end

  defp handle_response(response, url, nil, nil, pid) do
    interval = response["interval"]
    min_interval = response["min interval"]
    seeders = response["complete"]
    leechers = response["incomplete"]
    peers = response["peers"]

    case response["tracker id"] do
      nil -> :noop
      tracker_id -> store_id(url, tracker_id)
    end

    Tracker.response(pid, {interval, min_interval}, {seeders, leechers, peers})
  end

  @spec build_request(String.t(), atom, binary, binary, integer) :: String.t()
  defp build_request(url, event, info_hash, peer_id, port) do
    {:ok, torrent} = TorrentTable.get_torrent(info_hash)

    query = %{
      info_hash: info_hash,
      peer_id: peer_id,
      uploaded: torrent.uploaded,
      downloaded: torrent.downloaded,
      left: torrent.left,
      port: port,
      compact: 1
    }

    query =
      query
      |> add_tracker_id(url)
      |> add_event(event)
      |> URI.encode_query()

    url <> "?" <> query
  end

  @spec add_tracker_id(map, String.t()) :: map
  defp add_tracker_id(query, url) do
    case get_id(url) do
      {:ok, id} ->
        Map.put(query, :trackerid, id)

      :error ->
        query
    end
  end

  @spec add_event(map, atom) :: map
  defp add_event(query, :none), do: query
  defp add_event(query, event), do: Map.put(query, :event, event)
end
