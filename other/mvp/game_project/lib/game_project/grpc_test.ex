defmodule GRPCTest do
  @moduledoc """
  Módulo para probar manualmente la conexión gRPC al servidor de logs
  Ejecutar con: mix run -e "GRPCTest.run()"
  """

  @doc """
  Ejecutar test de conexión gRPC
  """
  def run do
    # Cargar variables de entorno
    {:ok, _} = Application.ensure_all_started(:dotenv)
    :dotenv.load()

    # Configurar servidor gRPC
    grpc_ip = "26.111.116.168"
    grpc_port = 50051

    IO.puts("\n== Test de conexión gRPC ==")
    IO.puts("Servidor: #{grpc_ip}:#{grpc_port}")

    # 1. Verificar conectividad TCP básica
    check_tcp_connectivity(grpc_ip, grpc_port)

    # 2. Iniciar aplicaciones necesarias
    {:ok, _} = Application.ensure_all_started(:grpc)

    # 3. Crear mensaje de prueba
    test_msg = create_test_message()

    # 4. Conectar y enviar mensaje
    send_grpc_message(grpc_ip, grpc_port, test_msg)

    IO.puts("\n== Test finalizado ==")
  end

  defp check_tcp_connectivity(ip, port) do
    IO.puts("\nVerificando conexión TCP básica...")

    case :gen_tcp.connect(String.to_charlist(ip), port, [:binary, active: false], 5000) do
      {:ok, socket} ->
        IO.puts("[OK] Conexión TCP establecida correctamente")
        :ok = :gen_tcp.close(socket)

      {:error, reason} ->
        IO.puts("[ERROR] No se pudo establecer conexión TCP: #{inspect(reason)}")
        IO.puts("Asegúrese de que el servidor está ejecutándose y es accesible")
    end
  end

  defp create_test_message do
    %LogEntry{
      timestamp: System.system_time(:second),
      id_instancia: 999,
      marcador: "TEST_MANUAL",
      ip: "127.0.0.1",
      alias: "test_manual",
      accion: "manual_connectivity_test",
      args: "{\"test\": true, \"timestamp\": \"#{DateTime.utc_now()}\"}"
    }
  end

  defp send_grpc_message(ip, port, message) do
    IO.puts("\nEstableciendo conexión gRPC...")

    adapter_opts = %{
      gun_opts: [
        connect_timeout: 5000,
        http2_opts: %{
          settings_timeout: :infinity
        },
        retry: 1,
        transport: :tcp,
        protocols: [:http2]
      ]
    }

    case GRPC.Stub.connect("#{ip}:#{port}", adapter_opts: adapter_opts) do
      {:ok, channel} ->
        IO.puts("[OK] Conexión gRPC establecida")

        try do
          IO.puts("\nEnviando mensaje: #{inspect(message)}")

          # Usar opciones específicas para el envío
          opts = %{metadata: %{"content-type" => "application/grpc"}}

          # Enviar mensaje y esperar respuesta
          case LogService.Stub.send_log(channel, message, opts) do
            {:ok, response} ->
              IO.puts("\n[OK] Respuesta recibida: #{inspect(response)}")

            {:error, error} ->
              IO.puts("\n[ERROR] Error al enviar mensaje: #{inspect(error)}")
          end

        rescue
          e ->
            IO.puts("\n[EXCEPCIÓN] #{inspect(e)}")
            IO.puts(Exception.format(:error, e, __STACKTRACE__))
        catch
          kind, reason ->
            IO.puts("\n[ERROR CAPTURADO] #{inspect(kind)}: #{inspect(reason)}")
        after
          IO.puts("\nCerrando conexión gRPC...")
          GRPC.Stub.disconnect(channel)
        end

      {:error, reason} ->
        IO.puts("[ERROR] No se pudo establecer conexión gRPC: #{inspect(reason)}")
    end
  end
end
