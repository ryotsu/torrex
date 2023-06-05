defmodule TorrexWeb.PageController do
  use TorrexWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home)
  end

  def add(conn, %{"torrent" => torrent}) do
    case Torrex.add_torrent(torrent.path) do
      {:error, reason} ->
        json(conn, %{error: reason})

      _ ->
        json(conn, %{success: :ok})
    end
  end
end
