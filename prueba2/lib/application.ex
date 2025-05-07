defmodule Prueba2.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Dotenv.load()

    #min_dado = System.get_env("CANT_MIN_DADO") |> String.trim() |> String.to_integer()
    #max_dado = System.get_env("CANT_MAX_DADO") |> String.trim() |> String.to_integer()

    # número aleatorio entero en el rango
    n_random = Enum.random(min_dado..max_dado)
    IO.puts("El número random es: #{n_random}")



    children = [
      # tus procesos supervisados aquí
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Prueba2.Supervisor)
  end
end
