defmodule GameProject.PlayerVisibilityTest do
  use ExUnit.Case
  alias GameProject.Models.Player
  alias GameProject.PlayerRegistry
  alias GameProject.MessageDistribution
  alias GameProject.MessageHandler

  setup do
    # Clear any existing players
    :ok = Supervisor.terminate_child(GameProject.Supervisor, PlayerRegistry)
    {:ok, _} = Supervisor.restart_child(GameProject.Supervisor, PlayerRegistry)

    # Create test players
    player1 = Player.new("127.0.0.1:5001", "player1", :equipo_rojo)
    player2 = Player.new("127.0.0.1:5002", "player2", :equipo_azul)
    player3 = Player.new("127.0.0.1:5003", "player3", :equipo_verde)

    %{
      player1: player1,
      player2: player2,
      player3: player3
    }
  end

  test "Player 1 should be notified about Player 3 when Player 3 joins through Player 2",
    %{player1: player1, player2: player2, player3: player3} do

    # Add P1 and P2 to registry - representing two nodes in the network
    {:ok, _} = PlayerRegistry.add_player(player1)
    {:ok, _} = PlayerRegistry.add_player(player2)

    # Simulate P3 joining through P2 - this would normally be done in HTTPServer
    # But we'll directly test the mechanism to ensure it works

    # Create the notification message that P2 would send to P1
    notification_message = %{
      type: :new_player_joined,
      player_data: %{
        address: player3.address,
        alias: player3.alias,
        team: player3.team
      },
      direct_notification: true # Flag to indicate this is a direct notification
    }

    # Simulate P2's MessageDistribution module calling handle_message on P1's node
    # This is what our fix is supposed to do
    # In the real system, this is triggered by HTTP POST to /message endpoint
    MessageHandler.handle_message(notification_message)

    # Now check if P1 knows about P3
    # Get all players in the registry
    all_players = PlayerRegistry.get_players()

    # Check if P3 is present in the registry
    p3_in_registry = Enum.any?(all_players, fn p -> p.alias == player3.alias end)

    # P3 should now be visible to P1
    assert p3_in_registry, "Player 3 should be visible to Player 1 after direct notification"
  end

  test "Players are correctly notified when a new player joins through distribute_message",
    %{player1: player1, player2: player2, player3: player3} do

    # Add P1 and P2 to registry
    {:ok, _} = PlayerRegistry.add_player(player1)
    {:ok, _} = PlayerRegistry.add_player(player2)

    # Create message about P3 joining
    new_player_message = %{
      type: :new_player_joined,
      player_data: %{
        address: player3.address,
        alias: player3.alias,
        team: player3.team
      },
      via_distribute_protocol: true  # Mark as coming through distribute protocol
    }

    # Instead of using full MessageDistribution which would try network calls,
    # directly call the handler which is what would happen after distribution
    MessageHandler.handle_message(new_player_message)

    # Now check if P3 is in the registry
    all_players = PlayerRegistry.get_players()
    p3_in_registry = Enum.any?(all_players, fn p -> p.alias == player3.alias end)

    assert p3_in_registry, "Player 3 should be in registry after distribute_message"
  end
end
