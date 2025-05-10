defmodule Prueba2.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Cargar variables de entorno desde el archivo .env
    Dotenv.load()

    # Asegurarse de que inits están disponibles
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    # Configuración para alias
    max_alias_length = System.get_env("MAX_ALIAS_LENGTH", "15") |> String.to_integer()
    Application.put_env(:prueba2, :max_alias_length, max_alias_length)

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
