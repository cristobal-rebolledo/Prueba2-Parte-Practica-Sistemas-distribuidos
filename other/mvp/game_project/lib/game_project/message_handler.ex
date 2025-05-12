defmodule GameProject.MessageHandler do
  @moduledoc """
  Módulo para manejar los mensajes recibidos en la aplicación.
  """
  alias GameProject.PlayerRegistry
  alias GameProject.GRPCLogger
  alias GameProject.GameServer
  @doc """
  Maneja un mensaje recibido y realiza las acciones necesarias.

  Tipos de mensajes soportados:
  - :player_joined_team - Cuando un jugador se une a un equipo
  - :player_disconnected - Cuando un jugador abandona la red
  - :new_player_joined - Cuando un nuevo jugador se une a la red
  """
  def handle_message(message) do
    # Handle nested messages with :action and :message keys (distribution instructions)
    message = cond do
      # Extract the actual message from distribution instructions
      is_map(message) && Map.has_key?(message, :action) && Map.has_key?(message, :message) &&
      message.action == :distribute_to_team ->
        IO.puts("\n#{IO.ANSI.cyan()}Extrayendo mensaje anidado de instrucción de distribución#{IO.ANSI.reset()}")
        # Mark the inner message as coming via the distribute protocol
        inner_message = message.message

        # Add a flag to indicate this message came through the distribution protocol
        if is_map(inner_message) do
          Map.put(inner_message, :via_distribute_protocol, true)
        else
          inner_message
        end

      # Keep the original message in other cases
      true ->
        message
    end    # Also handle string keys in addition to atoms
    cond do
      # Handle using pattern matching for atom keys
      is_map(message) && Map.has_key?(message, :type) && message.type == :player_joined_team ->
        handle_player_joined_team(message)

      is_map(message) && Map.has_key?(message, :type) && message.type == :player_disconnected ->
        handle_player_disconnected(message)

      is_map(message) && Map.has_key?(message, :type) && message.type == :new_player_joined ->
        handle_new_player_joined(message)      # Handle string keys for player_joined_team
      is_map(message) && Map.has_key?(message, "type") && message["type"] == "player_joined_team" ->
        IO.puts("\n#{IO.ANSI.yellow()}Convertir mensaje player_joined_team con claves string a átomos#{IO.ANSI.reset()}")
        # Convert string keys to atom keys
        atomized_message = %{
          type: :player_joined_team,
          player_alias: message["player_alias"],
          team: String.to_atom(message["team"])
        }
        handle_player_joined_team(atomized_message)

      is_map(message) && Map.has_key?(message, "type") && message["type"] in ["player_disconnected", "player_disconnected"] ->
        # Convert string keys to atom keys
        atomized_message = Map.new(message, fn
          {"type", _} -> {:type, :player_disconnected}
          {k, v} when is_binary(k) -> {String.to_atom(k), v}
          pair -> pair
        end)
        handle_player_disconnected(atomized_message)

      is_map(message) && Map.has_key?(message, "type") && message["type"] in ["new_player_joined", "new_player_joined"] ->
        # Convert string keys to atom keys
        atomized_message = Map.new(message, fn
          {"type", _} -> {:type, :new_player_joined}
          {k, v} when is_binary(k) -> {String.to_atom(k), v}
          pair -> pair
        end)
        handle_new_player_joined(atomized_message)

      true ->
        IO.puts("\n#{IO.ANSI.red()}Mensaje con formato desconocido: #{inspect(message)}#{IO.ANSI.reset()}")
        {:error, :unknown_message_type}
    end
  end

  @doc """
  Maneja el mensaje de un jugador uniéndose a un equipo.
  """
  def handle_player_joined_team(%{player_alias: player_alias, team: team}) do
    # Registrar en el log
    {:ok, game_state} = GameServer.get_game_state()
    {:ok, player} = PlayerRegistry.get_player(player_alias)

    # Actualizar el jugador en el registro
    {:ok, updated_player} = PlayerRegistry.update_player(player_alias, %{team: team})

    # Registrar en el log
    GRPCLogger.log_event(%{
      timestamp: System.system_time(:second),
      id_instancia: game_state.instance_id,
      marcador: "ACTUALIZACIÓN",
      ip: player.address,
      alias: player_alias,
      accion: "team_update",
      args: Jason.encode!(%{team: team})
    })

    # Notificar a la consola
    IO.puts("\n#{IO.ANSI.green()}#{player_alias} se ha unido al equipo #{team}#{IO.ANSI.reset()}")

    {:ok, updated_player}
  end
  @doc """
  Maneja el mensaje de un jugador abandonando la red.
  """
  def handle_player_disconnected(%{player_alias: player_alias} = msg) do
    case PlayerRegistry.get_player(player_alias) do
      {:ok, player} ->
        # Registrar en el log
        {:ok, game_state} = GameServer.get_game_state()

        # Determinar la acción basada en la razón
        reason = Map.get(msg, :reason, :unknown)
        action = if reason == :leave_network, do: "leave_network", else: "player_disconnected"
        log_message = if reason == :leave_network, do: "Abandonó la red", else: "Se desconectó"

        GRPCLogger.log_event(%{
          timestamp: System.system_time(:second),
          id_instancia: game_state.instance_id,
          marcador: "DESCONEXIÓN",
          ip: player.address,
          alias: player_alias,
          accion: action,
          args: Jason.encode!(%{reason: reason})
        })

        # Eliminar al jugador del registro
        {:ok, _} = PlayerRegistry.remove_player(player_alias)        # Notificar a la consola con un mensaje más claro
        IO.puts("\n#{IO.ANSI.yellow()}#{player_alias} #{log_message}#{IO.ANSI.reset()}")
        {:ok, player}
          {:error, :player_not_found} ->
        {:error, :player_not_found}
    end
  end

  @doc """
  Maneja el mensaje de un nuevo jugador uniéndose a la red.

  Siguiendo estrictamente el protocolo distribuye:
  1. El mensaje llega a todos los nodos a través del protocolo distribuye
  2. Cada nodo registra al nuevo jugador en su tabla local
  3. El nodo original también recibe este mensaje y lo procesa igual
  """
  def handle_new_player_joined(full_message = %{player_data: player_data}) do
    # Función auxiliar para acceder a campos, maneja tanto claves de átomos como strings
    get_field = fn map, key ->
      cond do
        is_map_key(map, key) -> Map.get(map, key)
        is_binary(key) and is_map_key(map, String.to_atom(key)) -> Map.get(map, String.to_atom(key))
        is_atom(key) and is_map_key(map, Atom.to_string(key)) -> Map.get(map, Atom.to_string(key))
        true -> nil
      end
    end

    # Extraer datos del jugador (maneja tanto claves string como atom)
    address = get_field.(player_data, :address) || get_field.(player_data, "address")
    alias_name = get_field.(player_data, :alias) || get_field.(player_data, "alias")
    team = get_field.(player_data, :team) || get_field.(player_data, "team")

    # Obtener el número secreto si existe (para nodos que procesan sus propias solicitudes)
    secret_number = Map.get(full_message, :secret_number, nil)

    # Obtener información sobre el origen del mensaje para mejorar depuración
    message_source = cond do
      Map.get(full_message, :via_distribute_protocol, false) -> "protocolo distribuye"
      Map.get(full_message, :join_network, false) -> "unión directa a red"
      true -> "origen desconocido"
    end

    # Verificar si tenemos los datos necesarios
    if address == nil || alias_name == nil do
      IO.puts("\n#{IO.ANSI.red()}Error: datos insuficientes para nuevo jugador: #{inspect(player_data)}#{IO.ANSI.reset()}")
      {:error, :missing_required_player_data}
    else
      # Verificar si estamos recibiendo un mensaje sobre nosotros mismos
      is_self_node = (address == GameProject.Network.get_local_ip())

      # Verificar si el jugador ya existe en el registro local
      case PlayerRegistry.get_player_by_address(address) do
        {:ok, existing_player} ->
          # El jugador ya existe, solo actualizamos info si es necesario
          message_prefix = if is_self_node, do: "SOBRE MI MISMO", else: message_source
          IO.puts("\n#{IO.ANSI.cyan()}[#{message_prefix}] Jugador ya registrado: #{alias_name} (#{address})#{IO.ANSI.reset()}")

          # Si hay alguna actualización de datos, aplicarla
          if existing_player.team != team && team != nil do
            IO.puts("\n#{IO.ANSI.green()}Actualizando datos del jugador ya registrado#{IO.ANSI.reset()}")
            PlayerRegistry.update_player(alias_name, %{team: team})
          end

          {:ok, :player_already_registered}

        {:error, :player_not_found} ->
          # El jugador no existe, lo agregamos al registro local (siguiendo el protocolo distribuye)
          IO.puts("\n#{IO.ANSI.bright()}[#{message_source}] Añadiendo nuevo jugador a tabla local: #{alias_name} (#{address})#{IO.ANSI.reset()}")

          # Crear el nuevo jugador con todos los datos disponibles
          player = GameProject.Models.Player.new(address, alias_name, team)

          # Si tenemos número secreto disponible, usarlo
          player_with_secret = if secret_number do
            %{player | secret_number: secret_number}
          else
            player
          end

          # Añadir el jugador al registro
          case PlayerRegistry.add_player(player_with_secret) do
            {:ok, added_player} ->
              # Notificar a la consola
              IO.puts("\n#{IO.ANSI.green()}Nuevo jugador se unió a la red: #{alias_name} (#{address})#{IO.ANSI.reset()}")

              # Registrar en el log
              case GameServer.get_game_state() do
                {:ok, game_state} ->
                  GRPCLogger.log_event(%{
                    timestamp: System.system_time(:second),
                    id_instancia: game_state.instance_id,
                    marcador: "ACTUALIZACIÓN",
                    ip: GameProject.Network.get_local_ip(),
                    alias: "system",
                    accion: "player_added_to_registry",
                    args: Jason.encode!(%{
                      player_alias: alias_name,
                      player_address: address,
                      via: message_source
                    })
                  })
                _ -> :ok
              end

              {:ok, player}

            {:error, reason} ->
              IO.puts("\n#{IO.ANSI.red()}Error al añadir jugador: #{reason}#{IO.ANSI.reset()}")
              {:error, reason}
          end
      end
    end
  end
end
