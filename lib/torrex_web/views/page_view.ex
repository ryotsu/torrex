defmodule TorrexWeb.PageView do
  use TorrexWeb, :view

  def render("add.json", %{success: success, token: token}) do
    %{success: success, token: token}
  end
end
