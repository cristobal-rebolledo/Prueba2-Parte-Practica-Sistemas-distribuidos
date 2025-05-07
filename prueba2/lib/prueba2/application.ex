defmodule Prueba2.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Dotenv.load()

    System.get_env("INTEGRANTES_EQUIPO") |> IO.puts # lee variable de entorno

    children = [
      # tus procesos supervisados aquí
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
