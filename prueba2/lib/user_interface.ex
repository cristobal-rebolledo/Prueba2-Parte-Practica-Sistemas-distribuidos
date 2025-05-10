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
    IO.puts("\n" <> @input_color <> "Selecciona una opción:" <> @reset)
    IO.puts("1. " <> @highlight_color <> "Tirar un dado" <> @reset)
    IO.puts("2. " <> @highlight_color <> "Ver lista de peers conectados" <> @reset)
    IO.puts("3. " <> @highlight_color <> "Salir de la red" <> @reset)

    case IO.gets(@input_color <> "> " <> @reset) |> String.trim() do
      "1" ->
        handle_dice_roll(state)
        Process.send_after(self(), :show_menu, 1000)
        {:noreply, state}
      "2" ->
        handle_show_peers()
        Process.send_after(self(), :show_menu, 1000)
        {:noreply, state}
      "3" -> handle_exit()
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
    peer_count = map_size(peers)

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
end
