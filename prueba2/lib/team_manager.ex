defmodule Prueba2.TeamManager do
  @moduledoc """
  Gestor de equipos para el juego de dados - versión simplificada.
  Solo el creador inicial puede definir equipos, los demás nodos solo pueden unirse.
  """

  use GenServer
  import IO.ANSI
  alias Prueba2.P2PNetwork

  # Colores para mensajes de equipo
  @team_color cyan()
  @reset reset()

  # Helper functions for safe operations
  defp safe_size(collection) when is_map(collection), do: map_size(collection)
  defp safe_size(collection) when is_list(collection), do: length(collection)
  defp safe_size(_), do: 0

  # API Pública
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  # Solo el creador de la red puede inicializar equipos
  def initialize_teams(teams, max_players_per_team), do:
    GenServer.call(__MODULE__, {:initialize_teams, teams, max_players_per_team})

  # Para el nodo que recibe equipos de la red
  def sync_teams_from_network(teams_data), do:
    GenServer.call(__MODULE__, {:sync_teams_from_network, teams_data})

  # Unirse a un equipo
  def join_team(player_name, team_name), do:
    GenServer.call(__MODULE__, {:join_team, player_name, team_name})

  # Métodos para el juego
  def set_team_ready(team_name), do: GenServer.call(__MODULE__, {:set_team_ready, team_name})
  def get_teams, do: GenServer.call(__MODULE__, :get_teams)
  def get_team_position(team_name), do: GenServer.call(__MODULE__, {:get_team_position, team_name})
  def update_team_position(team_name, position), do: GenServer.cast(__MODULE__, {:update_team_position, team_name, position})
  def all_teams_ready?, do: GenServer.call(__MODULE__, :all_teams_ready)
  def reset_teams, do: GenServer.cast(__MODULE__, :reset_teams)

  # Notificaciones a otros nodos
  def notify_player_joined(player_name, team_name) do
    P2PNetwork.get_peers()
    |> Enum.each(fn {address, _} ->
      Task.start(fn ->
        url = "http://#{address}/api/team-membership-update"
        payload = %{player_name: player_name, team_name: team_name}
        try do
          HTTPoison.post!(url, Jason.encode!(payload), [{"Content-Type", "application/json"}], [timeout: 5_000])
        rescue
          _ -> nil
        end
      end)
    end)
  end

  # Callbacks de GenServer
  @impl true
  def init(_) do
    {:ok, %{
      teams: %{},
      max_players_per_team: 3
    }}
  end

  @impl true
  def handle_call({:initialize_teams, teams, max_players}, _from, state) do
    if map_size(state.teams) > 0 do
      {:reply, {:error, "Los equipos ya han sido inicializados"}, state}
    else
      # Crear los equipos iniciales
      initialized_teams = Enum.map(teams, fn team_name ->
        {team_name, %{
          players: MapSet.new(),
          position: 0,
          ready: false
        }}
      end) |> Enum.into(%{})

      # Asignar el creador al primer equipo
      creator_name = Application.get_env(:prueba2, :username)
      first_team = List.first(teams)
      updated_teams = if first_team do
        first_team_info = Map.get(initialized_teams, first_team)
        updated_team = %{first_team_info | players: MapSet.put(first_team_info.players, creator_name)}
        Map.put(initialized_teams, first_team, updated_team)
      else
        initialized_teams
      end

      broadcast_team_event("Sistema de equipos inicializado")
      if first_team, do: broadcast_team_event("#{creator_name} se ha unido al equipo #{first_team}")

      # Intentar actualizar la información del peer
      try do
        if first_team do
          P2PNetwork.update_peer_team(Application.get_env(:prueba2, :address), first_team)
        end
      rescue
        _ -> nil
      end

      {:reply, {:ok, "Equipos inicializados"}, %{state | teams: updated_teams, max_players_per_team: max_players}}
    end
  end

  @impl true
  def handle_call({:join_team, player_name, team_name}, _from, state) do
    case Map.fetch(state.teams, team_name) do
      {:ok, team} ->
        cond do
          # Verificar si el jugador ya está en algún equipo
          Enum.any?(state.teams, fn {_, team_info} ->
            MapSet.member?(team_info.players, player_name)
          end) ->
            {:reply, {:error, "Ya estás en un equipo"}, state}

          # Verificar si el equipo está lleno
          MapSet.size(team.players) >= state.max_players_per_team ->
            {:reply, {:error, "El equipo está lleno (máximo #{state.max_players_per_team} jugadores)"}, state}

          # Unir al jugador al equipo
          true ->
            updated_team = %{team | players: MapSet.put(team.players, player_name)}
            new_teams = Map.put(state.teams, team_name, updated_team)

            broadcast_team_event("#{player_name} se unió al equipo #{team_name}")
            notify_player_joined(player_name, team_name)

            # Actualizar la información del peer si se trata de un usuario local
            try do
              P2PNetwork.update_peer_team(Application.get_env(:prueba2, :address), team_name)
            rescue
              _ -> nil
            end

            {:reply, {:ok, "Te has unido al equipo #{team_name}"}, %{state | teams: new_teams}}
        end

      :error ->
        {:reply, {:error, "El equipo no existe"}, state}
    end
  end

  @impl true
  def handle_call({:set_team_ready, team_name}, _from, state) do
    case Map.fetch(state.teams, team_name) do
      {:ok, team} ->
        if MapSet.size(team.players) == 0 do
          {:reply, {:error, "El equipo no tiene jugadores"}, state}
        else
          updated_team = %{team | ready: true}
          new_teams = Map.put(state.teams, team_name, updated_team)
          broadcast_team_event("El equipo #{team_name} está listo")
          {:reply, {:ok, "Equipo listo para iniciar"}, %{state | teams: new_teams}}
        end
      :error ->
        {:reply, {:error, "El equipo no existe"}, state}
    end
  end

  @impl true
  def handle_call(:get_teams, _from, state) do
    teams_info = Enum.map(state.teams, fn {name, info} ->
      {name, %{
        players: MapSet.to_list(info.players),
        position: info.position,
        ready: info.ready
      }}
    end) |> Enum.into(%{})
    {:reply, teams_info, state}
  end

  @impl true
  def handle_call({:get_team_position, team_name}, _from, state) do
    case Map.fetch(state.teams, team_name) do
      {:ok, team} -> {:reply, {:ok, team.position}, state}
      :error -> {:reply, {:error, "El equipo no existe"}, state}
    end
  end

  @impl true
  def handle_call(:all_teams_ready, _from, state) do
    teams_with_players = Enum.filter(state.teams, fn {_, team_info} ->
      MapSet.size(team_info.players) > 0
    end)

    all_ready = Enum.all?(teams_with_players, fn {_, team_info} -> team_info.ready end)
    enough_teams = safe_size(teams_with_players) >= 2

    {:reply, all_ready && enough_teams, state}
  end
  @impl true
  def handle_call({:sync_teams_from_network, teams_data}, _from, state) do
    # Ensure teams_data is a map before processing
    teams_data_map = cond do
      is_list(teams_data) -> Enum.into(teams_data, %{})
      is_map(teams_data) -> teams_data
      true -> %{}
    end

    new_state = Enum.reduce(teams_data_map, state, fn {team_name, team_info}, current_state ->
      if not Map.has_key?(current_state.teams, team_name) do
        # Handle both string and atom keys for compatibility
        players = cond do
          is_map(team_info) && Map.has_key?(team_info, "players") -> team_info["players"]
          is_map(team_info) && Map.has_key?(team_info, :players) -> team_info.players
          true -> []
        end

        position = cond do
          is_map(team_info) && Map.has_key?(team_info, "position") -> team_info["position"]
          is_map(team_info) && Map.has_key?(team_info, :position) -> team_info.position
          true -> 0
        end

        ready = cond do
          is_map(team_info) && Map.has_key?(team_info, "ready") -> team_info["ready"]
          is_map(team_info) && Map.has_key?(team_info, :ready) -> team_info.ready
          true -> false
        end

        new_team = %{
          players: MapSet.new(players),
          position: position,
          ready: ready
        }
        new_teams = Map.put(current_state.teams, team_name, new_team)
        %{current_state | teams: new_teams}
      else
        current_state
      end
    end)

    {:reply, {:ok, "Equipos sincronizados"}, new_state}
  end

  @impl true
  def handle_cast({:update_team_position, team_name, position}, state) do
    case Map.fetch(state.teams, team_name) do
      {:ok, team} ->
        updated_team = %{team | position: position}
        new_teams = Map.put(state.teams, team_name, updated_team)
        {:noreply, %{state | teams: new_teams}}
      :error ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:reset_teams, state) do
    reset_teams = Enum.map(state.teams, fn {name, team} ->
      {name, %{team | position: 0, ready: false}}
    end) |> Enum.into(%{})

    {:noreply, %{state | teams: reset_teams}}
  end

  # Utilidades
  defp broadcast_team_event(message) do
    IO.puts(@team_color <> "[EQUIPO] " <> @reset <> message)
  end
end
