defmodule Torrex.Tracker do
  @moduledoc """
  Worker for handling tracker connections
  """

  use GenServer

  require Logger

  alias Torrex.TorrentTable
  alias Torrex.Torrent.Control, as: TorrentControl
  alias Torrex.Tracker.HTTP
  alias Torrex.Tracker.UDP

  @type tracker_info :: {String.t(), DateTime.t(), integer}

  @epoch DateTime.from_unix(0) |> elem(1)

  @spec start_link(binary, pid) :: GenServer.on_start()
  def start_link(info_hash, control_pid) do
    GenServer.start_link(__MODULE__, [info_hash, control_pid])
  end

  @spec error(pid, String.t()) :: :ok
  def error(pid, error) do
    GenServer.cast(pid, {:error, error})
  end

  @spec warning(pid, String.t(), String.t()) :: :ok
  def warning(pid, url, warning) do
    GenServer.cast(pid, {:warning, url, warning})
  end

  @spec response(pid, {integer, integer | nil}, {integer, integer, binary}) :: :ok
  def response(pid, interval, peers) do
    GenServer.cast(pid, {:add_peers, interval, peers})
  end

  def find_peers(pid) do
    GenServer.cast(pid, :find_peers)
  end

  def init([info_hash, control_pid]) do
    {:ok, trackers} = TorrentTable.get_trackers(info_hash)
    trackers = Enum.map(trackers, fn t -> {t, @epoch, 0} end)

    state = %{
      info_hash: info_hash,
      control_pid: control_pid,
      trackers: trackers,
      current_tracker: :none,
      queued_message: :started,
      failed_trackers: [],
      timer: nil
    }

    {:ok, state, {:continue, :announce}}
  end

  def handle_continue(:announce, %{queued_message: msg, failed_trackers: failed} = state) do
    {url, trackers, failed} = contact_tracker(state.trackers, msg, state.info_hash, failed)
    new_state = %{state | current_tracker: url, trackers: trackers, failed_trackers: failed}

    {:noreply, new_state}
  end

  def handle_cast({:error, _msg}, %{current_tracker: current_tracker} = state) do
    tracker = {current_tracker, DateTime.utc_now(), 0}
    state = %{state | failed_trackers: [tracker | state.failed_trackers]}

    {:noreply, state, {:continue, :announce}}
  end

  def handle_cast({:warning, _url, msg}, state) do
    Logger.warn(msg)
    {:noreply, state}
  end

  def handle_cast({:add_peers, {interval, _}, {_seeders, _leechers, peers}}, state) do
    TorrentControl.add_peers(state.control_pid, peers)
    trackers = [{state.current_tracker, DateTime.utc_now(), interval} | state.trackers]
    timer = Process.send_after(self(), :announce, (interval + 5) * 1000)

    state = %{
      state
      | trackers: trackers ++ Enum.reverse(state.failed_trackers),
        current_tracker: :none,
        queued_message: :none,
        failed_trackers: [],
        timer: timer
    }

    {:noreply, state}
  end

  def handle_cast(:find_peers, %{timer: timer} = state) when is_reference(timer) do
    Process.cancel_timer(timer)
    {:noreply, %{state | timer: nil}, {:continue, :announce}}
  end

  def handle_cast(:find_peers, state) do
    {:noreply, state, {:continue, :announce}}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  def handle_info(:announce, state) do
    {:noreply, state, {:continue, :announce}}
  end

  def handle_info(:timeout, state) do
    {:noreply, state}
  end

  @spec contact_tracker([tracker_info], atom, binary, [tracker_info]) ::
          {String.t(), [tracker_info], [tracker_info]}
  defp contact_tracker([{_, announce, interval} = t | trackers], event, info_hash, failed) do
    if DateTime.diff(DateTime.utc_now(), announce) > interval do
      contact_tracker(t, trackers, event, info_hash, failed)
    else
      contact_tracker(trackers, event, info_hash, [t | failed])
    end
  end

  defp contact_tracker([], _event, _info_hash, failed) do
    {:none, [], failed}
  end

  @spec contact_tracker(tracker_info, [tracker_info], atom, binary, [tracker_info]) ::
          {String.t(), tracker_info, tracker_info}
  defp contact_tracker({url, _, interval} = t, trackers, event, info_hash, failed) do
    parsed_url = URI.parse(url)
    event = if interval == 0, do: :started, else: event

    case contact_tracker(parsed_url, event, info_hash) do
      :ok ->
        {url, trackers, failed}

      :error ->
        contact_tracker(trackers, event, info_hash, [t | failed])
    end
  end

  @spec contact_tracker(URI.t(), atom, binary) :: :ok | :error
  defp contact_tracker(%URI{scheme: "http"} = uri, event, info_hash) do
    HTTP.contact_tracker(self(), URI.to_string(uri), event, info_hash)
  end

  @spec contact_tracker(URI.t(), atom, binary) :: :ok | :error
  defp contact_tracker(%URI{scheme: "https"} = uri, event, info_hash) do
    HTTP.contact_tracker(self(), URI.to_string(uri), event, info_hash)
  end

  defp contact_tracker(%URI{scheme: "udp"} = uri, event, info_hash) do
    case uri.host |> to_charlist |> :inet.getaddr(:inet) do
      {:ok, ip} ->
        UDP.contact_tracker(self(), ip, uri.port, event, info_hash)

      _ ->
        :error
    end
  end
end
