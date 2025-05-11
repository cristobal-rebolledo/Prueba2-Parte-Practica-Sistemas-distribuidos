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
  @team_color cyan()
  @reset reset()

  # Helper functions for safe operations
  defp safe_size(collection) when is_map(collection), do: map_size(collection)
  defp safe_size(collection) when is_list(collection), do: length(collection)
  defp safe_size(_), do: 0

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

    # Iniciar el servidor HTTP
    {:ok, _} = Plug.Cowboy.http(Prueba2.ApiRouter, [], port: port, ip: {0, 0, 0, 0})

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

    name = IO.gets("") |> String.trim()

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

    # Verificar si el usuario pertenece a un equipo
    teams = Prueba2.TeamManager.get_teams()
    user_team = find_user_team(teams, state.username)

    IO.puts("\n" <> @input_color <> "Selecciona una opción:" <> @reset)
    IO.puts("1. " <> @highlight_color <> "Tirar un dado" <> @reset)
    IO.puts("2. " <> @highlight_color <> "Ver lista de peers conectados" <> @reset)
    IO.puts("3. " <> @highlight_color <> "Ver estado del juego" <> @reset)

    if user_team do
      IO.puts("4. " <> @highlight_color <> "Solicitar inicio del juego" <> @reset)
      IO.puts("5. " <> @highlight_color <> "Salir de la red" <> @reset)
    else
      IO.puts("4. " <> @highlight_color <> "Unirse a un equipo" <> @reset)
      IO.puts("5. " <> @highlight_color <> "Salir de la red" <> @reset)
    end

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
        if user_team do
          handle_request_start_game(state.username, user_team)
        else
          handle_team_selection(state.username)
        end
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

    # Solicitar información de equipos
    IO.puts(@input_color <> "¿Cuántos equipos deseas crear? (2-4):" <> @reset)
    team_count_input = IO.gets(@input_color <> "> " <> @reset) |> String.trim()

    team_count = case Integer.parse(team_count_input) do
      {count, _} when count >= 2 and count <= 4 -> count
      _ ->
        IO.puts(@error_color <> "Valor inválido. Utilizando 2 equipos por defecto." <> @reset)
        2
    end

    IO.puts(@input_color <> "¿Cuántos jugadores máximo por equipo? (2-5):" <> @reset)
    max_players_input = IO.gets(@input_color <> "> " <> @reset) |> String.trim()

    max_players = case Integer.parse(max_players_input) do
      {players, _} when players >= 2 and players <= 5 -> players
      _ ->
        IO.puts(@error_color <> "Valor inválido. Utilizando 3 jugadores por defecto." <> @reset)
        3
    end
    Application.put_env(:prueba2, :max_players_per_team, max_players)
    # Crear los nombres de equipos
    teams = Enum.map(1..team_count, fn i -> "Equipo #{i}" end)

    # Solicitar personalización de nombres
    teams = Enum.with_index(teams, 1)
      |> Enum.map(fn {default_name, idx} ->
        IO.puts(@input_color <> "Nombre para el equipo #{idx} (Enter para usar '#{default_name}'):" <> @reset)
        custom_name = IO.gets(@input_color <> "> " <> @reset) |> String.trim()
        if String.length(custom_name) > 0, do: custom_name, else: default_name
      end)

    # Inicializar el sistema de equipos
    case Prueba2.TeamManager.initialize_teams(teams, max_players) do
      {:ok, message} ->
        IO.puts(@info_color <> message <> @reset)
      {:error, reason} ->
        IO.puts(@error_color <> "Error al inicializar equipos: #{reason}" <> @reset)
    end

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
    peer_count = safe_size(peers)

    IO.puts("\n" <> @title_color <> "=== Peers conectados (#{peer_count}) ===" <> @reset)
    if peer_count == 0 do
      IO.puts(@info_color <> "No hay peers conectados todavía." <> @reset)
    else
      Enum.each(peers, fn {address, username} ->
        IO.puts(@peer_color <> "- #{username}" <> @reset <> @info_color <> " en " <> @highlight_color <> address <> @reset)
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
        {:ok, socket} -> :gen_tcp.close(socket); :ok
        {:error, _} -> :error
      end
    rescue
      _ -> :error
    end
  end

  # Solicitar el puerto
  defp get_port_input do
    IO.puts(@input_color <> "Introduzca el puerto para su servidor:" <> @reset)

    case IO.gets(@input_color <> "> " <> @reset) |> String.trim() |> Integer.parse() do
      {port_num, _} when port_num > 0 and port_num < 65536 -> port_num
      _ ->
        IO.puts(@error_color <> "Puerto inválido, debe ser un número entre 1 y 65535." <> @reset)
        get_port_input()
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

          # Si la respuesta incluye información de equipos, sincronizamos
          if Map.has_key?(decoded, "teams") do
            teams_data = decoded["teams"]
            IO.puts(@info_color <> "Sincronizando información de " <> @highlight_color <> "#{safe_size(teams_data)}" <> @reset <> @info_color <> " equipos." <> @reset)
            Prueba2.TeamManager.sync_teams_from_network(teams_data)
          else
            # De lo contrario, solicitamos la información de equipos al nodo inicial
            IO.puts(@info_color <> "Solicitando información de equipos..." <> @reset)
            request_teams_data(target_address)
          end

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

  # Ver estado del juego y equipos
  defp handle_show_game_state do
    teams = Prueba2.TeamManager.get_teams()

    IO.puts("\n" <> @title_color <> "===== Estado del Juego =====" <> @reset)

    if safe_size(teams) == 0 do
      IO.puts(@info_color <> "No hay equipos registrados todavía." <> @reset)
    else
      all_ready = Prueba2.TeamManager.all_teams_ready?()

      if all_ready do
        IO.puts(@info_color <> "Todos los equipos están listos para jugar." <> @reset)
      else
        ready_count = Enum.count(teams, fn {_, info} -> info.ready end)
        IO.puts(@info_color <> "Equipos listos: #{ready_count} de #{safe_size(teams)}" <> @reset)
      end

      IO.puts("\n" <> @title_color <> "Equipos:" <> @reset)

      Enum.each(teams, fn {team_name, info} ->
        ready_status = if info.ready, do: "listo", else: "no listo"
        position = info.position

        IO.puts(@team_color <> "#{team_name}: " <> @reset <>
                @info_color <> "#{length(info.players)} jugadores | Posición: #{position} | #{ready_status}" <> @reset)

        # Mostrar jugadores
        Enum.each(info.players, fn player ->
          IO.puts(@info_color <> "  - #{player}" <> @reset)
        end)
      end)
    end
  end

  # Solicitar inicio del juego
  defp handle_request_start_game(username, team_name) do
    case Prueba2.TeamManager.set_team_ready(team_name) do
      {:ok, _} ->
        IO.puts(@info_color <> "Tu equipo está listo para iniciar el juego" <> @reset)
      {:error, reason} ->
        IO.puts(@error_color <> "Error: #{reason}" <> @reset)
    end
  end

  # Manejar la selección de equipo
  defp handle_team_selection(player_name) do
    # Obtener equipos disponibles
    teams = Prueba2.TeamManager.get_teams()

    IO.puts("\n" <> @title_color <> "===== Unirse a un Equipo =====" <> @reset)

    if safe_size(teams) == 0 do
      IO.puts(@info_color <> "No hay equipos disponibles todavía. Espera a que el creador de la red los configure." <> @reset)
    else
      IO.puts(@info_color <> "Equipos disponibles:" <> @reset)

      # Mostrar lista numerada de equipos
      teams_list = teams |> Map.keys() |> Enum.sort()

      Enum.with_index(teams_list, 1) |> Enum.each(fn {team_name, idx} ->
        team_info = teams[team_name]
        players_count = length(team_info.players)
        max_players = Application.get_env(:prueba2, :max_players_per_team, 3)

        # Mostrar estado completo si está lleno
        status_text = if players_count >= max_players do
          " (#{players_count}/#{max_players }) - LLENO"
        else
          " (#{players_count} jugadores)"
        end

        IO.puts("#{idx}. " <> @highlight_color <> "#{team_name}" <> @reset <>
                @info_color <> status_text <> @reset)
      end)

      # Solicitar selección
      IO.write(@input_color <> "Seleccione un equipo (1-#{length(teams_list)}): " <> @reset)

      case IO.gets("") |> String.trim() do
        selection ->
          case Integer.parse(selection) do
            {idx, _} when idx >= 1 and idx <= length(teams_list) ->
              # Unirse a equipo existente
              selected_team = Enum.at(teams_list, idx - 1)
              team_info = teams[selected_team]
              max_players = Application.get_env(:prueba2, :max_players_per_team, 3)
              IO.puts(@info_color <> "Valor actual de max_players: #{max_players}" <> @reset)
              # Verificar si el equipo está lleno
              if length(team_info.players) >= max_players do
                IO.puts(@error_color <> "El equipo #{selected_team} ya está lleno (#{length(team_info.players)}/#{max_players}). Por favor seleccione otro equipo." <> @reset)
                # Volver a mostrar selección de equipos
                handle_team_selection(player_name)
              else
                # Proceder a unirse al equipo
                result = Prueba2.TeamManager.join_team(player_name, selected_team)
                process_team_result(result)
              end

            _ ->
              IO.puts(@error_color <> "Selección inválida, intente de nuevo." <> @reset)
              # Volver a mostrar selección de equipos
              handle_team_selection(player_name)
          end
      end
    end
  end


  # Procesar el resultado de la unión a un equipo
  defp process_team_result(result) do
    case result do
      {:ok, message} ->
        IO.puts(@info_color <> message <> @reset)
      {:error, reason} ->
        IO.puts(@error_color <> "Error: #{reason}" <> @reset)
    end
  end

  # Encontrar el equipo de un usuario
  defp find_user_team(teams, username) do
    Enum.find_value(teams, fn {team_name, team_data} ->
      if username in team_data.players do
        team_name
      else
        nil
      end
    end)
  end

  # Solicitar información de equipos a un peer
  defp request_teams_data(peer_address) do
    url = "http://#{peer_address}/api/get-teams"
    headers = [{"Content-Type", "application/json"}]

    try do
      response = HTTPoison.get!(url, headers, [timeout: 5_000, recv_timeout: 5_000])

      case response do
        %HTTPoison.Response{status_code: 200, body: body} ->
          decoded = Jason.decode!(body)
          teams_data = decoded["teams"]

          if teams_data && safe_size(teams_data) > 0 do
            IO.puts(@info_color <> "Recibida información de #{safe_size(teams_data)} equipos." <> @reset)
            Prueba2.TeamManager.sync_teams_from_network(teams_data)
          else
            IO.puts(@info_color <> "No hay equipos registrados en la red." <> @reset)
          end

        _ ->
          IO.puts(@error_color <> "Error al solicitar información de equipos." <> @reset)
      end
    rescue
      e ->
        IO.puts(@error_color <> "Error de conexión: #{inspect(e)}." <> @reset)
    end
  end
end
