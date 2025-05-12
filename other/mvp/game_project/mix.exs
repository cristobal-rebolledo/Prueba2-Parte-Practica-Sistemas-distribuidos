defmodule GameProject.MixProject do
  use Mix.Project
  def project do
    [
      app: :game_project,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end
  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {GameProject.Application, []},
      extra_applications: [:logger, :inets, :crypto]
    ]
  end
  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug_cowboy, "~> 2.5"},
      {:jason, "~> 1.4"},
      {:httpoison, "~> 2.0"},
      {:grpc, "~> 0.5.0"},
      {:protobuf, "~> 0.10.0"},
      {:dotenv, "~> 3.1.0", only: [:dev, :test]},
      {:mock, "~> 0.3.0", only: :test}
    ]
  end
end
