defmodule GameProject.UI.GameLogic do
  @moduledoc """
  Módulo para manejar la lógica de juego en la interfaz de usuario.
  """

  alias GameProject.GameServer
  alias GameProject.PlayerRegistry
  alias GameProject.GRPCLogger
  alias GameProject.MessageDistribution

  @doc """
  Muestra el estado actual del juego en la parte superior de la interfaz.
  """
  def show_game_status(game_state, player_alias) do
    {:ok, player} = PlayerRegistry.get_player(player_alias)

    IO.puts(IO.ANSI.clear())

    # Barra de estado
    status_color = case game_state.status do
      :waiting -> IO.ANSI.yellow()
      :in_progress -> IO.ANSI.green()
      :finished -> IO.ANSI.bright() <> IO.ANSI.blue()
    end

    status_text = case game_state.status do
      :waiting -> "EN ESPERA"
      :in_progress -> "EN CURSO"
      :finished -> "FINALIZADO"
    end

    IO.puts("#{status_color}[#{status_text}]#{IO.ANSI.reset()} | Turno: #{game_state.turn_number} | Puntuación máxima: #{game_state.max_score}")

    # Mostrar equipos y puntuaciones
    IO.puts("----------------------------------------")
    IO.puts("#{IO.ANSI.bright()}PUNTUACIONES#{IO.ANSI.reset()}")

    Enum.each(game_state.team_scores, fn {team, score} ->
      team_indicator = if player.team == team, do: "➤ ", else: "  "
      IO.puts("#{team_indicator}#{team}: #{score} puntos")
    end)

    # Si el juego está en progreso, mostrar quién debe jugar
    if game_state.status == :in_progress do
      IO.puts("\n#{IO.ANSI.bright()}TURNO ACTUAL#{IO.ANSI.reset()}")

      Enum.each(game_state.available_teams, fn team ->
        next_player = next_player_for_team(game_state, team)

        if next_player do
          player_indicator = if next_player.alias == player_alias, do: "#{IO.ANSI.bright()}➤ TU TURNO#{IO.ANSI.reset()}", else: ""
          IO.puts("  #{team}: #{next_player.alias} #{player_indicator}")
        else
          IO.puts("  #{team}: Esperando jugadores")
        end
      end)
    end

    IO.puts("----------------------------------------\n")
  end

  @doc """
  Determina si un jugador puede iniciar el juego (si es el creador de la red).
  """
  def can_start_game?(player_alias) do
    # En una implementación real, verificaríamos si es el creador
    # Para el MVP, permitimos que cualquier jugador inicie el juego
    true
  end

  @doc """
  Determina si es turno del jugador.
  """
  def is_player_turn?(player_alias, team) do
    if team do
      {:ok, game_state} = GameServer.get_game_state()
      player_for_turn = next_player_for_team(game_state, team)

      player_for_turn && player_for_turn.alias == player_alias
    else
      false
    end
  end

  @doc """
  Inicia el juego.
  """
  def start_game() do
    IO.puts("\n#{IO.ANSI.bright()}Iniciando el juego...#{IO.ANSI.reset()}")

    {:ok, game_state} = GameServer.start_game()

    IO.puts("El juego ha comenzado! Turno: #{game_state.turn_number}")
    IO.puts("\nPresiona Enter para continuar...")
    IO.gets("")
  end

  @doc """
  Permite al jugador ejecutar su turno de juego.
  """
  def play_turn(player_alias, team) do
    IO.puts("\n#{IO.ANSI.bright()}Es tu turno de lanzar los dados!#{IO.ANSI.reset()}")
    IO.puts("Selecciona el tipo de dado:")
    IO.puts("1. 2 + 1d4 (Mínimo riesgo, rango 3-6)")
    IO.puts("2. 1 + 1d6 (Riesgo medio, rango 2-7)")
    IO.puts("3. 1d10 (Máximo riesgo, rango 1-10)")

    dice_option = get_input("\nSelecciona (1-3): ")

    dice_type = case dice_option do
      "1" -> "d4"
      "2" -> "d6"
      "3" -> "d10"
      _ -> "d6"  # Valor por defecto
    end

    {:ok, player} = PlayerRegistry.get_player(player_alias)

    # Determinar el valor y lanzar el dado
    {min_value, max_faces} = case dice_type do
      "d4" -> {2, 4}  # 2 + 1d4
      "d6" -> {1, 6}  # 1 + 1d6
      "d10" -> {0, 10} # 1d10
      _ -> {0, 6}  # Por defecto, 1d6
    end

    # Lanzar el dado
    result = min_value + :rand.uniform(max_faces)

    # Actualizar puntuación
    {:ok, updated_state} = GameServer.update_score(team, result)

    # Registrar que este jugador ya jugó
    GameServer.register_turn(team, player_alias)

    # Registrar en el log
    GRPCLogger.log_event(%{
      timestamp: System.system_time(:second),
      id_instancia: updated_state.instance_id,
      marcador: "INICIO",
      ip: player.address,
      alias: player_alias,
      accion: "roll_dice",
      args: Jason.encode!(%{
        team: team,
        dice_type: dice_type
      })
    })

    # Distribuir el mensaje a todos los jugadores
    MessageDistribution.distribute_message(
      %{
        type: :roll_dice,
        player_alias: player_alias,
        team: team,
        points: result,
        new_score: Map.get(updated_state.team_scores, team)
      },
      PlayerRegistry.get_players()
    )

    # Mostrar resultado
    IO.puts("\n#{IO.ANSI.bright()}Resultado del dado:#{IO.ANSI.reset()} #{result}")
    IO.puts("Nueva puntuación para #{team}: #{Map.get(updated_state.team_scores, team)}")

    # Verificar si el juego ha terminado
    if updated_state.status == :finished do
      GameServer.end_game(team)
      IO.puts("\n#{IO.ANSI.bright()}¡El equipo #{team} ha ganado el juego!#{IO.ANSI.reset()}")
      IO.puts("Puntuación final: #{Map.get(updated_state.team_scores, team)}")
    end

    IO.puts("\nPresiona Enter para continuar...")
    IO.gets("")
  end

  # Obtiene el próximo jugador que debe jugar para un equipo
  defp next_player_for_team(game_state, team) do
    team_players = PlayerRegistry.get_players_by_team(team)
    GameServer.select_player_for_turn(team)
    |> elem(1)
  end

  # Función auxiliar para solicitar entrada al usuario
  defp get_input(prompt) do
    IO.write(prompt)
    IO.gets("") |> String.trim()
  end
end
