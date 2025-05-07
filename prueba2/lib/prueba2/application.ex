defmodule Prueba2.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Dotenv.load()

    IO.puts(System.get_env("VARIABLE_1")) # Correcto

    children = [
      # tus procesos supervisados aquí
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
