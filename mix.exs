defmodule Torrex.MixProject do
  use Mix.Project

  def project do
    [
      app: :torrex,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:xmerl]]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Torrex, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dialyxir, "~> 1.0.0-rc.2", only: [:dev], runtime: false},
      {:bento, "~> 0.9.2"},
      {:httpoison, "~> 1.1"}
      # {:mldht, "~> 0.0.1"}
    ]
  end
end
