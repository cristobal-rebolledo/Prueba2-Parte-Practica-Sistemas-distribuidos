defmodule Prueba2.GameEngine do
  @moduledoc """
  Motor del juego de dados por equipos.

  Este módulo maneja la lógica del juego donde:
  - Los equipos compiten para avanzar en un tablero
  - El avance se basa en la suma de los dados tirados por los miembros del equipo
  - El primer equipo en superar la posición máxima del tablero gana
  """

  use GenServer
  require Logger
  import IO.ANSI
  alias Prueba2.P2PNetwork

  # Colores para mensajes
  @title_color bright() <> blue()
  @info_color green()
  @error_color bright() <> red()
  @highlight_color yellow()
  @team_color cyan()
  @winner_color bright() <> magenta()
  @reset reset()

  # API Pública
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registra un nuevo equipo en el juego.
  """
  def register_team(team_name) do
    GenServer.call(__MODULE__, {:register_team, team_name})
  end

  @doc """
  Un equipo solicita iniciar el juego.
  """
  def request_start_game(team_name) do
    GenServer.call(__MODULE__, {:request_start_game, team_name})
  end

  @doc """
  Añade un jugador a un equipo existente.
  """
  def add_player_to_team(player_name, team_name) do
    GenServer.call(__MODULE__, {:add_player, player_name, team_name})
  end

  @doc """
  Procesa una tirada de dado de un jugador.
  """
  def process_dice_roll(player_name, team_name, value) do
    GenServer.cast(__MODULE__, {:dice_roll, player_name, team_name, value})
  end

  @doc """
  Obtiene el estado actual del juego.
  """
  def get_game_state do
    GenServer.call(__MODULE__, :get_game_state)
  end

  @doc """
  Obtiene la lista de equipos y sus jugadores.
  """
  def get_teams do
    GenServer.call(__MODULE__, :get_teams)
  end

  @doc """
  Reinicia el juego a su estado inicial.
  """
  def reset_game do
    GenServer.cast(__MODULE__, :reset_game)
  end

  # Callbacks de GenServer
  @impl true
  def init(_) do
    # Leer la cantidad máxima de posiciones del tablero de la variable de entorno
    max_pos = get_max_position_from_env()

    # Inicializamos con dos equipos por defecto
    {:ok, %{
      teams: %{
        "Equipo Rojo" => %{players: MapSet.new(), position: 0, ready: false},
        "Equipo Azul" => %{players: MapSet.new(), position: 0, ready: false}
      },
      max_position: max_pos,
      game_started: false,
      turn_order: [],
      current_turn: nil,
      winner: nil,
      roll_history: []
    }}
  end

  @impl true
  def handle_call({:register_team, team_name}, _from, state) do
    if Map.has_key?(state.teams, team_name) do
      {:reply, {:error, "El equipo ya existe"}, state}
    else
      new_teams = Map.put(state.teams, team_name, %{
        players: MapSet.new(),
        position: 0,
        ready: false
      })

      Logger.info("Equipo registrado: #{team_name}")
      broadcast_game_event("Nuevo equipo registrado: #{team_name}")

      {:reply, {:ok, "Equipo registrado correctamente"}, %{state | teams: new_teams}}
    end
  end
  @impl true
  def handle_call({:add_player, player_name, team_name}, _from, state) do
    case Map.fetch(state.teams, team_name) do
      {:ok, team} ->
        # Verificar si el jugador ya está en algún equipo
        player_exists = Enum.any?(state.teams, fn {_, team_info} ->
          MapSet.member?(team_info.players, player_name)
        end)

        if player_exists do
          {:reply, {:error, "El jugador ya está en un equipo"}, state}
        else
          # Añadir jugador al equipo
          updated_team = %{team | players: MapSet.put(team.players, player_name)}
          new_teams = Map.put(state.teams, team_name, updated_team)

          Logger.info("Jugador #{player_name} añadido al equipo #{team_name}")
          broadcast_game_event("#{player_name} se unió al equipo #{team_name}")

          # Buscar el peer en la red y actualizar su equipo
          try do
            # Encontrar la dirección del peer por nombre de usuario
            peers = Prueba2.P2PNetwork.get_peers()
            peer_address = find_peer_address_by_username(peers, player_name)

            if peer_address do
              # Actualizar el equipo del peer en el P2PNetwork
              Prueba2.P2PNetwork.update_peer_team(peer_address, team_name)
            end
          rescue
            e -> Logger.error("Error al actualizar info de equipo del peer: #{inspect(e)}")
          end

          {:reply, {:ok, "Jugador añadido al equipo"}, %{state | teams: new_teams}}
        end

      :error ->
        {:reply, {:error, "El equipo no existe"}, state}
    end
  end

  # Función auxiliar para encontrar la dirección de un peer por su nombre de usuario
  defp find_peer_address_by_username(peers, username) do
    Enum.find_value(peers, fn {address, peer_username} ->
      if peer_username == username, do: address, else: nil
    end)
  end

  @impl true
  def handle_call({:request_start_game, team_name}, _from, state) do
    case Map.fetch(state.teams, team_name) do
      {:ok, team} ->
        # Verificar si el equipo tiene al menos un jugador
        if MapSet.size(team.players) == 0 do
          {:reply, {:error, "El equipo no tiene jugadores"}, state}
        else
          # Marcar al equipo como listo para iniciar
          updated_team = %{team | ready: true}
          new_teams = Map.put(state.teams, team_name, updated_team)
          new_state = %{state | teams: new_teams}

          Logger.info("Equipo #{team_name} está listo para iniciar")
          broadcast_game_event("El equipo #{team_name} está listo para iniciar el juego")

          # Verificar si todos los equipos están listos para iniciar
          all_teams_ready = Enum.all?(new_teams, fn {_, team_info} -> team_info.ready end)

          if all_teams_ready && !state.game_started && map_size(new_teams) >= 2 do
            # Iniciar el juego y determinar el orden aleatorio de los turnos
            turn_order = Map.keys(new_teams) |> Enum.shuffle()
            started_state = %{
              new_state |
              game_started: true,
              turn_order: turn_order,
              current_turn: List.first(turn_order)
            }

            Logger.info("¡El juego ha iniciado! Orden de turnos: #{Enum.join(turn_order, ", ")}")
            broadcast_game_event("¡El juego ha comenzado! Orden de turnos: #{Enum.join(turn_order, ", ")}")
            broadcast_game_event("Es el turno del #{List.first(turn_order)}")

            {:reply, {:ok, "Juego iniciado"}, started_state}
          else
            {:reply, {:ok, "Equipo listo para iniciar"}, new_state}
          end
        end

      :error ->
        {:reply, {:error, "El equipo no existe"}, state}
    end
  end

  @impl true
  def handle_call(:get_game_state, _from, state) do
    game_state = %{
      teams: state.teams |> Enum.map(fn {name, info} ->
        {name, %{
          players: MapSet.to_list(info.players),
          position: info.position,
          ready: info.ready
        }}
      end) |> Enum.into(%{}),
      max_position: state.max_position,
      game_started: state.game_started,
      turn_order: state.turn_order,
      current_turn: state.current_turn,
      winner: state.winner,
      roll_history: Enum.take(state.roll_history, -10)  # Últimos 10 movimientos
    }

    {:reply, game_state, state}
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
  def handle_cast({:dice_roll, player_name, team_name, value}, state) do
    if state.game_started && state.winner == nil do
      case Map.fetch(state.teams, team_name) do
        {:ok, team} ->
          if team_name != state.current_turn do
            Logger.warning("#{player_name} intentó tirar el dado fuera de turno")
            broadcast_game_event("No es el turno del equipo #{team_name}")
            {:noreply, state}
          else
            # Verificar si el jugador pertenece al equipo
            if MapSet.member?(team.players, player_name) do
              # Actualizar la posición del equipo
              new_position = team.position + value
              Logger.info("#{player_name} (#{team_name}) tiró #{value}. Nueva posición: #{new_position}")

              # Añadir al historial de tiradas
              roll_entry = %{
                player: player_name,
                team: team_name,
                value: value,
                position: new_position,
                timestamp: DateTime.utc_now()
              }

              updated_team = %{team | position: new_position}
              new_teams = Map.put(state.teams, team_name, updated_team)

              broadcast_game_event("#{player_name} del equipo #{team_name} tiró un #{value}. Avanza a la posición #{new_position}")

              # Verificar si hay un ganador
              new_state = if new_position >= state.max_position do
                Logger.info("¡#{team_name} ha ganado el juego!")
                winner_message = "#{@winner_color}¡#{team_name} ha ganado el juego al alcanzar la posición #{new_position}!#{@reset}"
                broadcast_game_event(winner_message)

                # Notificar a todos los jugadores sobre el ganador
                notify_all_players_about_winner(state.teams, team_name, new_position)

                %{state |
                  winner: team_name,
                  teams: new_teams,
                  roll_history: [roll_entry | state.roll_history]
                }
              else
                # Cambiar al siguiente turno
                next_turn_index = Enum.find_index(state.turn_order, &(&1 == team_name)) + 1
                next_turn = Enum.at(state.turn_order, rem(next_turn_index, length(state.turn_order)))

                broadcast_game_event("Es el turno del #{next_turn}")

                %{state |
                  teams: new_teams,
                  current_turn: next_turn,
                  roll_history: [roll_entry | state.roll_history]
                }
              end

              {:noreply, new_state}
            else
              Logger.warning("#{player_name} no pertenece al equipo #{team_name}")
              {:noreply, state}
            end
          end

        :error ->
          Logger.warning("El equipo #{team_name} no existe")
          {:noreply, state}
      end
    else
      if state.winner != nil do
        Logger.info("El juego ya ha terminado. El ganador fue #{state.winner}")
        {:noreply, state}
      else
        Logger.warning("El juego no ha iniciado aún")
        {:noreply, state}
      end
    end
  end

  @impl true
  def handle_cast(:reset_game, _state) do
    # Reiniciar el juego a su estado inicial
    max_pos = get_max_position_from_env()

    Logger.info("El juego ha sido reiniciado")
    broadcast_game_event("El juego ha sido reiniciado. Todos los equipos están en la posición 0")

    {:noreply, %{
      teams: %{
        "Equipo Rojo" => %{players: MapSet.new(), position: 0, ready: false},
        "Equipo Azul" => %{players: MapSet.new(), position: 0, ready: false}
      },
      max_position: max_pos,
      game_started: false,
      turn_order: [],
      current_turn: nil,
      winner: nil,
      roll_history: []
    }}
  end

  # Funciones privadas

  # Obtener la posición máxima del tablero desde la variable de entorno
  defp get_max_position_from_env do
    # Primero intentamos obtener el valor de la variable de entorno directamente
    case System.get_env("MAX_POS_TABLERO") do
      nil ->
        # Si no está disponible, intentamos obtener del archivo .env a través de la aplicación
        case Application.get_env(:prueba2, :max_pos_tablero) do
          nil ->
            # Si aún no está disponible, usamos un valor predeterminado
            default = 100
            Logger.info("Usando valor predeterminado para MAX_POS_TABLERO: #{default}")
            default
          value when is_integer(value) ->
            value
          value when is_binary(value) ->
            # Convertir string a integer si es necesario
            case Integer.parse(value) do
              {num, _} -> num
              :error -> 100
            end
        end

      value ->
        # Convertir el valor de string a integer
        case Integer.parse(value) do
          {num, _} -> num
          :error -> 100  # Valor por defecto si no se puede parsear
        end
    end
  end

  # Envía eventos del juego a todos los jugadores conectados
  defp broadcast_game_event(message) do
    IO.puts(@team_color <> "[JUEGO] " <> @reset <> message)

    # Intentar enviar el mensaje a través del sistema P2P
    try do
      if function_exported?(P2PNetwork, :broadcast_message, 1) do
        P2PNetwork.broadcast_message("GAME_EVENT: " <> message)
      end
    rescue
      _ -> Logger.warning("No se pudo transmitir el evento de juego")
    end
  end

  # Notifica a todos los jugadores sobre el ganador
  defp notify_all_players_about_winner(teams, winning_team, final_position) do
    message = "El equipo #{winning_team} ha ganado el juego al alcanzar la posición #{final_position}!"

    # Crear un resumen del juego con puntuaciones finales
    team_scores = teams
    |> Enum.map(fn {name, info} ->
      {name, info.position}
    end)
    |> Enum.sort_by(fn {_, position} -> position end, :desc)

    summary = "Resultados finales:\n" <>
              (team_scores
              |> Enum.map(fn {name, pos} -> "#{name}: #{pos} puntos" end)
              |> Enum.join("\n"))

    # Intentar enviar las notificaciones a través del sistema P2P
    try do
      if function_exported?(P2PNetwork, :broadcast_message, 1) do
        P2PNetwork.broadcast_message("GAME_OVER: " <> message)
        P2PNetwork.broadcast_message("GAME_SUMMARY: " <> summary)
      end
    rescue
      _ -> Logger.warning("No se pudo notificar a los jugadores sobre el ganador")
    end

    # Mostrar el resumen en la consola local
    IO.puts(@winner_color <> "\n=== FIN DEL JUEGO ===" <> @reset)
    IO.puts(@winner_color <> message <> @reset)
    IO.puts(@info_color <> summary <> @reset)
  end
end
