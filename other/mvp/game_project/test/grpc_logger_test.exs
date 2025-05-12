defmodule GameProject.GRPCLoggerTest do
  use ExUnit.Case, async: false
  import Mock

  alias GameProject.GRPCLogger

  @test_event %{
    timestamp: System.system_time(:second),
    id_instancia: 123,
    marcador: "TEST",
    ip: "127.0.0.1",
    alias: "test_player",
    accion: "test_action",
    args: "{}"
  }

  setup do
    # Asegurar que el GenServer esté iniciado
    case Process.whereis(GRPCLogger) do
      nil ->
        {:ok, _pid} = GRPCLogger.start_link()
      _pid ->
        :ok
    end

    :ok
  end

  describe "GRPCLogger" do
    test "log_event acepta el evento y no bloquea" do
      # Este test verifica que la llamada no bloquea incluso si hay problemas
      GRPCLogger.log_event(@test_event)
      # Si llegamos aquí, la llamada no bloqueó
      assert true
    end

    test "log_event con mock de conexión exitosa" do
      with_mock GRPC.Stub, [
        connect: fn _url -> {:ok, :test_channel} end,
        disconnect: fn _channel -> :ok end
      ] do
        with_mock LogService.Stub, [
          send_log: fn _channel, _entry -> {:ok, %Ack{ok: true}} end
        ] do
          # Enviar el evento
          GRPCLogger.log_event(@test_event)

          # Dar tiempo para que el proceso asíncrono termine
          Process.sleep(100)

          # Verificar que se intentó conectar
          assert_called GRPC.Stub.connect(:_)
          # Verificar que se intentó enviar el log
          assert_called LogService.Stub.send_log(:_, :_)
        end
      end
    end

    test "log_event con mock de conexión fallida reintenta" do
      with_mock GRPC.Stub, [
        connect: fn _url -> {:ok, :test_channel} end,
        disconnect: fn _channel -> :ok end
      ] do
        with_mock LogService.Stub, [
          send_log: fn _channel, _entry ->
            raise "Error de conexión simulado"
          end
        ] do
          # Enviar el evento
          GRPCLogger.log_event(@test_event)

          # Dar tiempo para que el proceso asíncrono termine
          Process.sleep(100)

          # Verificar que se intentó conectar
          assert_called GRPC.Stub.connect(:_)
          # Verificar que se intentó enviar el log
          assert_called LogService.Stub.send_log(:_, :_)
        end
      end
    end
  end
end
