defmodule GameProject.MessageHandlerFix do
  @moduledoc """
  Módulo para manejar los mensajes recibidos en la aplicación.
  Implementación corregida que aísla el procesamiento de mensajes
  de la lógica de distribución.
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
    # El mensaje debe estar limpio (sin cabeceras de distribuye o anidamiento)
    # cuando llega aquí, así que sólo debemos asegurar el formato correcto
    message = normalize_message_format(message)

    # Procesar según el tipo de mensaje
    case message do
      %{type: :player_joined_team} ->
        handle_player_joined_team(message)

      %{type: :player_disconnected} ->
        handle_player_disconnected(message)

      %{type: :new_player_joined} ->
        handle_new_player_joined(message)

      %{type: :score_update} ->
        # Actualizar la puntuación del equipo
        handle_score_update(message)

      %{type: :roll_dice} ->
        # Procesar lanzamiento de dados
        handle_roll_dice(message)

      %{type: :game_ended} ->
        # Finalizar el juego
        handle_game_ended(message)

      _ ->
        IO.puts("\n#{IO.ANSI.red()}Mensaje con formato desconocido: #{inspect(message)}#{IO.ANSI.reset()}")
        {:error, :unknown_message_type}
    end
  end

  # Normaliza el formato del mensaje para asegurar claves atómicas consistentes
  defp normalize_message_format(message) when is_map(message) do
    cond do
      # Caso: mensaje con clave "type" en texto
      is_map_key(message, "type") ->
        type_atom = case message["type"] do
          "player_joined_team" -> :player_joined_team
          "player_disconnected" -> :player_disconnected
          "new_player_joined" -> :new_player_joined
          "score_update" -> :score_update
          "roll_dice" -> :roll_dice
          "game_ended" -> :game_ended
          other when is_binary(other) -> String.to_atom(other)
          other -> other
        end

        # Convertir claves restantes a átomos
        message
        |> Map.delete("type")
        |> Enum.reduce(%{type: type_atom}, fn
          {"team", team}, acc when is_binary(team) ->
            Map.put(acc, :team, String.to_atom(team))
          {k, v}, acc when is_binary(k) ->
            Map.put(acc, String.to_atom(k), v)
          {k, v}, acc ->
            Map.put(acc, k, v)
        end)

      # Caso: mensaje con clave :player_data que necesita normalización
      is_map_key(message, :player_data) && is_map(message.player_data) ->
        player_data = Enum.into(message.player_data, %{}, fn
          {k, v} when is_binary(k) -> {String.to_atom(k), v}
          pair -> pair
        end)
        Map.put(message, :player_data, player_data)

      # Caso: no necesita normalización
      true ->
        message
    end
  end

  defp normalize_message_format(message), do: message

  @doc """
  Maneja el mensaje de un jugador uniéndose a un equipo.
  """
  def handle_player_joined_team(%{player_alias: player_alias, team: team}) do
    # Registrar en el log
    {:ok, game_state} = GameServer.get_game_state()

    case PlayerRegistry.get_player(player_alias) do
      {:ok, player} ->
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

        IO.puts("\n#{IO.ANSI.green()}Jugador #{player_alias} se unió al equipo #{inspect(team)}#{IO.ANSI.reset()}")
        {:ok, updated_player}

      _ ->
        IO.puts("\n#{IO.ANSI.red()}Error al actualizar equipo: Jugador #{player_alias} no encontrado#{IO.ANSI.reset()}")
        {:error, :player_not_found}
    end
  end

  @doc """
  Maneja el mensaje de un jugador abandonando la red.
  """
  def handle_player_disconnected(%{player_alias: player_alias}) do
    IO.puts("\n#{IO.ANSI.yellow()}Jugador desconectado: #{player_alias}#{IO.ANSI.reset()}")

    case PlayerRegistry.remove_player(player_alias) do
      {:ok, removed_player} ->
        # Registrar evento
        {:ok, game_state} = GameServer.get_game_state()
        GRPCLogger.log_event(%{
          timestamp: System.system_time(:second),
          id_instancia: game_state.instance_id,
          marcador: "DESCONEXIÓN",
          ip: removed_player.address,
          alias: player_alias,
          accion: "player_disconnected",
          args: Jason.encode!(%{
            reason: Map.get(removed_player, :reason, "unknown")
          })
        })

        {:ok, removed_player}

      _ ->
        {:error, :player_not_found}
    end
  end

  @doc """
  Maneja el mensaje de un nuevo jugador uniéndose a la red.
  """
  def handle_new_player_joined(%{player_data: player_data} = message) do
    # Extract player data
    %{alias: player_alias, address: address} = player_data
    team = Map.get(player_data, :team)

    # Añadir el nuevo jugador al registro local
    secret_number = Map.get(message, :secret_number, :rand.uniform(1000))

    new_player = %GameProject.Models.Player{
      address: address,
      alias: player_alias,
      team: team,
      secret_number: secret_number
    }

    IO.puts("\n#{IO.ANSI.green()}[unión directa a red] Añadiendo nuevo jugador a tabla local: #{player_alias} (#{address})#{IO.ANSI.reset()}")

    case PlayerRegistry.add_player(new_player) do
      {:ok, _} ->
        # Log the event
        {:ok, game_state} = GameServer.get_game_state()
        GRPCLogger.log_event(%{
          timestamp: System.system_time(:second),
          id_instancia: game_state.instance_id,
          marcador: "ACTUALIZACIÓN",
          ip: Network.get_local_ip(),
          alias: "system",
          accion: "player_added_to_registry",
          args: Jason.encode!(%{
            via: "unión directa a red",
            player_alias: player_alias,
            player_address: address
          })
        })

        IO.puts("\n#{IO.ANSI.green()}Nuevo jugador se unió a la red: #{player_alias} (#{address})#{IO.ANSI.reset()}")
        {:ok, new_player}

      {:error, :player_exists} ->
        IO.puts("\n#{IO.ANSI.yellow()}El jugador #{player_alias} ya existe en el registro#{IO.ANSI.reset()}")
        {:error, :player_exists}

      error ->
        IO.puts("\n#{IO.ANSI.red()}Error al añadir jugador: #{inspect(error)}#{IO.ANSI.reset()}")
        error
    end
  end

  # Manejadores para el resto de tipos de mensajes

  def handle_score_update(%{team: team, points: points}) do
    GameServer.update_score(team, points)
  end

  def handle_roll_dice(%{team: team, player_alias: player_alias, points: points}) do
    GameServer.update_score(team, points)
    GameServer.register_turn(team, player_alias)
    {:ok, %{team: team, points: points}}
  end

  def handle_game_ended(_message) do
    # Marcar el juego como terminado
    GameServer.get_game_state()
    |> elem(1)
    |> Map.put(:status, :finished)
    |> then(&GameServer.update_game_state/1)
  end
end
