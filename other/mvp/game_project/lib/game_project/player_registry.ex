defmodule GameProject.PlayerRegistry do
  @moduledoc """
  Módulo para gestionar la tabla de jugadores y sus datos.
  """

  use GenServer
  alias GameProject.Models.Player

  # API

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def add_player(player_data) do
    GenServer.call(__MODULE__, {:add_player, player_data})
  end

  def update_player(player_alias, updates) do
    GenServer.call(__MODULE__, {:update_player, player_alias, updates})
  end

  def remove_player(player_alias) do
    GenServer.call(__MODULE__, {:remove_player, player_alias})
  end
  def get_player(player_alias) do
    GenServer.call(__MODULE__, {:get_player, player_alias})
  end

  def get_player_by_address(address) do
    GenServer.call(__MODULE__, {:get_player_by_address, address})
  end

  def get_players() do
    GenServer.call(__MODULE__, :get_players)
  end

  def get_players_by_team(team) do
    GenServer.call(__MODULE__, {:get_players_by_team, team})
  end

  def get_players_without_team() do
    GenServer.call(__MODULE__, :get_players_without_team)
  end

  def get_players_grouped_by_team() do
    GenServer.call(__MODULE__, :get_players_grouped_by_team)
  end

  def reset() do
    GenServer.call(__MODULE__, :reset)
  end

  def clear() do
    GenServer.call(__MODULE__, :clear)
  end

  # Callbacks

  @impl true
  def init(_) do
    {:ok, %{players: %{}}}
  end

  @impl true
  def handle_call({:add_player, player_to_add}, _from, state) do
    # player_to_add is expected to be a Player struct.
    # The key in state.players is the player's alias.

    # Log the attempt to add/update.
    # Consider if alias should be immutable once registered, or if addresses should be unique identifiers.
    # For now, adding/updating by alias.
    # GRPCLogger.log_event_placeholder("PlayerRegistry: add_player_call", %{alias: player_to_add.alias, address: player_to_add.address})

    # Add or overwrite the player in the map.
    updated_players_map = Map.put(state.players, player_to_add.alias, player_to_add)
    updated_state = %{state | players: updated_players_map}

    # According to MessageHandler.handle_new_player_joined, it expects {:ok, added_player_struct}
    # So, we reply with the player struct that was added/updated.
    {:reply, {:ok, player_to_add}, updated_state}
  end

  @impl true
  def handle_call({:update_player, player_alias, updates}, _from, state) do
    case Map.get(state.players, player_alias) do
      nil ->
        {:reply, {:error, :player_not_found}, state}
      player ->
        updated_player = Enum.reduce(updates, player, fn {key, value}, acc ->
          Map.put(acc, key, value)
        end)

        updated_players = Map.put(state.players, player_alias, updated_player)
        {:reply, {:ok, updated_player}, %{state | players: updated_players}}
    end
  end

  @impl true
  def handle_call({:remove_player, player_alias}, _from, state) do
    case Map.pop(state.players, player_alias) do
      {nil, _} ->
        {:reply, {:error, :player_not_found}, state}
      {player, remaining_players} ->
        {:reply, {:ok, player}, %{state | players: remaining_players}}
    end
  end

  @impl true
  def handle_call({:get_player, player_alias}, _from, state) do
    case Map.get(state.players, player_alias) do
      nil -> {:reply, {:error, :player_not_found}, state}
      player -> {:reply, {:ok, player}, state}
    end
  end

  @impl true
  def handle_call({:get_player_by_address, address}, _from, state) do
    found_player =
      state.players
      |> Map.values()
      |> Enum.find(fn player -> player.address == address end)

    if found_player do
      {:reply, {:ok, found_player}, state}
    else
      {:reply, {:error, :player_not_found}, state}
    end
  end

  @impl true
  def handle_call(:get_players, _from, state) do
    {:reply, Map.values(state.players), state}
  end

  @impl true
  def handle_call({:get_players_by_team, team}, _from, state) do
    team_players = state.players
    |> Map.values()
    |> Enum.filter(fn player -> player.team == team end)

    {:reply, team_players, state}
  end

  @impl true
  def handle_call(:get_players_without_team, _from, state) do
    no_team_players = state.players
    |> Map.values()
    |> Enum.filter(fn player -> player.team == nil end)

    {:reply, no_team_players, state}
  end

  @impl true
  def handle_call(:get_players_grouped_by_team, _from, state) do
    grouped = state.players
    |> Map.values()
    |> Enum.reduce(%{nil => []}, fn player, acc ->
      Map.update(acc, player.team, [player], fn players -> [player | players] end)
    end)

    {:reply, grouped, state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{players: %{}}}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %{players: %{}}}
  end
end
