defmodule TorrexWeb.TorrentController do
  use TorrexWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def add(conn, %{"torrent" => torrent}) do
    case Torrex.add_torrent(torrent.path) do
      {:error, reason} ->
        json(conn, %{success: reason})

      _ ->
        json(conn, %{success: :ok})
    end
  end
end
