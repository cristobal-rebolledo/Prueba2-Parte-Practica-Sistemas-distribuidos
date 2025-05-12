defmodule DistribuyeProtocolTest do
  use ExUnit.Case

  alias GameProject.Models.Player
  alias GameProject.PlayerRegistry
  alias GameProject.MessageDistribution
  alias GameProject.Network

  setup do
    # Reiniciar el registro de jugadores antes de cada prueba
    PlayerRegistry.clear()

    # Agregar jugadores de prueba con diferentes equipos
    player1 = %Player{alias: "jugador1", address: "192.168.0.1", team: :equipo_rojo, secret_number: 12345}
    player2 = %Player{alias: "jugador2", address: "192.168.0.2", team: :equipo_rojo, secret_number: 23456}
    player3 = %Player{alias: "jugador3", address: "192.168.0.3", team: :equipo_azul, secret_number: 34567}
    player4 = %Player{alias: "jugador4", address: Network.get_local_ip(), team: :equipo_azul, secret_number: 45678}

    PlayerRegistry.add_player(player1)
    PlayerRegistry.add_player(player2)
    PlayerRegistry.add_player(player3)
    PlayerRegistry.add_player(player4)

    :ok
  end

  # Prueba el protocolo "distribuye" para mensajes player_joined_team
  test "distribuye message protocol correctly processes player_joined_team message" do
    # Mock para Network.http_post para simular envíos exitosos
    :meck.new(GameProject.Network, [:passthrough])
    :meck.expect(GameProject.Network, :http_post, fn _url, body, _headers, _opts ->
      IO.puts("Mensaje enviado simulado: #{body}")
      {:ok, %HTTPoison.Response{status_code: 200}}
    end)

    # Creamos un mensaje de unión a equipo
    message = %{
      type: :player_joined_team,
      player_alias: "jugador4",
      team: :equipo_azul,
      timestamp: System.system_time(:millisecond)
    }

    # Obtenemos la lista de jugadores
    players = PlayerRegistry.get_players()

    # Distribuimos el mensaje usando el protocolo distribuye
    MessageDistribution.distribute_message(message, players)

    # Verificamos que el mensaje fue procesado correctamente
    # En un caso real esto verificaría el estado, pero aquí solo revisamos si el mock fue llamado
    assert :meck.num_calls(GameProject.Network, :http_post, :_) > 0

    # Limpiamos el mock
    :meck.unload(GameProject.Network)
  end
end
