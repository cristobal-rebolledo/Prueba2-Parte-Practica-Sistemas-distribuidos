defmodule GameProject.GameServerTest do
  use ExUnit.Case
  alias GameProject.GameServer
  alias GameProject.PlayerRegistry
  alias GameProject.Models.Player

  setup do
    PlayerRegistry.reset()
    # Solo preparar datos, no arrancar supervisados
    teams = [:equipo_dragon, :equipo_planta]
    {:ok, game_state} = GameServer.create_game(100, teams, 5)

    # Agregar algunos jugadores de prueba
    player1 = %{alias: "player1", address: "127.0.0.1:4000", team: :equipo_dragon, secret_number: 1234}
    player2 = %{alias: "player2", address: "127.0.0.1:4001", team: :equipo_dragon, secret_number: 5678}
    player3 = %{alias: "player3", address: "127.0.0.1:4002", team: :equipo_planta, secret_number: 9012}

    PlayerRegistry.add_player(player1)
    PlayerRegistry.add_player(player2)
    PlayerRegistry.add_player(player3)

    %{teams: teams, game_state: game_state}
  end

  test "crear juego", %{teams: teams} do
    max_score = 150
    max_players = 3

    {:ok, game_state} = GameServer.create_game(max_score, teams, max_players)

    assert game_state.max_score == max_score
    assert game_state.available_teams == teams
    assert game_state.max_players_per_team == max_players
    assert is_integer(game_state.instance_id)
    assert game_state.turn_number == 0
  end

  test "obtener estado del juego" do
    {:ok, game_state} = GameServer.get_game_state()
    assert game_state != nil
  end

  test "actualizar puntuación", %{teams: [team | _]} do
    points = 25
    {:ok, updated_state} = GameServer.update_score(team, points)

    assert updated_state.team_scores[team] == points
  end

  test "registrar turno jugado", %{teams: [team | _]} do
    player_alias = "player1"
    :ok = GameServer.register_turn(team, player_alias)

    {:ok, game_state} = GameServer.get_game_state()
    assert player_alias in game_state.turns_played[team]
  end

  test "seleccionar jugador para turno", %{teams: [team | _]} do
    {:ok, player} = GameServer.select_player_for_turn(team)

    assert player != nil
    assert player.team == team
  end

  test "avanzar al siguiente turno" do
    current_turn = GameServer.get_game_state() |> elem(1) |> Map.get(:turn_number)

    # Registrar que todos han jugado
    GameServer.register_turn(:equipo_dragon, "player1")
    GameServer.register_turn(:equipo_dragon, "player2")
    GameServer.register_turn(:equipo_planta, "player3")

    # Avanzar al siguiente turno
    {:ok, updated_state} = GameServer.next_turn()

    assert updated_state.turn_number == current_turn + 1
    assert updated_state.turns_played[:equipo_dragon] == []
    assert updated_state.turns_played[:equipo_planta] == []
  end
end
