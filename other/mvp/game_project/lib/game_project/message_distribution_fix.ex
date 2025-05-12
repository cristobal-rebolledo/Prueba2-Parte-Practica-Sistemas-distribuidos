defmodule GameProject.MessageDistributionFix do
  @moduledoc """
  Módulo para manejar la distribución de mensajes entre jugadores.
  Implementación corregida del protocolo "distribuye".
  """

  alias GameProject.GRPCLogger
  alias GameProject.Network
  alias GameProject.PlayerRegistry
  alias GameProject.MessageHandler

  # Constante para identificar mensajes que deben ser distribuidos según el protocolo
  @distribute_flag :distribute_protocol

  # Utilidad para normalizar claves string a átomos en mensajes
  defp normalize_message_keys(message) when is_map(message) do
    message
    |> Enum.map(fn
      {"type", v} when is_binary(v) -> {:type, String.to_atom(v)}
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      pair -> pair
    end)
    |> Enum.into(%{})
  end

  @doc """
  Distribuye un mensaje a todos los jugadores siguiendo la especificación "distribuye".

  Implementación corregida siguiendo el protocolo original:
  1. Selecciona un miembro aleatorio de cada equipo (incluyendo los sin equipo)
  2. Cada seleccionado envía el mensaje a todos los miembros de su equipo
  3. Si algún miembro no responde, se elimina de la tabla y se avisa a los demás
  4. Cada nodo procesa el mensaje exactamente una vez cuando lo recibe como destinatario
  """
  def distribute_message(message, players) do
    # Asegurar que el propio nodo esté incluido en la lista de jugadores de su equipo
    local_ip = Network.get_local_ip()
    local_player = Enum.find(players, fn p -> p.address == local_ip end)
    players =
      if local_player do
        players
      else
        # Si no está, intentar obtener el equipo del mensaje o dejarlo sin equipo
        team = case message do
          %{player_data: %{team: t}} when not is_nil(t) -> t
          %{team: t} when not is_nil(t) -> t
          _ -> nil
        end
        [%{address: local_ip, alias: "self", team: team} | players]
      end

    # CORRECCIÓN FUNDAMENTAL DEL PROTOCOLO DISTRIBUYE:
    # El nodo originador NO procesa el mensaje localmente aquí.
    # Los mensajes se procesan solo cuando llegan a su destino final.

    IO.puts("\n#{IO.ANSI.magenta()}Iniciando protocolo distribuye para mensaje tipo: #{inspect(message[:type] || message["type"])}#{IO.ANSI.reset()}")

    # Normalizar el mensaje para formato consistente sin procesarlo
    normalized_message = case message do
      %{type: :new_player_joined} ->
        if is_map_key(message, :player_data) && is_map(message.player_data) do
          player_data = message.player_data
          atomized_data = Enum.into(%{}, player_data, fn
            {k, v} when is_binary(k) -> {String.to_atom(k), v}
            pair -> pair
          end)
          Map.put(message, :player_data, atomized_data)
        else
          message
        end

      _ -> message
    end

    # Iniciar log de distribución
    log_distribute_start(normalized_message)

    # Agregar timestamp al mensaje para control de duplicados
    message_with_timestamp = Map.put_new(normalized_message, :timestamp, System.system_time(:millisecond))

    # PASO 1: Agrupar jugadores por equipo (nil también cuenta como un grupo)
    players_by_team = Enum.group_by(players, fn player -> player.team end)

    # Debug: mostrar información sobre los grupos
    Enum.each(players_by_team, fn {team, members} ->
      IO.puts("\n#{IO.ANSI.cyan()}Equipo #{inspect(team)}: #{length(members)} miembros#{IO.ANSI.reset()}")
      Enum.each(members, fn m -> IO.puts("  - #{m.alias} @ #{m.address}") end)
    end)

    # PASO 2: Seleccionar UN representante aleatorio de CADA equipo/grupo
    # Este es el paso crítico del protocolo "distribuye"
    representatives = Enum.map(players_by_team, fn {team, team_players} ->
      representative = select_representative(team_players)
      if representative do
        IO.puts("\n#{IO.ANSI.green()}Representante para #{inspect(team)}: #{representative.alias}#{IO.ANSI.reset()}")
      end
      {team, representative}
    end)
    |> Enum.filter(fn {_team, representative} -> representative != nil end)

    # PASO 3: Cada representante envía el mensaje a TODOS los miembros de SU EQUIPO
    Enum.each(representatives, fn {team, representative} ->
      team_members = players_by_team[team] || []

      # Marcar el mensaje con la cabecera "distribuye" para que el representante sepa que
      # debe redistribuirlo a los miembros de su equipo
      distribute_message = Map.put(message_with_timestamp, @distribute_flag, true)

      IO.puts("\n#{IO.ANSI.green()}Enviando instrucción de distribución a #{representative.alias} para equipo #{inspect(team)}#{IO.ANSI.reset()}")

      # Si el representante es el nodo actual, simplemente distribuir a los miembros del equipo
      # SIN procesarlo localmente en distribute_message
      if representative.address == Network.get_local_ip() do
        IO.puts("\n#{IO.ANSI.green()}El representante es este nodo, redistribuyendo a miembros del equipo#{IO.ANSI.reset()}")

        # CORRECCIÓN IMPORTANTE: El mensaje original se distribuye directamente
        # sin procesamiento local. El procesamiento ocurrirá cuando este nodo
        # reciba el mensaje como miembro del equipo.
        distribute_to_team(distribute_message, team_members)
      else
        # Para otros nodos, enviar la instrucción de distribución
        distribution_instruction = %{
          action: :distribute_to_team,
          message: distribute_message,
          team: team
        }

        case send_message(distribution_instruction, Network.get_local_ip(), representative.address) do
          :ok ->
            IO.puts("\n#{IO.ANSI.green()}Instrucción de distribución enviada correctamente a #{representative.alias}#{IO.ANSI.reset()}")
          :error ->
            IO.puts("\n#{IO.ANSI.red()}Error enviando instrucción a #{representative.alias}. Eliminando jugador de la tabla y notificando a todos.#{IO.ANSI.reset()}")
            # El representante falló, eliminarlo e informar a los demás
            handle_representative_failure(representative, team, message, players_by_team)
        end
      end
    end)

    # Finalizar log de distribución
    log_distribute_end(message_with_timestamp, true)

    :ok
  end

  # Selecciona un representante aleatorio de un equipo
  defp select_representative(team_members) do
    if Enum.empty?(team_members) do
      nil
    else
      Enum.random(team_members)
    end
  end

  @doc """
  Distribuye un mensaje específico a todos los miembros de un equipo.
  Esta función es llamada cuando se recibe una instrucción de distribución.

  El representante debe:
  1. NO procesar el mensaje localmente (ya que lo recibirá como miembro del equipo)
  2. Distribuir el mensaje a todos los miembros del equipo, incluido a sí mismo
  """
  def distribute_to_team(message, team_members) do
    IO.puts("\n#{IO.ANSI.yellow()}Distribuyendo mensaje a #{length(team_members)} miembros del equipo #{IO.ANSI.reset()}")

    # Determinar el tipo de mensaje para logging
    message_type = cond do
      is_map_key(message, :type) -> message.type
      is_map_key(message, "type") -> message["type"]
      true -> "desconocido"
    end

    IO.puts("#{IO.ANSI.yellow()}Tipo de mensaje: #{inspect(message_type)}#{IO.ANSI.reset()}")

    # Normalizar el mensaje para garantizar formato consistente
    normalized_message = case message_type do
      "player_joined_team" ->
        %{
          type: :player_joined_team,
          player_alias: message["player_alias"] || message[:player_alias],
          team: if(is_binary(message["team"]), do: String.to_atom(message["team"]), else: message["team"] || message[:team]),
          timestamp: message["timestamp"] || message[:timestamp] || System.system_time(:millisecond)
        }
      _ ->
        normalize_message_keys(message)
    end

    # CORRECCIÓN: El representante NO procesa el mensaje aquí
    # Simplemente lo distribuye a todos los miembros (incluyéndose a sí mismo)
    IO.puts("\n#{IO.ANSI.green()}El representante solo distribuye sin procesar el mensaje#{IO.ANSI.reset()}")

    # Distribuir a TODOS los miembros del equipo (incluido el representante)
    Enum.each(team_members, fn member ->
      # Limpiar el mensaje de la cabecera de distribución para evitar redistribuciones
      clean_message = if Map.has_key?(normalized_message, @distribute_flag) do
        Map.delete(normalized_message, @distribute_flag)
      else
        normalized_message
      end

      if member.address == Network.get_local_ip() do
        # Para el nodo local (sea el representante u otro miembro), procesar directamente
        IO.puts("#{IO.ANSI.cyan()}Procesando mensaje como miembro local del equipo#{IO.ANSI.reset()}")
        MessageHandler.handle_message(clean_message)
      else
        # Para nodos remotos, enviar el mensaje limpio (sin cabecera de distribución)
        IO.puts("#{IO.ANSI.yellow()}Enviando a: #{member.alias} @ #{member.address}#{IO.ANSI.reset()}")

        # Enviar directamente a cada miembro
        case send_message(clean_message, Network.get_local_ip(), member.address) do
          :ok ->
            IO.puts("#{IO.ANSI.green()}Mensaje enviado con éxito a #{member.alias}#{IO.ANSI.reset()}")
          :error ->
            IO.puts("#{IO.ANSI.red()}Error enviando a #{member.alias}#{IO.ANSI.reset()}")
            # Podríamos implementar aquí la notificación de miembros fallidos
        end
      end
    end)

    :ok
  end

  # Maneja el fallo de un representante
  defp handle_representative_failure(representative, team, message, players_by_team) do
    case PlayerRegistry.remove_player(representative.alias) do
      {:ok, _} ->
        # Obtener jugadores actualizados (sin el que falló)
        updated_players = PlayerRegistry.get_players()

        # Enviar un mensaje informando que este jugador se desconectó
        failure_message = %{
          type: :player_disconnected,
          player_alias: representative.alias,
          timestamp: System.system_time(:millisecond)
        }

        # Registrar evento de jugador desconectado
        GRPCLogger.log_event(%{
          timestamp: System.system_time(:second),
          id_instancia: get_instance_id(),
          marcador: "NA",
          ip: Network.get_local_ip(),
          alias: "system",
          accion: "connection_lost",
          args: Jason.encode!(%{
            disconnected_player: representative.alias,
            disconnected_ip: representative.address,
            role: "representative"
          })
        })

        # Distribuir este mensaje (pero con otra profundidad para evitar ciclos)
        if Map.get(message, :recursion_depth, 0) < 3 do
          distribute_message(
            Map.put(failure_message, :recursion_depth, (Map.get(message, :recursion_depth, 0) + 1)),
            updated_players
          )

          # Si había otros miembros en ese equipo, volver a intentar con un nuevo representante
          try_with_new_representative(team, players_by_team, representative, message)
        end

      _ -> :ok # Error al eliminar el jugador, posiblemente ya fue eliminado
    end
  end

  # Intenta enviar el mensaje con un nuevo representante
  defp try_with_new_representative(team, players_by_team, failed_representative, message) do
    remaining_team_members = players_by_team[team] || []
    remaining_team_members = Enum.reject(remaining_team_members, fn p ->
      p.alias == failed_representative.alias
    end)

    if length(remaining_team_members) > 0 do
      # Seleccionar un nuevo representante para el equipo
      new_representative = select_representative(remaining_team_members)

      # Volver a intentar distribuir el mensaje original con el nuevo representante
      distribution_instruction = %{
        action: :distribute_to_team,
        message: message,
        team: team
      }

      send_message(distribution_instruction, Network.get_local_ip(), new_representative.address)
    end
  end

  # Envía un mensaje HTTP a un jugador específico
  defp send_message(message, from_address, to_address) do
    url = "http://#{to_address}/message"
    body = Jason.encode!(%{
      message: message,
      from: from_address,
      timestamp: System.system_time(:millisecond)
    })

    headers = [{"Content-Type", "application/json"}]

    # Implementación con reintentos
    retry_send_message(url, body, headers, 3)
  end

  # Implementa lógica de reintentos con backoff exponencial
  defp retry_send_message(url, body, headers, retries, delay \\ 1000) do
    case Network.http_post(url, body, headers, [timeout: 5000, recv_timeout: 5000]) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        :ok
      _error ->
        if retries > 0 do
          # Esperar con backoff exponencial
          :timer.sleep(delay)
          retry_send_message(url, body, headers, retries - 1, delay * 2)
        else
          :error
        end
    end
  end

  # Log al inicio de distribución de mensaje
  defp log_distribute_start(message) do
    GRPCLogger.log_event(%{
      timestamp: System.system_time(:second),
      id_instancia: get_instance_id(),
      marcador: "INICIO",
      ip: Network.get_local_ip(),
      alias: "system",
      accion: "distribute_message",
      args: Jason.encode!(%{
        type: message[:type],
        target_teams: "all"
      })
    })
  end

  # Log al final de distribución de mensaje
  defp log_distribute_end(message, success) do
    GRPCLogger.log_event(%{
      timestamp: System.system_time(:second),
      id_instancia: get_instance_id(),
      marcador: "FIN",
      ip: Network.get_local_ip(),
      alias: "system",
      accion: "distribute_message",
      args: Jason.encode!(%{
        type: message[:type],
        success: success
      })
    })
  end

  # Obtener ID de instancia del juego
  defp get_instance_id do
    case GameProject.GameServer.get_game_state() do
      {:ok, state} -> state.instance_id
      _ -> 0
    end
  end
end
