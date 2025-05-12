defmodule GameProject.GameServer do
  @moduledoc """
  Servidor GenServer para gestionar el estado del juego.
  """

  use GenServer
  alias GameProject.Models.GameState
  alias GameProject.GRPCLogger
  alias GameProject.MessageDistribution
  alias GameProject.PlayerRegistry

  @turn_timeout 10_000  # 10 segundos para realizar acción

  # API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def create_game(max_score, teams, max_players_per_team) do
    GenServer.call(__MODULE__, {:create_game, max_score, teams, max_players_per_team})
  end

  def get_game_state() do
    GenServer.call(__MODULE__, :get_game_state)
  end

  def update_score(team, points) do
    GenServer.call(__MODULE__, {:update_score, team, points})
  end

  def register_turn(team, player_alias) do
    GenServer.call(__MODULE__, {:register_turn, team, player_alias})
  end

  def select_player_for_turn(team) do
    GenServer.call(__MODULE__, {:select_player_for_turn, team})
  end

  def next_turn() do
    GenServer.call(__MODULE__, :next_turn)
  end

  def start_game() do
    GenServer.call(__MODULE__, :start_game)
  end
  def end_game(winning_team) do
    GenServer.call(__MODULE__, {:end_game, winning_team})
  end

  def set_game_state(game_config) do
    GenServer.call(__MODULE__, {:set_game_state, game_config})
  end

  # Callbacks

  @impl true
  def init(_opts) do
    {:ok, nil}
  end

  @impl true
  def handle_call({:create_game, max_score, teams, max_players_per_team}, _from, _state) do
    game_state = GameState.new(max_score, teams, max_players_per_team)

    # Log de creación de juego
    GRPCLogger.log_event(%{
      timestamp: System.system_time(:second),
      id_instancia: game_state.instance_id,
      marcador: "INICIO",
      ip: GameProject.Network.get_local_ip(),
      alias: "system",
      accion: "create_network",
      args: Jason.encode!(%{
        max_score: max_score,
        teams: teams,
        max_players_per_team: max_players_per_team
      })
    })

    {:reply, {:ok, game_state}, game_state}
  end

  @impl true
  def handle_call(:get_game_state, _from, game_state) do
    if game_state do
      {:reply, {:ok, game_state}, game_state}
    else
      {:reply, {:error, :no_game_state}, game_state}
    end
  end

  @impl true
  def handle_call({:update_score, team, points}, _from, game_state) do
    if game_state do
      updated_state = GameState.update_score(game_state, team, points)
      # Distribuir la actualización de puntuación y loguear fuera del GenServer.call
      spawn(fn ->
        MessageDistribution.distribute_message(
          %{type: :score_update, team: team, points: points, new_score: Map.get(updated_state.team_scores, team)},
          GameProject.PlayerRegistry.get_players()
        )
        GRPCLogger.log_event(%{
          timestamp: System.system_time(:second),
          id_instancia: game_state.instance_id,
          marcador: "FIN",
          ip: GameProject.Network.get_local_ip(),
          alias: "system",
          accion: "roll_dice",
          args: Jason.encode!(%{
            team: team,
            points: points,
            new_score: Map.get(updated_state.team_scores, team)
          })
        })
      end)
      {:reply, {:ok, updated_state}, updated_state}
    else
      {:reply, {:error, :no_game_state}, game_state}
    end
  end

  @impl true
  def handle_call({:register_turn, team, player_alias}, _from, game_state) do
    if game_state do
      updated_state = GameState.register_turn_played(game_state, team, player_alias)
      {:reply, :ok, updated_state}
    else
      {:reply, {:error, :no_game_state}, game_state}
    end
  end

  @impl true
  def handle_call({:select_player_for_turn, team}, _from, game_state) do
    if game_state do
      players_by_team = GameProject.PlayerRegistry.get_players_by_team(team)
      player = GameState.select_player_for_turn(game_state, team, players_by_team)
      {:reply, {:ok, player}, game_state}
    else
      {:reply, {:error, :no_game_state}, game_state}
    end
  end
  @impl true
  def handle_call(:next_turn, _from, game_state) do
    if game_state do
      players_grouped = PlayerRegistry.get_players_grouped_by_team()
      updated_state = GameState.next_turn(game_state, players_grouped)

      # Programar el siguiente turno automáticamente
      if updated_state.status == :in_progress do
        schedule_turn_timeout()
      end

      {:reply, {:ok, updated_state}, updated_state}
    else
      {:reply, {:error, :no_game_state}, game_state}
    end
  end

  @impl true
  def handle_call(:start_game, _from, game_state) do
    if game_state do
      updated_state = %GameState{game_state | status: :in_progress, turn_number: 1}

      # Notificar a todos los jugadores que el juego ha comenzado
      MessageDistribution.distribute_message(
        %{type: :game_started, turn_number: 1},
        PlayerRegistry.get_players()
      )

      # Programar timeout para el primer turno
      schedule_turn_timeout()

      # Log de inicio de juego
      GRPCLogger.log_event(%{
        timestamp: System.system_time(:second),
        id_instancia: updated_state.instance_id,
        marcador: "INICIO",
        ip: GameProject.Network.get_local_ip(),
        alias: "system",
        accion: "game_started",
        args: Jason.encode!(%{
          teams: updated_state.available_teams,
          max_score: updated_state.max_score,
          players: length(PlayerRegistry.get_players())
        })
      })

      {:reply, {:ok, updated_state}, updated_state}
    else
      {:reply, {:error, :no_game_state}, game_state}
    end
  end
  @impl true
  def handle_call({:end_game, winning_team}, _from, game_state) do
    if game_state do
      updated_state = %GameState{game_state | status: :finished}

      # Notificar a todos los jugadores que el juego ha terminado
      MessageDistribution.distribute_message(
        %{
          type: :game_ended,
          winning_team: winning_team,
          final_score: Map.get(game_state.team_scores, winning_team)
        },
        PlayerRegistry.get_players()
      )

      # Log de finalización de juego
      GRPCLogger.log_event(%{
        timestamp: System.system_time(:second),
        id_instancia: updated_state.instance_id,
        marcador: "FIN",
        ip: GameProject.Network.get_local_ip(),
        alias: "system",
        accion: "game_finished",
        args: Jason.encode!(%{
          winning_team: winning_team,
          final_score: Map.get(game_state.team_scores, winning_team)
        })
      })

      {:reply, {:ok, updated_state}, updated_state}
    else
      {:reply, {:error, :no_game_state}, game_state}
    end
  end

  @impl true
  def handle_call({:set_game_state, game_config}, _from, _game_state) do
    # Create a new GameState from the received configuration
    instance_id = Map.get(game_config, "instance_id", :rand.uniform(999_999))
    available_teams = Map.get(game_config, "available_teams", [])
    max_score = Map.get(game_config, "max_score", 100)
    max_players_per_team = Map.get(game_config, "max_players_per_team", 5)
    status = Map.get(game_config, "status", :waiting) |> maybe_convert_to_atom()

    # Convert string teams to atoms if necessary
    available_teams = convert_teams_to_atoms(available_teams)

    # Build team_scores and turns_played maps
    team_scores = Enum.reduce(available_teams, %{}, fn team, acc -> Map.put(acc, team, 0) end)
    turns_played = Enum.reduce(available_teams, %{}, fn team, acc -> Map.put(acc, team, []) end)

    # Create the game state
    game_state = %GameState{
      instance_id: instance_id,
      turn_number: 0,
      team_scores: team_scores,
      turns_played: turns_played,
      max_score: max_score,
      status: status,
      available_teams: available_teams,
      max_players_per_team: max_players_per_team
    }

    {:reply, {:ok, game_state}, game_state}
  end

  # Helper to ensure status is an atom
  defp maybe_convert_to_atom(status) when is_binary(status), do: String.to_atom(status)
  defp maybe_convert_to_atom(status) when is_atom(status), do: status

  # Helper to convert team names to atoms
  defp convert_teams_to_atoms(teams) do
    Enum.map(teams, fn
      team when is_binary(team) -> String.to_atom(team)
      team when is_atom(team) -> team
    end)
  end

  @impl true
  def handle_info(:turn_timeout, game_state) do
    if game_state && game_state.status == :in_progress do
      # Avanzar al siguiente turno automáticamente
      players_grouped = PlayerRegistry.get_players_grouped_by_team()
      updated_state = GameState.next_turn(game_state, players_grouped)

      # Notificar a todos que el turno ha cambiado
      MessageDistribution.distribute_message(
        %{type: :turn_timeout, new_turn_number: updated_state.turn_number},
        PlayerRegistry.get_players()
      )

      # Programar el siguiente timeout
      schedule_turn_timeout()

      {:noreply, updated_state}
    else
      {:noreply, game_state}
    end
  end

  # Programar un timeout para el turno actual
  defp schedule_turn_timeout() do
    Process.send_after(self(), :turn_timeout, @turn_timeout)
  end
end
