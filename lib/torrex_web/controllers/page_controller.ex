defmodule TorrexWeb.PageController do
  use TorrexWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html", token: get_csrf_token())
  end

  def add(conn, %{"torrent" => torrent}) do
    case Torrex.add_torrent(torrent.path) do
      {:error, reason} ->
        render(conn, "add.json", %{success: reason, token: get_csrf_token()})

      _ ->
        render(conn, "add.json", %{success: :ok, token: get_csrf_token()})
    end
  end
end
