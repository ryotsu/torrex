defmodule TorrexWeb.Router do
  use TorrexWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TorrexWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TorrexWeb do
    pipe_through :browser

    get "/", PageController, :home
    post "/add", PageController, :add
  end

  # Other scopes may use custom stacks.
  # scope "/api", TorrexWeb do
  #   pipe_through :api
  # end
end
