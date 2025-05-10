defmodule Prueba2.UserInterface do
  use GenServer
  require Logger
  import IO.ANSI
  alias Prueba2.IpDetector
  alias Prueba2.PasswordManager

  # Colores para mensajes
  @title_color bright() <> blue()
  @info_color green()
  @error_color bright() <> red()
  @highlight_color yellow()
  @input_color bright() <> cyan()
  @dice_color magenta()
  @peer_color bright() <> white()
  @reset reset()

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end
  def init(_) do
    # Configuración inicial
    username = get_username()
    ip_local = IpDetector.get_real_local_ip()
    port = get_available_port()
    address = "#{ip_local}:#{port}"

    # Guardar configuración global
    Application.put_env(:prueba2, :address, address)
    Application.put_env(:prueba2, :username, username)

    # Iniciar el servidor HTTP con manejo de errores
    case Plug.Cowboy.http(Prueba2.ApiRouter, [], port: port, ip: {0, 0, 0, 0}) do
      {:ok, _} ->
        Logger.info("Servidor HTTP iniciado en el puerto #{port}")
      {:error, {:already_started, _}} ->
        Logger.warning("El servidor HTTP ya se encuentra iniciado en el puerto #{port}")
      {:error, reason} ->
        Logger.error("Error al iniciar el servidor HTTP: #{inspect(reason)}")
        IO.puts(@error_color <> "Error al iniciar el servidor HTTP: #{inspect(reason)}" <> @reset)
        Process.sleep(2000) # Dar tiempo para que el mensaje sea visible
        System.stop(1)
    end

    # Obtener IP pública
    public_ip = IpDetector.get_public_ip()

    Process.send_after(self(), :show_welcome, 100)
    {:ok, %{
      public_ip: public_ip,
      port: port,
      ip_local: ip_local,
      address: address,
      username: username
    }}
  end
  # Solicitar nombre de usuario
  defp get_username do
    max_length = Application.get_env(:prueba2, :max_alias_length, 15)

    IO.puts("\n" <> @title_color <> "==== Sistema P2P de Dados ====" <> @reset)
    IO.puts(@info_color <> "¡Bienvenido al juego de dados P2P!" <> @reset)
    IO.puts(@info_color <> "El nombre de usuario debe tener máximo #{max_length} caracteres" <> @reset)
    IO.write(@input_color <> "Introduce tu nombre de usuario: " <> @reset)

    case IO.gets("") do
      nil ->
        IO.puts(@error_color <> "Error al leer el nombre de usuario, intenta de nuevo." <> @reset)
        Process.sleep(1000) # Dar tiempo para que el mensaje se muestre
        get_username()
      input ->
        name = String.trim(input)

        cond do
          String.length(name) == 0 ->
            IO.puts(@error_color <> "El nombre no puede estar vacío, intenta de nuevo." <> @reset)
            get_username()
          String.length(name) > max_length ->
            IO.puts(@error_color <> "El nombre no puede exceder #{max_length} caracteres, intenta de nuevo." <> @reset)
            get_username()
          true ->
            name
        end
    end
  end

  # Manejador de mensajes de bienvenida
  def handle_info(:show_welcome, state) do
    # Asegurarnos de tener el nombre de usuario actualizado desde la configuración global
    current_username = Application.get_env(:prueba2, :username, state.username)
    # Actualizar el estado si es necesario
    state = if current_username != state.username, do: %{state | username: current_username}, else: state

    IO.puts("\n" <> @title_color <> "===== Sistema P2P de Dados =====" <> @reset)
    IO.puts(@info_color <> "Usuario: " <> @highlight_color <> state.username <> @reset)
    IO.puts(@info_color <> "Tu dirección local: " <> @highlight_color <> state.ip_local <> ":" <> Integer.to_string(state.port) <> @reset)
    IO.puts(@info_color <> "Tu IP pública: " <> @highlight_color <> state.public_ip <> ":" <> Integer.to_string(state.port) <> @reset <> @info_color <> " (usa esta para conexiones desde Internet)" <> @reset)
    IO.puts("\n" <> @input_color <> "¿Qué desea hacer?" <> @reset)
    IO.puts("1. " <> @highlight_color <> "Iniciar una nueva red" <> @reset)
    IO.puts("2. " <> @highlight_color <> "Unirse a una red existente" <> @reset)
    IO.puts("3. " <> @highlight_color <> "Cambiar nombre de usuario" <> @reset)

    case IO.gets(@input_color <> "> " <> @reset) |> String.trim() do
      "1" ->
        handle_new_network(state)
        {:noreply, state}
      "2" ->
        handle_join_network(state)
        {:noreply, state}
      "3" ->
        new_name = get_username()
        Application.put_env(:prueba2, :username, new_name)
        state = %{state | username: new_name}
        Process.send_after(self(), :show_welcome, 100)
        {:noreply, state}
      _ ->
        IO.puts(@error_color <> "Opción no válida, intente de nuevo." <> @reset)
        Process.send_after(self(), :show_welcome, 100)
        {:noreply, state}
    end
  end
  # Manejador para mostrar el menú principal
  def handle_info(:show_menu, state) do
    # Asegurarnos de tener el nombre de usuario actualizado desde la configuración global
    current_username = Application.get_env(:prueba2, :username, state.username)
    # Actualizar el estado si es necesario
    state = if current_username != state.username, do: %{state | username: current_username}, else: state

    IO.puts("\n" <> @title_color <> "===== Menú del Sistema =====" <> @reset)
    IO.puts(@info_color <> "Usuario: " <> @highlight_color <> state.username <> @reset)
    IO.puts(@info_color <> "Tu dirección local: " <> @highlight_color <> state.ip_local <> ":" <> Integer.to_string(state.port) <> @reset)
    IO.puts(@info_color <> "Tu IP pública: " <> @highlight_color <> state.public_ip <> ":" <> Integer.to_string(state.port) <> @reset)
    IO.puts("\n" <> @input_color <> "Selecciona una opción:" <> @reset)
    IO.puts("1. " <> @highlight_color <> "Tirar un dado" <> @reset)
    IO.puts("2. " <> @highlight_color <> "Ver lista de peers conectados" <> @reset)
    IO.puts("3. " <> @highlight_color <> "Ver estado del juego" <> @reset)
    IO.puts("4. " <> @highlight_color <> "Unirse a un equipo" <> @reset)
    IO.puts("5. " <> @highlight_color <> "Salir de la red" <> @reset)

    case IO.gets(@input_color <> "> " <> @reset) |> String.trim() do
      "1" ->
        handle_dice_roll(state)
        Process.send_after(self(), :show_menu, 1000)
        {:noreply, state}
      "2" ->
        handle_show_peers()
        Process.send_after(self(), :show_menu, 1000)
        {:noreply, state}
      "3" ->
        handle_show_game_state()
        Process.send_after(self(), :show_menu, 1000)
        {:noreply, state}
      "4" ->
        handle_join_team(state.username)
        Process.send_after(self(), :show_menu, 1000)
        {:noreply, state}
      "5" ->
        handle_exit()
      _ ->
        IO.puts(@error_color <> "Opción no válida, intente de nuevo." <> @reset)
        Process.send_after(self(), :show_menu, 1000)
        {:noreply, state}
    end
  end

  # Crear una nueva red
  defp handle_new_network(state) do
    IO.puts("\n" <> @title_color <> "=== Información de Red ===" <> @reset)
    IO.puts(@info_color <> "Iniciando nueva red P2P como " <> @highlight_color <> state.username <> @reset)
    IO.puts(@info_color <> "Dirección local: " <> @highlight_color <> state.ip_local <> ":" <> Integer.to_string(state.port) <> @reset)
    IO.puts(@info_color <> "IP pública: " <> @highlight_color <> state.public_ip <> ":" <> Integer.to_string(state.port) <> @reset)

    # Solicitar contraseña usando PasswordManager
    password = PasswordManager.get_room_password()
    Prueba2.P2PNetwork.set_password(password)

    msg = if password == "", do: "Sala creada sin contraseña", else: "Sala creada con contraseña"
    IO.puts(@info_color <> msg <> @reset)

    IO.puts(@info_color <> "Comparte tu dirección local para red local o pública para Internet" <> @reset)
    Process.send_after(self(), :show_menu, 500)
  end

  # Unirse a una red existente
  defp handle_join_network(state) do
    IO.puts("\n" <> @title_color <> "=== Conexión ===" <> @reset)
    IO.puts(@info_color <> "Tu dirección local: " <> @highlight_color <> state.ip_local <> ":" <> Integer.to_string(state.port) <> @reset)
    IO.puts(@info_color <> "IP pública: " <> @highlight_color <> state.public_ip <> ":" <> Integer.to_string(state.port) <> @reset)
    IO.puts(@input_color <> "¿A qué red desea unirse? (IP:puerto)" <> @reset)

    target_address = IO.gets(@input_color <> "> " <> @reset) |> String.trim()
    IO.puts(@info_color <> "Intentando unirse a la red a través de " <> @highlight_color <> target_address <> @reset <> "...")

    # Siempre solicitamos la contraseña
    password_hash = PasswordManager.get_join_password()
    join_network(target_address, state.address, state.username, password_hash)
  end

  # Tirar un dado
  defp handle_dice_roll(state) do
    IO.puts(@info_color <> "Tirando un dado..." <> @reset)
    value = Enum.random(1..6)
    IO.puts(@dice_color <> "El resultado es: " <> bright() <> to_string(value) <> @reset)
    Prueba2.P2PNetwork.notify_dice_roll(value, state.username)
  end
  # Mostrar peers conectados
  defp handle_show_peers do
    peers = Prueba2.P2PNetwork.get_peers()
    peers_details = Prueba2.P2PNetwork.get_peers_details()
    peer_count = map_size(peers)

    IO.puts("\n" <> @title_color <> "=== Peers conectados (#{peer_count}) ===" <> @reset)
    if peer_count == 0 do
      IO.puts(@info_color <> "No hay peers conectados todavía." <> @reset)
    else
      IO.puts(@info_color <> "Dirección | Nombre | Equipo" <> @reset)
      IO.puts(@info_color <> "-------------------------------------" <> @reset)

      # Ordenar los peers por equipo
      peers_details
      |> Enum.sort_by(fn {_, details} -> {details[:team] || "Sin equipo", details.username} end)
      |> Enum.each(fn {address, details} ->
        username = details.username
        team = details.team || "Sin equipo"
        team_display = if team == "Sin equipo", do: team, else: @highlight_color <> team <> @reset

        IO.puts(@peer_color <> "- #{username}" <> @reset <>
                @info_color <> " en " <> @highlight_color <> address <> @reset <>
                " | Equipo: " <> team_display)
      end)
    end
  end

  # Salir de la aplicación
  defp handle_exit do
    IO.puts(@info_color <> "Saliendo de la red..." <> @reset)
    Prueba2.P2PNetwork.exit_network()
    IO.puts(@highlight_color <> "¡Hasta luego!" <> @reset)
    System.stop(0)
  end

  # Obtener y verificar un puerto disponible
  defp get_available_port do
    port = get_port_input()
    if check_port_availability(port) == :ok, do: port, else: get_available_port()
  end
  # Verificar disponibilidad del puerto
  defp check_port_availability(port) do
    try do
      case :gen_tcp.listen(port, []) do
        {:ok, socket} ->
          :gen_tcp.close(socket)
          :ok
        {:error, reason} ->
          Logger.warning("Puerto #{port} no disponible: #{inspect(reason)}")
          IO.puts(@error_color <> "Puerto #{port} no disponible, intenta con otro." <> @reset)
          :error
      end
    rescue
      e ->
        Logger.error("Error al verificar puerto: #{inspect(e)}")
        IO.puts(@error_color <> "Error al verificar disponibilidad del puerto, intenta con otro." <> @reset)
        :error
    end
  end

  # Solicitar el puerto
  defp get_port_input do
    IO.puts(@input_color <> "Introduzca el puerto para su servidor:" <> @reset)

    case IO.gets(@input_color <> "> " <> @reset) do
      nil ->
        IO.puts(@error_color <> "Error al leer la entrada. Intentando de nuevo..." <> @reset)
        Process.sleep(1000) # Dar tiempo para que se muestre el mensaje
        get_port_input()
      input ->
        case input |> String.trim() |> Integer.parse() do
          {port_num, _} when port_num > 0 and port_num < 65536 ->
            port_num
          {port_num, _} ->
            IO.puts(@error_color <> "Puerto #{port_num} fuera de rango, debe estar entre 1 y 65535." <> @reset)
            get_port_input()
          :error ->
            IO.puts(@error_color <> "Entrada inválida, debe ingresar un número." <> @reset)
            get_port_input()
        end
    end
  end

  # Unirse a una red existente
  defp join_network(target_address, my_address, username, password_hash) do
    url = "http://#{target_address}/api/join-network"
    payload = %{address: my_address, username: username, password_hash: password_hash}
    headers = [{"Content-Type", "application/json"}]

    try do
      HTTPoison.post!(url, Jason.encode!(payload), headers, [timeout: 10_000, recv_timeout: 10_000])
      |> case do
        %HTTPoison.Response{status_code: 200, body: body} ->
          decoded = Jason.decode!(body)
          peers = decoded["peers"]

          IO.puts(@info_color <> "Conectado a la red exitosamente!" <> @reset)
          IO.puts(@info_color <> "Recibidos " <> @highlight_color <> "#{length(peers)}" <> @reset <> @info_color <> " peers existentes." <> @reset)

          # Agregar peers recibidos
          Enum.each(peers, fn peer ->
            Prueba2.P2PNetwork.add_peer(peer["address"], peer["username"])
          end)

          # Agregar el nodo inicial
          Prueba2.P2PNetwork.add_peer(target_address, decoded["host_username"])
          Process.send_after(self(), :show_menu, 500)

        %HTTPoison.Response{status_code: 401} ->
          IO.puts(@error_color <> "Error: Contraseña incorrecta." <> @reset)
          Process.send_after(self(), :show_welcome, 1000)

        %HTTPoison.Response{status_code: 409} ->
          IO.puts(@error_color <> "Error: El nombre de usuario ya está en uso. Intente unirse con otro nombre." <> @reset)
          Process.send_after(self(), :show_welcome, 1000)

        %HTTPoison.Response{status_code: status_code} ->
          IO.puts(@error_color <> "Error al conectarse: código #{status_code}." <> @reset)
          Process.send_after(self(), :show_welcome, 1000)
      end
    rescue
      e ->
        IO.puts(@error_color <> "Error de conexión: #{inspect(e)}." <> @reset)
        Process.send_after(self(), :show_welcome, 1000)
    end
  end

  # Mostrar estado actual del juego
  defp handle_show_game_state do
    try do
      game_state = Prueba2.GameEngine.get_game_state()

      IO.puts("\n" <> @title_color <> "===== Estado del Juego =====" <> @reset)

      if game_state.game_started do
        IO.puts(@info_color <> "Juego en progreso" <> @reset)
        IO.puts(@info_color <> "Posición máxima del tablero: " <> @highlight_color <> "#{game_state.max_position}" <> @reset)
        IO.puts(@info_color <> "Turno actual: " <> @highlight_color <> "#{game_state.current_turn}" <> @reset)

        if game_state.winner do
          IO.puts(@highlight_color <> "¡El juego ha terminado! Ganador: " <> @winner_color <> game_state.winner <> @reset)
        end

        IO.puts("\n" <> @title_color <> "Posiciones de los equipos:" <> @reset)

        # Ordenar equipos por posición
        teams_by_position = game_state.teams
        |> Enum.sort_by(fn {_, info} -> -info.position end)  # Ordenar descendente por posición

        Enum.each(teams_by_position, fn {team_name, info} ->
          ready_status = if info.ready, do: "listo", else: "no listo"
          players_count = length(info.players)

          IO.puts(@team_color <> "#{team_name}: " <> @highlight_color <> "#{info.position}" <> @reset <>
                  @info_color <> " puntos | #{players_count} jugadores | #{ready_status}" <> @reset)

          # Mostrar jugadores
          Enum.each(info.players, fn player ->
            IO.puts(@info_color <> "  - #{player}" <> @reset)
          end)
        end)

        # Mostrar historial reciente de tiradas
        if length(game_state.roll_history) > 0 do
          IO.puts("\n" <> @title_color <> "Últimos movimientos:" <> @reset)

          game_state.roll_history
          |> Enum.take(5)  # Mostrar solo las últimas 5 tiradas
          |> Enum.each(fn entry ->
            IO.puts(@info_color <> "#{entry.player} (#{entry.team}) tiró un #{entry.value}. Posición: #{entry.position}" <> @reset)
          end)
        end

      else
        IO.puts(@info_color <> "El juego no ha iniciado." <> @reset)

        teams_ready = game_state.teams
        |> Enum.filter(fn {_, info} -> info.ready end)
        |> length()

        teams_total = map_size(game_state.teams)

        IO.puts(@info_color <> "Equipos listos: " <> @highlight_color <> "#{teams_ready} de #{teams_total}" <> @reset)

        # Mostrar lista de equipos
        IO.puts("\n" <> @title_color <> "Equipos:" <> @reset)
        Enum.each(game_state.teams, fn {team_name, info} ->
          players_count = length(info.players)
          ready_status = if info.ready, do: "listo", else: "no listo"

          IO.puts(@team_color <> "#{team_name}: " <> @reset <> @info_color <> "#{players_count} jugadores | #{ready_status}" <> @reset)

          # Mostrar jugadores
          Enum.each(info.players, fn player ->
            IO.puts(@info_color <> "  - #{player}" <> @reset)
          end)
        end)
      end

    rescue
      e ->
        Logger.error("Error al obtener el estado del juego: #{inspect(e)}")
        IO.puts(@error_color <> "Error al obtener el estado del juego." <> @reset)
    end
  end

  # Unirse a un equipo
  defp handle_join_team(player_name) do
    try do
      # Obtener equipos disponibles
      teams = Prueba2.GameEngine.get_teams()

      IO.puts("\n" <> @title_color <> "===== Unirse a un Equipo =====" <> @reset)
      IO.puts(@info_color <> "Equipos disponibles:" <> @reset)

      # Mostrar lista numerada de equipos
      teams_list = teams |> Map.keys() |> Enum.sort()

      Enum.with_index(teams_list, 1) |> Enum.each(fn {team_name, idx} ->
        team_info = teams[team_name]
        players_count = length(team_info.players)

        IO.puts("#{idx}. " <> @highlight_color <> "#{team_name}" <> @reset <>
                @info_color <> " (#{players_count} jugadores)" <> @reset)
      end)

      # Opción para crear nuevo equipo
      new_team_idx = length(teams_list) + 1
      IO.puts("#{new_team_idx}. " <> @highlight_color <> "Crear nuevo equipo" <> @reset)

      # Solicitar selección
      IO.write(@input_color <> "Seleccione un equipo (1-#{new_team_idx}): " <> @reset)

      case IO.gets("") |> String.trim() do
        "" ->
          IO.puts(@error_color <> "Selección cancelada." <> @reset)

        selection ->
          case Integer.parse(selection) do
            {idx, _} when idx >= 1 and idx <= length(teams_list) ->
              # Unirse a un equipo existente
              selected_team = Enum.at(teams_list, idx - 1)
              result = Prueba2.GameEngine.add_player_to_team(player_name, selected_team)

              case result do
                {:ok, _} ->
                  IO.puts(@info_color <> "Te has unido al equipo " <> @highlight_color <> selected_team <> @reset)
                {:error, reason} ->
                  IO.puts(@error_color <> "Error: #{reason}" <> @reset)
              end

            {^new_team_idx, _} ->
              # Crear un nuevo equipo
              IO.write(@input_color <> "Nombre para el nuevo equipo: " <> @reset)
              team_name = IO.gets("") |> String.trim()

              if String.length(team_name) > 0 do
                # Registrar el nuevo equipo
                case Prueba2.GameEngine.register_team(team_name) do
                  {:ok, _} ->
                    IO.puts(@info_color <> "Equipo " <> @highlight_color <> team_name <> @reset <> @info_color <> " creado correctamente." <> @reset)
                    # Ahora unirse al equipo recién creado
                    case Prueba2.GameEngine.add_player_to_team(player_name, team_name) do
                      {:ok, _} ->
                        IO.puts(@info_color <> "Te has unido al equipo " <> @highlight_color <> team_name <> @reset)
                      {:error, reason} ->
                        IO.puts(@error_color <> "Error al unirse: #{reason}" <> @reset)
                    end
                  {:error, reason} ->
                    IO.puts(@error_color <> "Error al crear equipo: #{reason}" <> @reset)
                end
              else
                IO.puts(@error_color <> "Nombre de equipo no válido." <> @reset)
              end

            _ ->
              IO.puts(@error_color <> "Selección no válida." <> @reset)
          end
      end

    rescue
      e ->
        Logger.error("Error al manejar unión a equipo: #{inspect(e)}")
        IO.puts(@error_color <> "Error al procesar la solicitud de unirse a un equipo." <> @reset)
    end
  end

  # Variable para color de equipos y ganador
  @team_color cyan()
  @winner_color bright() <> magenta()
end
