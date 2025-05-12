defmodule GameProject.LoggingTest do
  @moduledoc """
  Script para probar la conexión gRPC con el servidor externo
  """

  alias GameProject.GRPCLogger

  @spec run_test_connection() :: :ok
  def run_test_connection do
    # Cargar configuración de entorno
    Dotenv.load()

    # Configurar el servidor gRPC
    ip = System.get_env("GRPC_SERVER_IP") || "127.0.0.1"
    port = System.get_env("GRPC_SERVER_PORT") || "50051"
    timeout = System.get_env("GRPC_SERVER_TIMEOUT") || "5000"

    # Eliminar caracteres no deseados como \r y \n antes de convertir a entero
    port = port |> String.trim() |> String.to_integer()
    timeout = timeout |> String.trim() |> String.to_integer()

    IO.puts("Configurando servidor gRPC en #{ip}:#{port} (timeout: #{timeout}ms)")
    Application.put_env(:game_project, :grpc_server, %{ip: ip, port: port, timeout: timeout})

    # Asegurar que el GenServer esté inicializado
    case Process.whereis(GRPCLogger) do
      nil ->
        {:ok, _pid} = GRPCLogger.start_link()
      _pid ->
        :ok
    end

    # Crear un evento de prueba
    test_event = %{
      timestamp: System.system_time(:second),
      id_instancia: 999,
      marcador: "TEST_CONNECTION",
      ip: "127.0.0.1",
      alias: "test_script",
      accion: "connection_test",
      args: "{'test': 'manual connection test'}"
    }

    IO.puts("Enviando evento de prueba: #{inspect(test_event)}")

    # Intentar enviar el evento
    GRPCLogger.log_event(test_event)

    # Esperar un tiempo para que el log asíncrono se procese
    :timer.sleep(2000)

    IO.puts("Prueba de conexión completada. Revisa los logs para ver resultados.")

    :ok
  end
end
