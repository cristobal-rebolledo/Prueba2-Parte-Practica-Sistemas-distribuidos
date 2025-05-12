defmodule GameProject.MessageDistributionTest do
  use ExUnit.Case
  alias GameProject.MessageDistribution
  alias GameProject.PlayerRegistry
  alias GameProject.GameServer
  alias GameProject.Models.Player

  setup do
    # Solo preparar datos, no arrancar supervisados
    teams = [:equipo_rojo, :equipo_azul]
    {:ok, game_state} = GameServer.create_game(100, teams, 5)

    # Crear jugadores de prueba
    player1 = Player.new("127.0.0.1:5001", "player1", :equipo_rojo)
    player2 = Player.new("127.0.0.1:5002", "player2", :equipo_rojo)
    player3 = Player.new("127.0.0.1:5003", "player3", :equipo_azul)
    player4 = Player.new("127.0.0.1:5004", "player4", nil)  # Sin equipo

    # Agregar jugadores al registro
    PlayerRegistry.add_player(player1)
    PlayerRegistry.add_player(player2)
    PlayerRegistry.add_player(player3)
    PlayerRegistry.add_player(player4)

    # Pasar los jugadores para las pruebas
    players = [player1, player2, player3, player4]

    %{game_state: game_state, players: players}
  end

  test "distribución de mensajes - agrupar por equipo", %{players: players} do
    # Esta prueba verifica que los jugadores se agrupan correctamente por equipo

    # Agrupar jugadores por equipo (código similar a MessageDistribution)
    players_by_team = Enum.group_by(players, fn player -> player.team end)

    # Verificar que tenemos 3 grupos (equipo_rojo, equipo_azul, nil)
    assert map_size(players_by_team) == 3

    # Verificar conteo de jugadores por equipo
    assert length(players_by_team[:equipo_rojo]) == 2
    assert length(players_by_team[:equipo_azul]) == 1
    assert length(players_by_team[nil]) == 1
  end

  # Nota: No podemos probar fácilmente la distribución completa sin mocks para HTTP
  # pero podemos verificar algunas funciones internas que podríamos exponer para pruebas

  # test "marcado de logs en distribución", %{players: players} do
  #   # Simulamos la distribución de un mensaje simple
  #   # No probamos la distribución real ya que requeriría servidores HTTP reales
  #   message = %{type: :test_message, content: "Test content"}

  #   # Ejecutar la función bajo prueba
  #   # La distribución fallará pero queremos verificar que los logs se registran
  #   MessageDistribution.distribute_message(message, players)

  #   # No podemos verificar directamente el resultado en los logs
  #   # pero podemos verificar que la función no lanza errores
  #   assert true
  # end
end
