defmodule GameProject.PlayerRegistryTest do
  use ExUnit.Case

  alias GameProject.PlayerRegistry
  alias GameProject.Models.Player

  setup do
    PlayerRegistry.reset()
    :ok
  end
  test "agregar y obtener jugadores" do
    # Crear y añadir un nuevo jugador
    player = Player.new("127.0.0.1:8080", "player1")
    assert {:ok, _} = PlayerRegistry.add_player(player)

    # Verificar que podemos obtener el jugador
    {:ok, retrieved_player} = PlayerRegistry.get_player("player1")
    assert retrieved_player.alias == "player1"
    assert retrieved_player.address == "127.0.0.1:8080"
    assert retrieved_player.team == nil
  end
  test "actualizar jugador" do
    # Crear y añadir un jugador
    player = Player.new("127.0.0.1:8080", "player2")
    assert {:ok, _} = PlayerRegistry.add_player(player)

    # Actualizar el equipo del jugador
    {:ok, updated_player} = PlayerRegistry.update_player("player2", %{team: :equipo_rojo})

    # Verificar la actualización
    assert updated_player.team == :equipo_rojo

    # Verificar que se actualizó en el registro
    {:ok, retrieved_player} = PlayerRegistry.get_player("player2")
    assert retrieved_player.team == :equipo_rojo
  end
  test "eliminar jugador" do
    # Crear y añadir un jugador
    player = Player.new("127.0.0.1:8080", "player3")
    assert {:ok, _} = PlayerRegistry.add_player(player)

    # Eliminar el jugador
    assert {:ok, _} = PlayerRegistry.remove_player("player3")

    # Verificar que ya no existe
    assert {:error, _} = PlayerRegistry.get_player("player3")
  end

  test "obtener jugadores por equipo" do
    # Crear y añadir jugadores
    player1 = Player.new("127.0.0.1:8081", "player4")
    player2 = Player.new("127.0.0.1:8082", "player5")
    player3 = Player.new("127.0.0.1:8083", "player6")    # Añadir jugadores
    assert {:ok, _} = PlayerRegistry.add_player(player1)
    assert {:ok, _} = PlayerRegistry.add_player(player2)
    assert {:ok, _} = PlayerRegistry.add_player(player3)

    # Actualizar equipos
    {:ok, _} = PlayerRegistry.update_player("player4", %{team: :equipo_rojo})
    {:ok, _} = PlayerRegistry.update_player("player5", %{team: :equipo_rojo})
    {:ok, _} = PlayerRegistry.update_player("player6", %{team: :equipo_azul})

    # Verificar jugadores por equipo
    red_team = PlayerRegistry.get_players_by_team(:equipo_rojo)
    blue_team = PlayerRegistry.get_players_by_team(:equipo_azul)

    assert length(red_team) == 2
    assert length(blue_team) == 1

    # Verificar que los jugadores están en los equipos correctos
    assert Enum.any?(red_team, fn p -> p.alias == "player4" end)
    assert Enum.any?(red_team, fn p -> p.alias == "player5" end)
    assert Enum.any?(blue_team, fn p -> p.alias == "player6" end)
  end
end
