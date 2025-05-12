defmodule GameProject.UI do
  @moduledoc """
  Módulo para manejar la interfaz de usuario en terminal.
  """

  alias GameProject.Models.Player
  alias GameProject.PlayerRegistry
  alias GameProject.GameServer
  alias GameProject.Network
  alias GameProject.GRPCLogger
  alias GameProject.MessageDistribution

  @team_names [
    :equipo_dragon,
    :equipo_planta,
    :equipo_rojo,
    :equipo_azul,
    :equipo_amarillo,
    :equipo_negro,
    :equipo_blanco,
    :equipo_verde,
    :equipo_morado,
    :equipo_naranja,
    :equipo_rosa,
    :equipo_marron,
    :equipo_gris,
    :equipo_oro,
    :equipo_plata
  ]
  @doc """
  Inicia la interfaz de usuario.
  """
  def start() do
    IO.puts(IO.ANSI.clear())
    IO.puts(IO.ANSI.bright() <> "¡Bienvenido al Juego en Red!" <> IO.ANSI.reset())
    IO.puts("----------------------------------------")

    # Solicitar alias inicial
    player_alias = get_input("Por favor, ingresa tu alias: ")

    # Obtener dirección IP local y pública
    local_ip = Network.get_local_ip()
    public_ip = Network.get_public_ip() || "No disponible"

    IO.puts("\nInformación de red:")
    IO.puts("IP local: #{local_ip}")
    IO.puts("IP pública: #{public_ip}")

    # Intentar iniciar el servidor HTTP
    start_http_server(player_alias, local_ip)
  end

  # Función para intentar iniciar el servidor HTTP
  defp start_http_server(player_alias, ip_address, attempt \\ 1) do
    # Limitar los intentos para evitar bucles infinitos
    if attempt > 5 do
      IO.puts("\n#{IO.ANSI.red()}No se pudo iniciar el servidor HTTP después de varios intentos.#{IO.ANSI.reset()}")
      IO.puts("Por favor, reinicie la aplicación y pruebe con otro rango de puertos.")
      System.halt(1)
    end

    # Solicitar puerto para el servidor HTTP
    port = get_input("Ingresa el puerto para el servidor HTTP: ")
    |> String.to_integer()

    # Intentar iniciar el servidor HTTP
    try do
      case GameProject.HTTPServer.start_link(port) do
        {:ok, _pid} ->
          IO.puts("\n#{IO.ANSI.green()}Servidor HTTP iniciado en puerto #{port}#{IO.ANSI.reset()}")
          # Mostrar menú principal
          show_initial_menu(player_alias, "#{ip_address}:#{port}")
        {:error, {:already_started, _}} ->
          IO.puts("\n#{IO.ANSI.yellow()}El servidor ya está iniciado. Continuando...#{IO.ANSI.reset()}")
          show_initial_menu(player_alias, "#{ip_address}:#{port}")
        {:error, reason} ->
          IO.puts("\n#{IO.ANSI.red()}Error al iniciar servidor HTTP en puerto #{port}: #{inspect(reason)}#{IO.ANSI.reset()}")
          IO.puts("Por favor intente con otro puerto.")
          start_http_server(player_alias, ip_address, attempt + 1)
      end
    rescue
      e ->
        IO.puts("\n#{IO.ANSI.red()}Error al iniciar servidor HTTP: #{inspect(e)}#{IO.ANSI.reset()}")
        IO.puts("Por favor intente con otro puerto.")
        start_http_server(player_alias, ip_address, attempt + 1)
    end
  end

  # Menú inicial (antes de unirse a una red)
  defp show_initial_menu(player_alias, address) do
    IO.puts(IO.ANSI.clear())
    IO.puts(IO.ANSI.bright() <> "MENÚ PRINCIPAL" <> IO.ANSI.reset())
    IO.puts("----------------------------------------")
    IO.puts("Alias actual: #{player_alias}")
    IO.puts("Dirección: #{address}")
    IO.puts("----------------------------------------")
    IO.puts("1. Cambiar alias")
    IO.puts("2. Crear una red nueva")
    IO.puts("3. Unirse a una red existente")
    IO.puts("4. Salir del juego")
    IO.puts("----------------------------------------")

    option = get_input("Selecciona una opción: ")

    case option do
      "1" ->
        new_alias = get_input("Ingresa tu nuevo alias: ")
        show_initial_menu(new_alias, address)

      "2" ->
        create_network(player_alias, address)

      "3" ->
        join_network(player_alias, address)

      "4" ->
        IO.puts("\n¡Gracias por jugar!")
        System.halt(0)

      _ ->
        IO.puts("\nOpción no válida. Inténtalo de nuevo.")
        :timer.sleep(1000)
        show_initial_menu(player_alias, address)
    end
  end

  # Crear una nueva red
  defp create_network(player_alias, address) do
    IO.puts(IO.ANSI.clear())
    IO.puts(IO.ANSI.bright() <> "CREAR NUEVA RED" <> IO.ANSI.reset())
    IO.puts("----------------------------------------")

    # Solicitar parámetros de configuración
    num_teams = get_input("Número de equipos (1-15): ")
    |> String.to_integer()
    |> max(1)
    |> min(15)

    max_score = get_input("Puntuación máxima para ganar: ")
    |> String.to_integer()
    |> max(10)

    max_players = get_input("Máximo de jugadores por equipo: ")
    |> String.to_integer()
    |> max(1)

    _access_key = get_input("Establece una clave de acceso: ")

    # Seleccionar equipos disponibles
    available_teams = Enum.take(@team_names, num_teams)

    # Crear el estado del juego
    {:ok, game_state} = GameServer.create_game(max_score, available_teams, max_players)

    # Crear jugador local y agregarlo al registro
    player = Player.new(address, player_alias)
    PlayerRegistry.add_player(player)

    IO.puts("\nRed creada con éxito. ID de instancia: #{game_state.instance_id}")
    IO.puts("Esperando conexiones entrantes...")
    IO.puts("\nPresiona Enter para continuar...")
    IO.gets("")

    # Mostrar menú dentro del juego
    show_in_game_menu(player_alias, address)
  end

  # Unirse a una red existente
  defp join_network(player_alias, address) do
    IO.puts(IO.ANSI.clear())
    IO.puts(IO.ANSI.bright() <> "UNIRSE A UNA RED" <> IO.ANSI.reset())
    IO.puts("----------------------------------------")

    server_address = get_input("Ingresa la dirección del servidor (IP:puerto): ")
    access_key = get_input("Ingresa la clave de acceso: ")

    # Generar número secreto para el jugador
    secret_number = Player.generate_secret_number()

    # Realizar la solicitud HTTP al servidor para unirse
    url = "http://#{server_address}/join"
    body = Jason.encode!(%{
      address: address,
      alias: player_alias,
      secret_number: secret_number,
      access_key: access_key
    })
    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.post(url, body, headers, [timeout: 5000, recv_timeout: 5000]) do      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        decoded = Jason.decode!(resp_body)
        players = Map.get(decoded, "players", [])
        game_config = Map.get(decoded, "game_config", %{})
        instance_id = Map.get(decoded, "instance_id")

        # Initialize the game state with the received configuration
        game_config = Map.merge(game_config, %{"instance_id" => instance_id})
        {:ok, _game_state} = GameServer.set_game_state(game_config)        # Limpiar y registrar todos los jugadores recibidos
        PlayerRegistry.clear()
        Enum.each(players, fn player_map ->
          player = Player.from_map(player_map)
          PlayerRegistry.add_player(player)
        end)

        # Añadir a sí mismo al registro local con el número secreto correcto
        self_player = %GameProject.Models.Player{
          address: address,
          alias: player_alias,
          team: nil,
          secret_number: secret_number
        }
        PlayerRegistry.add_player(self_player)

        IO.puts("\nUnido a la red con éxito. Jugadores actuales:")
        Enum.each(PlayerRegistry.get_players(), fn p ->
          IO.puts("- #{p.alias} (#{p.address})")
        end)
        IO.puts("\nPresiona Enter para continuar...")
        IO.gets("")
        # Mostrar menú dentro del juego
        show_in_game_menu(player_alias, address)
      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
        IO.puts("\nError al unirse a la red (#{code}): #{resp_body}")
        IO.gets("\nPresiona Enter para volver...")
        show_initial_menu(player_alias, address)
      {:error, reason} ->
        IO.puts("\nError de conexión: #{inspect(reason)}")
        IO.gets("\nPresiona Enter para volver...")
        show_initial_menu(player_alias, address)
    end
  end

  # Menú dentro del juego (tras unirse a una red)
  defp show_in_game_menu(player_alias, address) do
    {:ok, game_state} = GameServer.get_game_state()

    IO.puts(IO.ANSI.clear())
    IO.puts(IO.ANSI.bright() <> "MENÚ DE JUEGO" <> IO.ANSI.reset())
    IO.puts("----------------------------------------")
    IO.puts("Alias: #{player_alias}")
    IO.puts("Estado del juego: #{game_state.status}")
    IO.puts("Turno actual: #{game_state.turn_number}")
    IO.puts("----------------------------------------")
    IO.puts("1. Ver estado actual del juego")
    IO.puts("2. Ver tabla de jugadores")
    IO.puts("3. Mostrar tabla de rutas")
    IO.puts("4. Seleccionar un equipo para unirse")
    IO.puts("5. Abandonar la red")
    IO.puts("6. Volver al menú inicial")
    IO.puts("----------------------------------------")

    option = get_input("Selecciona una opción: ")

    case option do
      "1" ->
        show_game_state()
        show_in_game_menu(player_alias, address)

      "2" ->
        show_players_table()
        show_in_game_menu(player_alias, address)

      "3" ->
        show_routes_table()
        show_in_game_menu(player_alias, address)
      "4" ->
        join_team(player_alias)
        show_in_game_menu(player_alias, address)

      "5" ->
        leave_network(player_alias)
        show_initial_menu(player_alias, address)

      "6" ->
        # Volver al menú inicial (hacer limpieza como en la opción de abandonar la red)
        leave_network(player_alias)
        show_initial_menu(player_alias, address)

      _ ->
        IO.puts("\nOpción no válida. Inténtalo de nuevo.")
        :timer.sleep(1000)
        show_in_game_menu(player_alias, address)
    end
  end

  # Mostrar el estado actual del juego
  defp show_game_state() do
    {:ok, game_state} = GameServer.get_game_state()

    IO.puts(IO.ANSI.clear())
    IO.puts(IO.ANSI.bright() <> "ESTADO DEL JUEGO" <> IO.ANSI.reset())
    IO.puts("----------------------------------------")
    IO.puts("ID de instancia: #{game_state.instance_id}")
    IO.puts("Estado: #{game_state.status}")
    IO.puts("Turno actual: #{game_state.turn_number}")
    IO.puts("Puntuación máxima: #{game_state.max_score}")
    IO.puts("----------------------------------------")
    IO.puts(IO.ANSI.bright() <> "PUNTUACIONES" <> IO.ANSI.reset())

    Enum.each(game_state.team_scores, fn {team, score} ->
      IO.puts("#{team}: #{score} puntos")
    end)

    IO.puts("\nPresiona Enter para volver...")
    IO.gets("")
  end

  # Mostrar la tabla de jugadores
  defp show_players_table() do
    players = PlayerRegistry.get_players()

    IO.puts(IO.ANSI.clear())
    IO.puts(IO.ANSI.bright() <> "TABLA DE JUGADORES" <> IO.ANSI.reset())
    IO.puts("----------------------------------------")
    IO.puts("#{String.pad_trailing("Alias", 15)} | #{String.pad_trailing("Equipo", 15)} | Dirección")
    IO.puts("----------------------------------------")

    Enum.each(players, fn player ->
      team_name = if player.team, do: "#{player.team}", else: "Sin equipo"
      IO.puts("#{String.pad_trailing(player.alias, 15)} | #{String.pad_trailing(team_name, 15)} | #{player.address}")
    end)

    IO.puts("\nPresiona Enter para volver...")
    IO.gets("")
  end

  # Mostrar la tabla de rutas (conectividad entre nodos)
  defp show_routes_table() do
    players = PlayerRegistry.get_players()

    IO.puts(IO.ANSI.clear())
    IO.puts(IO.ANSI.bright() <> "TABLA DE RUTAS" <> IO.ANSI.reset())
    IO.puts("----------------------------------------")
    IO.puts("#{String.pad_trailing("Origen", 15)} | #{String.pad_trailing("Destino", 15)} | Estado")
    IO.puts("----------------------------------------")

    # En una implementación real, aquí se verificaría la conectividad entre nodos
    # Para el MVP, mostraremos rutas simuladas
    Enum.each(players, fn p1 ->
      Enum.each(players, fn p2 ->
        # No mostrar la ruta a sí mismo
        if p1.alias != p2.alias do
          # Simular conectividad (en un 90% de los casos)
          status = if :rand.uniform(10) > 1, do: "Conectado", else: "Desconectado"
          IO.puts("#{String.pad_trailing(p1.alias, 15)} | #{String.pad_trailing(p2.alias, 15)} | #{status}")
        end
      end)
    end)

    IO.puts("\nPresiona Enter para volver...")
    IO.gets("")
  end

  # Unirse a un equipo
  defp join_team(player_alias) do
    {:ok, game_state} = GameServer.get_game_state()

    IO.puts(IO.ANSI.clear())
    IO.puts(IO.ANSI.bright() <> "UNIRSE A UN EQUIPO" <> IO.ANSI.reset())
    IO.puts("----------------------------------------")
    IO.puts("Equipos disponibles:")

    # Mostrar lista numerada de equipos disponibles
    Enum.with_index(game_state.available_teams, 1)
    |> Enum.each(fn {team, index} ->
      IO.puts("#{index}. #{team}")
    end)

    IO.puts("0. Cancelar")
    IO.puts("----------------------------------------")

    option = get_input("Selecciona un equipo: ")
    |> String.to_integer()

    if option >= 1 and option <= length(game_state.available_teams) do
      selected_team = Enum.at(game_state.available_teams, option - 1)

      # Proceso de votación implementado según las especificaciones
      {:ok, player} = PlayerRegistry.get_player(player_alias)

      # Obtener miembros actuales del equipo
      team_members = PlayerRegistry.get_players_by_team(selected_team)

      if Enum.empty?(team_members) do
        # Caso especial: Equipo vacío
        IO.puts("\nEl equipo #{selected_team} está vacío. Procesando unión directa...")
        # Seleccionar un jugador aleatorio de cualquier equipo para verificar
        all_players = PlayerRegistry.get_players()

        if length(all_players) > 1 do
          # Hay otros jugadores para verificar
          other_players = Enum.filter(all_players, fn p -> p.alias != player_alias end)
          verifier = Enum.random(other_players)

          IO.puts("Solicitando verificación a #{verifier.alias}...")
          # Realizar solicitud HTTP real para verificación
          url = "http://#{verifier.address}/verify_join"
          body = Jason.encode!(%{
            requester_alias: player_alias,
            team: selected_team,
            voter_addresses: [], # No hay votantes ya que el equipo está vacío
            secret_sum: 0 # No hay suma ya que no hay votantes
          })
          headers = [{"Content-Type", "application/json"}]

          verification_result = try do
            case HTTPoison.post(url, body, headers, [timeout: 5000, recv_timeout: 5000]) do
              {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
                response = Jason.decode!(resp_body)
                if Map.get(response, "verified", false) do
                  IO.puts("#{IO.ANSI.green()}Verificación exitosa.#{IO.ANSI.reset()}")
                  :ok
                else
                  IO.puts("#{IO.ANSI.red()}Verificación fallida. No se puede unir al equipo.#{IO.ANSI.reset()}")
                  :error
                end

              _ ->
                IO.puts("#{IO.ANSI.red()}Error en la verificación. No se puede unir al equipo.#{IO.ANSI.reset()}")
                :error
            end
          catch
            _, _ ->
              IO.puts("#{IO.ANSI.red()}Error inesperado en la verificación.#{IO.ANSI.reset()}")
              :error
          end

          if verification_result == :ok do
            # NO actualizar el jugador localmente
            # En su lugar, confiar en el protocolo "distribuye" para que la actualización
            # llegue a través del representante del equipo y actualice a todos (incluido este nodo)

            # Distribuir mensaje a todos los jugadores
            MessageDistribution.distribute_message(
              %{type: :player_joined_team, player_alias: player_alias, team: selected_team, timestamp: System.system_time(:millisecond)},
              PlayerRegistry.get_players()
            )

            IO.puts("\nTe has unido al equipo #{selected_team} con éxito.")
          end
        else
          # No hay otros jugadores, se une directamente
          IO.puts("No hay otros jugadores para verificar. Unión directa al equipo.")
          # NO actualizar el jugador localmente
          # En su lugar, confiar en el protocolo "distribuye" para que la actualización
          # llegue a través del representante del equipo y actualice a todos (incluido este nodo)

          # Distribuir mensaje a todos los jugadores
          MessageDistribution.distribute_message(
            %{type: :player_joined_team, player_alias: player_alias, team: selected_team, timestamp: System.system_time(:millisecond)},
            PlayerRegistry.get_players()
          )

          IO.puts("\nTe has unido al equipo #{selected_team} con éxito.")
        end
      else
        # Caso normal: Equipo con miembros
        IO.puts("\nEl equipo #{selected_team} tiene #{length(team_members)} miembros.")
        IO.puts("Iniciando proceso de votación en una terminal separada...")

        # Usar la nueva terminal de votación separada
        result = GameProject.VotingTerminal.start_vote(
          player_alias,
          player.address,
          selected_team,
          game_state.instance_id
        )

        # Procesar el resultado
        case result do
          {:ok, vote_result} ->
            IO.puts("\nVotación exitosa: #{vote_result.positive_votes}/#{vote_result.total_votes} votos positivos.")
            IO.puts("Te has unido al equipo #{selected_team} con éxito.")

            # La actualización del jugador ocurre mediante el protocolo "distribuye"
            # y se procesa en MessageHandler.handle_player_joined_team

            # Registrar en el log
            GRPCLogger.log_event(%{
              timestamp: System.system_time(:second),
              id_instancia: game_state.instance_id,
              marcador: "INICIO",
              ip: player.address,
              alias: player_alias,
              accion: "join_team",
              args: Jason.encode!(%{team: selected_team})
            })

          {:error, error_result} ->
            case error_result.status do
              :rejected ->
                IO.puts("\nVotación fallida: #{error_result.positive_votes}/#{error_result.total_votes} votos positivos.")
                IO.puts("No tienes suficientes votos para unirte al equipo #{selected_team}.")
              :timeout ->
                IO.puts("\nTiempo de votación agotado. Inténtalo más tarde.")
            end
        end
      end
    else
      IO.puts("\nOperación cancelada.")
    end

    IO.puts("\nPresiona Enter para volver...")
    IO.gets("")
  end

  # Abandonar la red
  defp leave_network(player_alias) do
    IO.puts(IO.ANSI.clear())
    IO.puts(IO.ANSI.bright() <> "ABANDONAR LA RED" <> IO.ANSI.reset())
    IO.puts("----------------------------------------")

    confirm = get_input("¿Estás seguro de que deseas abandonar la red? (s/n): ")

    if String.downcase(confirm) == "s" do
      # Obtener jugador antes de eliminarlo
      {:ok, player} = PlayerRegistry.get_player(player_alias)      # Distribuir mensaje de desconexión
      MessageDistribution.distribute_message(
        %{type: :player_disconnected, player_alias: player_alias, reason: :leave_network},
        PlayerRegistry.get_players()
      )

      # Registrar en el log
      {:ok, game_state} = GameServer.get_game_state()
      GRPCLogger.log_event(%{
        timestamp: System.system_time(:second),
        id_instancia: game_state.instance_id,
        marcador: "NA",
        ip: player.address,
        alias: player_alias,
        accion: "leave_network",
        args: Jason.encode!(%{alias: player_alias, ip: player.address})
      })

      # Eliminar al jugador del registro
      PlayerRegistry.remove_player(player_alias)

      IO.puts("\nHas abandonado la red con éxito.")
      IO.puts("\nPresiona Enter para volver al menú principal...")
      IO.gets("")
      true
    else
      IO.puts("\nOperación cancelada.")
      IO.puts("\nPresiona Enter para volver...")
      IO.gets("")
      false
    end
  end

  # Función auxiliar para solicitar entrada al usuario
  defp get_input(prompt) do
    IO.write(prompt)
    IO.gets("") |> String.trim()
  end
end
