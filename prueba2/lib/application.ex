defmodule Prueba2.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Asegurarse de que inits están disponibles
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    # Valores por defecto para dados
    min_dado = 1
    max_dado = 6

    # número aleatorio entero en el rango
    n_random = Enum.random(min_dado..max_dado)
    Logger.info("Número aleatorio inicial: #{n_random}")

    children = [
      # Supervisar la red P2P
      {Prueba2.P2PNetwork, []},
      # Iniciar la interfaz de usuario
      {Prueba2.UserInterface, []}
    ]

    Logger.info("Iniciando aplicación P2P...")
    Supervisor.start_link(children, strategy: :one_for_one, name: Prueba2.Supervisor)
  end
end
