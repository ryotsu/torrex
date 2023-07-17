defmodule TorrexWeb.PageController do
  use TorrexWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
