# Archivo para simular un servidor proto para pruebas

defmodule GameProject.MockProtoServer do
  @moduledoc """
  Módulo para simular un servidor gRPC basado en la definición de log.proto.
  Este servidor simulado permite probar la integración gRPC sin necesitar
  un servidor real en funcionamiento.
  """

  @doc """
  Inicia un servidor simulado que acepta mensajes de log.
  """
  def start() do
    IO.puts("Iniciando servidor gRPC simulado en puerto 50051")

    # En una implementación real se iniciaría el servidor gRPC
    # Para el MVP, simplemente devolvemos un pid simulado
    spawn(fn -> loop([]) end)
  end

  defp loop(logs) do
    receive do
      {:log, entry} ->
        IO.puts("Log recibido: #{inspect(entry)}")
        loop([entry | logs])

      {:get_logs, sender} ->
        send(sender, {:logs, logs})
        loop(logs)

      :stop ->
        IO.puts("Servidor gRPC simulado detenido")
        :ok
    end
  end

  @doc """
  Envía un mensaje de log al servidor simulado.
  """
  def send_log(server, entry) do
    send(server, {:log, entry})
    :ok
  end

  @doc """
  Obtiene todos los logs almacenados en el servidor simulado.
  """
  def get_logs(server) do
    send(server, {:get_logs, self()})

    receive do
      {:logs, logs} -> logs
    after
      1000 -> []
    end
  end

  @doc """
  Detiene el servidor simulado.
  """
  def stop(server) do
    send(server, :stop)
  end
end
