defmodule Prueba2.TeamManager do
  @moduledoc """
  Gestor de equipos para el juego de dados - versión simplificada.
  Ahora la lista de peers se obtiene siempre de P2PNetwork.
  """

  use GenServer
  import IO.ANSI
  alias Prueba2.P2PNetwork

  # Colores para mensajes de equipo
  @team_color cyan()
  @reset reset()

  # API Pública
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  # Gestión de equipos
  def initialize_teams(teams, max_players_per_team), do:
    GenServer.call(__MODULE__, {:initialize_teams, teams, max_players_per_team})
  def sync_teams_from_network(teams_data), do:
    GenServer.call(__MODULE__, {:sync_teams_from_network, teams_data})
  def sync_lista_equipos(lista_equipos_data), do:
    GenServer.call(__MODULE__, {:sync_lista_equipos, lista_equipos_data})
  def join_team(player_name, team_name), do:
    GenServer.call(__MODULE__, {:join_team, player_name, team_name})
  def set_team_ready(team_name), do:
    GenServer.call(__MODULE__, {:set_team_ready, team_name})
  def get_teams, do:
    GenServer.call(__MODULE__, :get_teams)
  def get_team_position(team_name), do:
    GenServer.call(__MODULE__, {:get_team_position, team_name})
  def update_team_position(team_name, position), do:
    GenServer.cast(__MODULE__, {:update_team_position, team_name, position})
  def all_teams_ready?, do:
    GenServer.call(__MODULE__, :all_teams_ready)
  def reset_teams, do:
    GenServer.cast(__MODULE__, :reset_teams)

  # Nuevas funciones para las listas
  def get_lista_peers, do:
    GenServer.call(__MODULE__, :get_lista_peers)
  def get_lista_equipos, do:
    GenServer.call(__MODULE__, :get_lista_equipos)
  def get_lista_mi_equipo, do:
    GenServer.call(__MODULE__, :get_lista_mi_equipo)

  # Notificaciones
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
      max_players_per_team: 3,
      lista_equipos: [] # Formato: [{address :: String.t(), secret_number :: integer(), team_name :: atom()}]
    }}
  end

  @impl true
  def handle_call({:initialize_teams, teams, max_players}, _from, state) do
    if map_size(state.teams) > 0 do
      {:reply, {:error, "Los equipos ya han sido inicializados"}, state}
    else
      # Convertir nombres de equipo a átomos
      team_atoms = Enum.map(teams, &String.to_atom/1)

      # Crear estructura inicial de equipos
      initialized_teams = Enum.reduce(team_atoms, %{}, fn team_name, acc ->
        Map.put(acc, team_name, %{
          players: MapSet.new(),
          position: 0,
          ready: false
        })
      end)

      # Obtener información del creador
      creator_name = Application.get_env(:prueba2, :username)
      creator_address = Application.get_env(:prueba2, :address)
      first_team = List.first(team_atoms)

      # Actualizar listas
      lista_equipos = if creator_name && creator_address && first_team do
        new_secret = :rand.uniform(1000)
        # Asegurarnos de almacenar el formato nuevo con el equipo
        IO.puts(@team_color <> "[EQUIPO] Asignando ID secreto #{new_secret} al creador en equipo #{first_team}" <> @reset)
        [{creator_address, new_secret, first_team}]
      else
        []
      end

      # Asignar creador al primer equipo si existe
      updated_teams = if first_team && creator_name do
        put_in(initialized_teams, [first_team, :players], MapSet.put(initialized_teams[first_team].players, creator_name))
      else
        initialized_teams
      end

      # Notificaciones
      broadcast_team_event("Sistema de equipos inicializado")
      if first_team && creator_name do
        broadcast_team_event("#{creator_name} se ha unido al equipo #{first_team}")
      end

      # Mostrar lista inicial de equipos
      if lista_equipos != [] do
        display_teams_list(lista_equipos)
      end

      {:reply, {:ok, "Equipos inicializados"}, %{
        state |
        teams: updated_teams,
        max_players_per_team: max_players,
        lista_equipos: lista_equipos
      }}
    end
  end

  @impl true
  def handle_call({:join_team, player_name, team_name}, _from, state) do
    team_atom =
      if is_atom(team_name), do: team_name, else: String.to_atom(to_string(team_name))

    with {:ok, team} <- Map.fetch(state.teams, team_atom),
         false <- Enum.any?(state.teams, fn {_, t} -> MapSet.member?(t.players, player_name) end),
         true <- MapSet.size(team.players) < state.max_players_per_team do

      # Actualizar equipo
      updated_team = %{team | players: MapSet.put(team.players, player_name)}
      new_teams = Map.put(state.teams, team_atom, updated_team)

      # Asignar ID secreto si no lo tiene
      player_address = get_player_address(player_name)
      already_has_id = Enum.any?(state.lista_equipos, fn
        {addr, _, _} -> addr == player_address
        {addr, _} -> addr == player_address
      end)
      new_secret = :rand.uniform(1000)
      # Guardar el equipo seleccionado junto con el address y el id secreto
      new_lista_equipos =
        cond do
          player_address && !already_has_id ->
            # Registrar nuevo peer con equipo y ID
            broadcast_team_event("Asignando ID secreto #{new_secret} al jugador en equipo #{team_atom}")
            [{player_address, new_secret, team_atom} | state.lista_equipos]
          player_address && already_has_id ->
            # Si ya existe, actualizar el equipo si cambió
            Enum.map(state.lista_equipos, fn
              {^player_address, id, _old_team} ->
                broadcast_team_event("Actualizando equipo del jugador con ID #{id}")
                {player_address, id, team_atom}
              {^player_address, id} ->
                # Migrar formato antiguo al nuevo
                broadcast_team_event("Migrando formato antiguo: asignando equipo #{team_atom} al jugador con ID #{id}")
                {player_address, id, team_atom}
              other -> other
            end)
          true ->
            broadcast_team_event("No se pudo obtener dirección para el jugador #{player_name}")
            state.lista_equipos
        end

      # Notificaciones
      broadcast_team_event("#{player_name} se unió al equipo #{team_atom}")
      notify_player_joined(player_name, team_atom)

      # Mostrar la lista de equipos actualizada
      display_teams_list(new_lista_equipos)

      {:reply, {:ok, "Te has unido al equipo #{team_atom}"}, %{
        state |
        teams: new_teams,
        lista_equipos: new_lista_equipos
      }}
    else
      :error ->
        {:reply, {:error, "El equipo no existe"}, state}
      true ->
        {:reply, {:error, "Ya estás en un equipo"}, state}
      false ->
        {:reply, {:error, "El equipo está lleno"}, state}
    end
  end

  @impl true
  def handle_call({:set_team_ready, team_name}, _from, state) do
    team_atom = String.to_atom(team_name)

    case Map.fetch(state.teams, team_atom) do
      {:ok, team} ->
        if MapSet.size(team.players) == 0 do
          {:reply, {:error, "El equipo no tiene jugadores"}, state}
        else
          updated_team = %{team | ready: true}
          new_teams = Map.put(state.teams, team_atom, updated_team)
          broadcast_team_event("El equipo #{team_name} está listo")
          {:reply, {:ok, "Equipo listo para iniciar"}, %{state | teams: new_teams}}
        end
      :error ->
        {:reply, {:error, "El equipo no existe"}, state}
    end
  end

  @impl true
  def handle_call(:get_teams, _from, state) do
    # Convertir todos los MapSet de players a listas para evitar errores de Jason
    teams_serializable = Enum.into(state.teams, %{}, fn {team, info} ->
      {team, %{info | players: MapSet.to_list(info.players)}}
    end)
    {:reply, teams_serializable, state}
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
    teams_with_players = Enum.filter(state.teams, fn {_, team} ->
      MapSet.size(team.players) > 0
    end)

    all_ready = Enum.all?(teams_with_players, fn {_, team} -> team.ready end)
    enough_teams = map_size(teams_with_players) >= 2

    {:reply, all_ready && enough_teams, state}
  end

  @impl true
  def handle_call({:sync_teams_from_network, teams_data}, _from, state) do
    teams_map = case teams_data do
      list when is_list(list) -> Enum.into(list, %{})
      map when is_map(map) -> map
      _ -> %{}
    end

    new_teams = Enum.reduce(teams_map, state.teams, fn {team_name, team_info}, acc ->
      team_atom = String.to_atom(team_name)

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

      Map.put(acc, team_atom, %{
        players: MapSet.new(players),
        position: position,
        ready: ready
      })
    end)

    {:reply, {:ok, "Equipos sincronizados"}, %{state | teams: new_teams}}
  end

  @impl true
  def handle_call({:sync_lista_equipos, lista_equipos_data}, _from, state) do
    # Convertir lista_equipos_data de formato JSON (lista de mapas) a formato interno (lista de tuplas)
    new_lista = Enum.map(lista_equipos_data, fn
      # Caso cuando es un mapa (como viene de JSON)
      %{"address" => address, "secret" => secret, "equipo" => equipo} ->
        {address, secret, String.to_atom(equipo)}
      # Formato para compatibilidad con mapas antiguos
      %{"address" => address, "secret" => secret} ->
        {address, secret}
      # Caso cuando ya es una tupla (desde código Elixir)
      {address, secret, equipo} when is_binary(equipo) ->
        {address, secret, String.to_atom(equipo)}
      # Cualquier otro formato de tupla se mantiene
      item -> item
    end)

    broadcast_team_event("Lista de equipos sincronizada: #{length(new_lista)} registros")
    display_teams_list(new_lista)

    {:reply, {:ok, "Lista de equipos sincronizada"}, %{state | lista_equipos: new_lista}}
  end
  @impl true
  def handle_call(:get_lista_peers, _from, state) do
    # Obtener información del peer local
    local_username = Application.get_env(:prueba2, :username)
    local_address = Application.get_env(:prueba2, :address)

    # Determinar equipo local
    local_equipo = if local_username do
      Enum.find_value(state.teams, :NA, fn {team, info} ->
        if MapSet.member?(info.players, local_username), do: team, else: nil
      end)
    else
      :NA
    end

    # Obtener peers de P2PNetwork y derivar equipo
    peers = Prueba2.P2PNetwork.get_peers()
    remote_peers_list = Enum.map(peers, fn {address, username} ->
      equipo = Enum.find_value(state.teams, :NA, fn {team, info} ->
        if MapSet.member?(info.players, username), do: team, else: nil
      end)
      {address, username, equipo}
    end)

    # Agregar peer local a la lista si existe
    lista_peers = if local_username && local_address do
      [{local_address, local_username, local_equipo} | remote_peers_list]
    else
      remote_peers_list
    end

    {:reply, lista_peers, state}
  end
  @impl true
  def handle_call(:get_lista_equipos, _from, state) do
    # Obtener información del peer local
    local_username = Application.get_env(:prueba2, :username)
    local_address = Application.get_env(:prueba2, :address)

    # Asegurar que todos los elementos tengan el formato {address, secret_number, equipo}
    normalized_lista = Enum.map(state.lista_equipos, fn
      {address, secret_number, equipo} -> {address, secret_number, equipo}  # Formato nuevo
      {address, secret_number} -> # Formato antiguo, buscar equipo
        username = find_username_by_address(address)
        equipo = if username do
          Enum.find_value(state.teams, :NA, fn {team, info} ->
            if MapSet.member?(info.players, username), do: team, else: nil
          end)
        else
          :NA
        end
        {address, secret_number, equipo}
    end)

    # Verificar si el peer local ya está en la lista
    local_peer_in_list = Enum.any?(normalized_lista, fn
      {addr, _, _} -> addr == local_address
      {addr, _} -> addr == local_address
    end)

    # Si el peer local no está en la lista y tiene equipo asignado, agregarlo
    final_lista = if !local_peer_in_list && local_username && local_address do
      # Determinar equipo local
      local_equipo = Enum.find_value(state.teams, :NA, fn {team, info} ->
        if MapSet.member?(info.players, local_username), do: team, else: nil
      end)

      # Si está en un equipo, debería tener un ID secreto
      case local_equipo do
        nil ->
          normalized_lista
        :NA ->
          normalized_lista
        equipo ->
          # Generar un ID secreto para el peer local si se unió a un equipo
          new_secret = :rand.uniform(1000)
          broadcast_team_event("Asignando ID secreto #{new_secret} al usuario local en equipo #{equipo}")
          [{local_address, new_secret, equipo} | normalized_lista]
      end
    else
      normalized_lista
    end

    {:reply, final_lista, state}
  end

  @impl true
  def handle_call(:get_lista_mi_equipo, _from, state) do
    # Obtener información del peer local
    local_username = Application.get_env(:prueba2, :username)
    local_address = Application.get_env(:prueba2, :address)

    # Determinar equipo local
    local_equipo = if local_username do
      Enum.find_value(state.teams, :NA, fn {team, info} ->
        if MapSet.member?(info.players, local_username), do: team, else: nil
      end)
    else
      :NA
    end

    if local_equipo == :NA || local_equipo == nil do
      # Si no tengo equipo, devuelvo lista vacía
      {:reply, [], state}
    else
      # Filtrar la lista_equipos para incluir solo peers de mi equipo
      my_team_peers = Enum.filter(state.lista_equipos, fn
        {_address, _secret, equipo} -> equipo == local_equipo
        {_address, _secret} -> false  # No incluir los que no tienen equipo asignado
      end)

      # Agregar mi propio peer si no está en la lista
      local_peer_in_list = Enum.any?(my_team_peers, fn
        {addr, _, _} -> addr == local_address
        {addr, _} -> addr == local_address
      end)

      final_list = if !local_peer_in_list && local_username && local_address && local_equipo != :NA do
        # Buscar si tengo un ID secreto
        secret_number = :rand.uniform(1000)  # Valor por defecto si no lo encuentro

        # Verificar si ya tengo un ID secreto en la lista_equipos general
        case Enum.find(state.lista_equipos, fn
          {^local_address, _, _} -> true
          {^local_address, _} -> true
          _ -> false
        end) do
          {_, s, _} -> [{local_address, s, local_equipo} | my_team_peers]
          {_, s} -> [{local_address, s, local_equipo} | my_team_peers]
          nil -> [{local_address, secret_number, local_equipo} | my_team_peers]
        end
      else
        my_team_peers
      end

      {:reply, final_list, state}
    end
  end

  @impl true
  def handle_cast({:update_team_position, team_name, position}, state) do
    team_atom = String.to_atom(team_name)

    case Map.fetch(state.teams, team_atom) do
      {:ok, team} ->
        updated_team = %{team | position: position}
        new_teams = Map.put(state.teams, team_atom, updated_team)
        {:noreply, %{state | teams: new_teams}}
      :error ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:reset_teams, state) do
    reset_teams = Map.new(state.teams, fn {name, team} ->
      {name, %{team | position: 0, ready: false}}
    end)

    {:noreply, %{state | teams: reset_teams}}
  end

  # Funciones privadas
  defp broadcast_team_event(message) do
    IO.puts(@team_color <> "[EQUIPO] " <> @reset <> message)
  end

  defp get_player_address(player_name) do
    case Enum.find(P2PNetwork.get_peers(), fn {_, username} -> username == player_name end) do
      {address, _} -> address
      nil -> nil
    end
  end

  defp find_username_by_address(address) do
    case Enum.find(P2PNetwork.get_peers(), fn {addr, _} -> addr == address end) do
      {_, username} -> username
      nil -> nil
    end
  end
  # Función para mostrar la lista de equipos actualizada
  defp display_teams_list(lista_equipos) do
    equipo_count = length(lista_equipos)
    IO.puts(@team_color <> "\n===== Lista de Equipos Actualizada (#{equipo_count}) =====" <> @reset)

    if (equipo_count == 0) do
      IO.puts(@team_color <> "No hay equipos registrados todavía." <> @reset)
    else
      IO.puts(@team_color <> "Dirección" <> @reset <> " | " <>
              @team_color <> "ID Secreto" <> @reset <> " | " <>
              @team_color <> "Equipo" <> @reset)
      IO.puts(String.duplicate("-", 60))

      # Organizamos por equipo para una mejor visualización
      lista_equipos
      |> Enum.group_by(fn
        {_, _, equipo} -> equipo
        {_, _} -> :sin_equipo
      end)
      |> Enum.sort_by(fn {k, _} -> to_string(k) end)
      |> Enum.each(fn {equipo, miembros} ->
        IO.puts(@team_color <> "\nEquipo: #{equipo}" <> @reset)

        Enum.each(miembros, fn
          {address, secret_number, _} ->
            username = find_username_by_address(address)
            username_str = if username, do: "(#{username})", else: ""
            IO.puts("  #{address} #{username_str} | #{secret_number}")
          {address, secret_number} -> # Para mantener compatibilidad con formato anterior
            username = find_username_by_address(address)
            username_str = if username, do: "(#{username})", else: ""
            IO.puts("  #{address} #{username_str} | #{secret_number}")
        end)
      end)
    end
    IO.puts("\n")
  end
end
