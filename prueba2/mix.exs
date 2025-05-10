defmodule Prueba2.MixProject do
  use Mix.Project

  def project do
    [
      app: :prueba2,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {Prueba2.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:dotenv, "~> 3.0.0"},        # para poner variables de entorno
      {:elixir_uuid, "~> 1.2"},     # para generar UUIDs
      {:plug_cowboy, "~> 2.5"},     # Para la API HTTP
      {:jason, "~> 1.2"},           # Para codificación/decodificación JSON
      {:httpoison, "~> 2.0"},       # Cliente HTTP más amigable que :httpc
      {:remote_ip, "~> 1.1"}        # Para obtener IP pública de forma confiable
    ]
  end
end
