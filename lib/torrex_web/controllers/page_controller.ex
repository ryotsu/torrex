defmodule TorrexWeb.PageController do
  use TorrexWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html", token: get_csrf_token())
  end

  def add(conn, %{"torrent" => torrent}) do
    success = Torrex.add_torrent(torrent.path)

    render(conn, "add.json", %{success: success, token: get_csrf_token()})
  end
end
