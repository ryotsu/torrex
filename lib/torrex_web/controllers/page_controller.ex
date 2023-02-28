defmodule TorrexWeb.PageController do
  use TorrexWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  # def add(conn, %{"torrent" => torrent}) do
  #   case Torrex.add_torrent(torrent.path) do
  #     {:error, reason} ->
  #       render(conn, "add.json", %{success: reason, token: get_csrf_token()})

  #     _ ->
  #       render(conn, "add.json", %{success: :ok, token: get_csrf_token()})
  #   end
  # end
end
