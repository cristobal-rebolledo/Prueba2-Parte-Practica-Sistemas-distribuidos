defmodule GameProject.Application do
  use Application
  @impl true
  def start(_type, _args) do    load_env()

    # El protocolo "distribuye" no necesita inicialización explícita

    children = [
      # Define workers and child supervisors to be supervised
      {DynamicSupervisor, strategy: :one_for_one, name: GameProject.DynamicSupervisor},
      {GameProject.PlayerRegistry, []},
      {GameProject.GameServer, []},
      {GameProject.GRPCLogger, []}
      # MessageHandler is not a process, just a module with functions
    ]

    opts = [strategy: :one_for_one, name: GameProject.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Carga variables de entorno desde .env en desarrollo y pruebas
  defp load_env do
    if Mix.env() in [:dev, :test] do
      Dotenv.load()

      # Cargar configuración desde variables de entorno
      config_grpc_server()
    end
  end    # Configura servidor gRPC desde variables de entorno
  defp config_grpc_server do
    ip = System.get_env("GRPC_SERVER_IP") || "127.0.0.1"
    port = System.get_env("GRPC_SERVER_PORT") || "50051"
    timeout = System.get_env("GRPC_SERVER_TIMEOUT") || "5000"

    # Eliminar caracteres no deseados como \r y \n antes de convertir a entero
    port = port |> String.trim() |> String.to_integer()
    timeout = timeout |> String.trim() |> String.to_integer()

    IO.puts("Configurando servidor gRPC en #{ip}:#{port} (timeout: #{timeout}ms)")
    Application.put_env(:game_project, :grpc_server, %{ip: ip, port: port, timeout: timeout})
  end
end
