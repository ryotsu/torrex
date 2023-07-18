defmodule TorrexWeb.TorrentLive do
  @moduledoc """
  Displays all the torrents in a list and handles messages from the torrent table
  """
  require Logger
  use Phoenix.LiveView

  import TorrexWeb.CoreComponents, [:flash]

  def mount(_params, _options, socket) do
    torrents = Torrex.TorrentTable.subscribe()
    {:ok, assign(socket, torrents: torrents)}
  end

  def handle_event(_event, _params, socket) do
    {:noreply, socket}
  end

  def handle_info({:added, torrents}, socket) do
    {:noreply, assign(socket, :torrents, Map.merge(socket.assigns.torrents, torrents))}
  end

  def handle_info({:update, torrents}, socket) do
    for {id, download_speed} <- torrents do
      send_update(TorrexWeb.TorrentComponent, id: id, download_speed: download_speed)
    end

    {:noreply, socket}
  end

  def handle_info({:saved, sizes}, socket) do
    for {id, size} <- sizes do
      send_update(TorrexWeb.TorrentComponent, id: id, saved: size)
    end

    {:noreply, socket}
  end

  def handle_info({:left, left}, socket) do
    for {id, size} <- left do
      send_update(TorrexWeb.TorrentComponent, id: id, left: size)
    end

    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    Logger.warning("Unhandled message: #{msg}")
    {:noreply, socket}
  end
end
