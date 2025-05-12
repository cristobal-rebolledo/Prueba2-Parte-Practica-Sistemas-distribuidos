defmodule GameProject.GRPCLogger do
  @moduledoc """
  Cliente gRPC para enviar logs al servidor central.
  """

  use GenServer
  require Logger

  @max_retries 3
  @retry_delay 5000

  # API Pública

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Envía un evento de log al servidor gRPC.
  Si la conexión falla, lo almacena localmente para reintento posterior.

  Estructura del evento:
  %{
    timestamp: timestamp,       # Unix epoch en segundos
    id_instancia: id,           # ID único de la instancia del juego
    marcador: marker,           # "INICIO", "FIN" o "NA"
    ip: ip,                     # IP del proceso que genera el log
    alias: alias,               # Alias del jugador o "system"
    accion: action,             # Nombre de la función/acción
    args: args_json             # Args como JSON serializado
  }
  """
  def log_event(event) do
    GenServer.cast(__MODULE__, {:log_event, event})
  end

  # Callbacks

  @impl true
  def init(_opts) do
    # Inicializar estado con cola de eventos pendientes
    {:ok, %{pending_events: [], connected: false, retries: %{}}}
  end

  @impl true
  def handle_cast({:log_event, event}, state) do
    # Primero guardamos el evento localmente
    store_event_locally(event)

    # Luego intentamos enviarlo al servidor gRPC
    case send_to_grpc_server(event) do
      :ok ->
        # Éxito al enviar
        {:noreply, %{state | connected: true}}

      :error ->
        # Fallo al enviar, agregar a pendientes
        updated_state = %{
          state |
          connected: false,
          pending_events: [event | state.pending_events]
        }

        # Programar un reintento
        schedule_retry()

        {:noreply, updated_state}
    end
  end

  @impl true
  def handle_info(:retry_pending, state) do
    if Enum.empty?(state.pending_events) do
      {:noreply, state}
    else
      # Intentar reenviar los eventos pendientes
      {_sent, still_pending, retries} =
        Enum.reduce(state.pending_events, {[], [], state.retries}, fn event, {sent, pending, retries} ->
          event_id = "#{event.timestamp}_#{event.alias}"
          current_retries = Map.get(retries, event_id, 0)

          if current_retries < @max_retries do
            case send_to_grpc_server(event) do
              :ok ->
                {[event | sent], pending, retries}

              :error ->
                {sent, [event | pending], Map.put(retries, event_id, current_retries + 1)}
            end
          else
            # Excedió el número máximo de reintentos
            Logger.warning("Máximo de reintentos alcanzado para evento: #{inspect(event)}")
            {sent, pending, retries}
          end
        end)

      if !Enum.empty?(still_pending) do
        # Si aún hay pendientes, programar otro reintento
        schedule_retry()
      end

      {:noreply, %{state | pending_events: still_pending, retries: retries}}
    end
  end

  @impl true
  def handle_info({:tcp, _port, _data}, state) do
    # Ignorar mensajes TCP sin procesar (comúnmente enviados por el socket subyacente)
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_closed, _port}, state) do
    # El puerto TCP se cerró
    Logger.info("GRPCLogger: TCP connection closed")
    {:noreply, %{state | connected: false}}
  end

  @impl true
  def handle_info({:tcp_error, _port, reason}, state) do
    # Error en la conexión TCP
    Logger.warning("GRPCLogger: TCP connection error: #{inspect(reason)}")
    {:noreply, %{state | connected: false}}
  end

  @impl true
  def handle_info(unexpected_message, state) do
    # Captura cualquier otro mensaje inesperado
    Logger.debug("GRPCLogger: Ignoring unexpected message: #{inspect(unexpected_message)}")
    {:noreply, state}
  end

  # Almacena el evento localmente para persistencia y reintentos
  defp store_event_locally(event) do
    # Para una implementación más robusta, guardaríamos en un archivo o base de datos local
    Logger.info("Log: #{event.marcador} - #{event.accion}", event)
  end

  # Comprueba si el servidor gRPC está disponible mediante una conexión TCP
  defp grpc_server_available?(ip, port, timeout) do
    # Limpiar la IP y asegurar que no hay caracteres adicionales
    ip = to_string(ip) |> String.trim() |> String.replace("\r", "") |> String.replace("\n", "")

    # Asegurarnos que el puerto es un entero
    port =
      cond do
        is_binary(port) -> String.trim(port) |> String.replace(~r/\D/, "") |> String.to_integer()
        is_integer(port) -> port
        true -> 50051
      end

    case :gen_tcp.connect(String.to_charlist(ip), port, [:binary], timeout) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true
      {:error, _} ->
        false
    end
  end

  # Envía el evento al servidor gRPC
  defp send_to_grpc_server(event) do
    # Obtener configuración del servidor gRPC
    config = Application.get_env(:game_project, :grpc_server, %{
      ip: "127.0.0.1",
      port: 50051,
      timeout: 5000
    })

    grpc_ip = config.ip
    grpc_port = config.port
    timeout = config.timeout

    # Imprimir mensaje de depuración
    IO.puts("DEBUG: Intentando conectar a #{grpc_ip}:#{grpc_port}")

    # Verificar disponibilidad del servidor
    if grpc_server_available?(grpc_ip, grpc_port, timeout) do
      # Convertir el evento a un mensaje protobuf LogEntry
      # Asegurando que id_instancia sea un entero
      id_instancia_value =
        cond do
          is_binary(event.id_instancia) -> String.to_integer(event.id_instancia)
          is_integer(event.id_instancia) -> event.id_instancia
          true -> 0
        end

      log_entry = %LogEntry{
        timestamp: event.timestamp,
        id_instancia: id_instancia_value,
        marcador: event.marcador,
        ip: event.ip,
        alias: event.alias,
        accion: event.accion,
        args: event.args
      }

      try do
        Logger.info("Conectando a servidor gRPC: #{grpc_ip}:#{grpc_port}")
        {:ok, _} = Application.ensure_all_started(:grpc)
        IO.puts("DEBUG: Conectando canal...")
        # Limpiar dirección
        clean_ip = String.trim(grpc_ip) |> String.replace("\r", "") |> String.replace("\n", "")
        address = "#{clean_ip}:#{grpc_port}"
        # Aquí desempaquetamos correctamente el canal
        case GRPC.Stub.connect(address) do
          {:ok, channel} ->
            IO.puts("DEBUG: Canal conectado")
            IO.puts("DEBUG: Enviando mensaje...")
            Logger.info("Enviando log a #{grpc_ip}:#{grpc_port}: #{inspect(log_entry)}")
            send_result =
              try do
                LogService.Stub.send_log(channel, log_entry)
              rescue
                e -> {:error, e}
              end
            case send_result do
              {:ok, ack} ->
                IO.puts("DEBUG: Mensaje enviado, respuesta: #{inspect(ack)}")
                Logger.info("Respuesta recibida: #{inspect(ack)}")
                GRPC.Stub.disconnect(channel)
                :ok
              {:error, reason} ->
                Logger.error("Error enviando mensaje: #{inspect(reason)}")
                GRPC.Stub.disconnect(channel)
                :error
            end
          {:error, reason} ->
            Logger.error("Error conectando a gRPC: #{inspect(reason)}")
            :error
        end
      rescue
        e ->
          Logger.warning("Error enviando log por gRPC: #{inspect(e)}")
          :error
      catch
        :exit, reason ->
          Logger.warning("Timeout enviando log por gRPC: #{inspect(reason)}")
          :error
      end
    else
      Logger.warning("Servidor gRPC no disponible en #{grpc_ip}:#{grpc_port}")
      :error
    end
  end

  # Programa un reintento para enviar eventos pendientes
  defp schedule_retry() do
    Process.send_after(self(), :retry_pending, @retry_delay)
  end
end
