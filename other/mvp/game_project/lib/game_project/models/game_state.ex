defmodule GameProject.Models.GameState do
  @moduledoc """
  Estructura que define el estado de juego.
  """

  alias GameProject.Models.Player

  defstruct [
    # ID único de la instancia del juego
    instance_id: nil,
    # Número del turno actual
    turn_number: 0,
    # Mapa que asocia cada equipo con su puntaje actual
    team_scores: %{},
    # Registro de qué jugadores ya han participado en el turno actual
    turns_played: %{},
    # Puntuación máxima para ganar
    max_score: 100,
    # Estado actual del juego (:waiting, :in_progress, :finished)
    status: :waiting,
    # Equipos disponibles en el juego
    available_teams: [],
    # Máximo jugadores por equipo
    max_players_per_team: 5
  ]

  @doc """
  Crea un nuevo estado de juego con los parámetros especificados.
  """
  def new(max_score, teams, max_players_per_team) do
    instance_id = :rand.uniform(999_999)
    team_scores = Enum.reduce(teams, %{}, fn team, acc -> Map.put(acc, team, 0) end)
    turns_played = Enum.reduce(teams, %{}, fn team, acc -> Map.put(acc, team, []) end)

    %__MODULE__{
      instance_id: instance_id,
      max_score: max_score,
      team_scores: team_scores,
      turns_played: turns_played,
      available_teams: teams,
      max_players_per_team: max_players_per_team
    }
  end

  @doc """
  Actualiza el puntaje de un equipo después de un lanzamiento de dado.
  """
  def update_score(game_state, team, points) do
    new_score = Map.get(game_state.team_scores, team, 0) + points

    # Verificar si el juego ha terminado
    status = if new_score >= game_state.max_score, do: :finished, else: game_state.status

    %__MODULE__{
      game_state |
      team_scores: Map.put(game_state.team_scores, team, new_score),
      status: status
    }
  end

  @doc """
  Registra que un jugador ha jugado su turno
  """
  def register_turn_played(game_state, team, player_alias) do
    players_played = Map.get(game_state.turns_played, team, [])
    updated_players = [player_alias | players_played]

    %__MODULE__{
      game_state |
      turns_played: Map.put(game_state.turns_played, team, updated_players)
    }
  end

  @doc """
  Avanza al siguiente turno y reinicia los registros si todos han jugado
  """
  def next_turn(game_state, players_by_team) do
    all_played = Enum.all?(game_state.available_teams, fn team ->
      team_members = Map.get(players_by_team, team, [])
      team_members_played = Map.get(game_state.turns_played, team, [])

      # Si el equipo está vacío, considerarlo como "todos han jugado"
      Enum.empty?(team_members) ||
        Enum.all?(team_members, fn player -> player.alias in team_members_played end)
    end)

    if all_played do
      # Reiniciar el registro de turnos jugados y avanzar al siguiente turno
      turns_played = Enum.reduce(game_state.available_teams, %{}, fn team, acc ->
        Map.put(acc, team, [])
      end)

      %__MODULE__{
        game_state |
        turn_number: game_state.turn_number + 1,
        turns_played: turns_played
      }
    else
      game_state
    end
  end

  @doc """
  Selecciona un jugador que no haya jugado en este turno
  """
  def select_player_for_turn(game_state, team, players) do
    team_players = Enum.filter(players, fn player -> player.team == team end)
    players_played = Map.get(game_state.turns_played, team, [])

    # Filtrar jugadores que aún no han jugado
    available_players = Enum.filter(team_players, fn player ->
      player.alias not in players_played
    end)

    if Enum.empty?(available_players) do
      nil
    else
      Enum.random(available_players)
    end
  end
end
