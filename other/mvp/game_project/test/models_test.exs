defmodule GameProject.ModelsTest do
  use ExUnit.Case
  alias GameProject.Models.Player
  alias GameProject.Models.GameState

  describe "Player" do
    test "create new player" do
      player = Player.new("192.168.1.1:4000", "player1")
      assert player.address == "192.168.1.1:4000"
      assert player.alias == "player1"
      assert player.team == nil
      assert is_integer(player.secret_number)
      assert is_integer(player.secret_number)
    end

    test "update player team" do
      player = Player.new("192.168.1.1:4000", "player1")
      updated = Player.update_team(player, :equipo_dragon)
      assert updated.team == :equipo_dragon
    end

    test "remove secret number" do
      player = Player.new("192.168.1.1:4000", "player1")
      assert player.secret_number != nil

      public_player = Player.without_secret(player)
      assert public_player.secret_number == nil
      assert public_player.alias == player.alias
    end
  end

  describe "GameState" do
    test "create new game state" do
      teams = [:equipo_dragon, :equipo_planta]
      game_state = GameState.new(100, teams, 5)

      assert game_state.max_score == 100
      assert game_state.available_teams == teams
      assert game_state.max_players_per_team == 5
      assert game_state.status == :waiting
      assert game_state.turn_number == 0
      assert map_size(game_state.team_scores) == 2
      assert Enum.all?(game_state.team_scores, fn {_, score} -> score == 0 end)
    end

    test "update score" do
      teams = [:equipo_dragon, :equipo_planta]
      game_state = GameState.new(100, teams, 5)

      # Actualizar puntuación de equipo_dragon
      updated = GameState.update_score(game_state, :equipo_dragon, 20)
      assert updated.team_scores[:equipo_dragon] == 20
      assert updated.status == :waiting  # no se alcanzó la puntuación máxima

      # Alcanzar puntuación máxima
      final_update = GameState.update_score(updated, :equipo_dragon, 100)
      assert final_update.team_scores[:equipo_dragon] == 120
      assert final_update.status == :finished
    end

    test "track turns played" do
      teams = [:equipo_dragon, :equipo_planta]
      game_state = GameState.new(100, teams, 5)

      # Registrar que player1 ha jugado para equipo_dragon
      updated = GameState.register_turn_played(game_state, :equipo_dragon, "player1")
      assert "player1" in updated.turns_played[:equipo_dragon]

      # Registrar que player2 ha jugado para equipo_planta
      updated = GameState.register_turn_played(updated, :equipo_planta, "player2")
      assert "player2" in updated.turns_played[:equipo_planta]
    end
  end
end
