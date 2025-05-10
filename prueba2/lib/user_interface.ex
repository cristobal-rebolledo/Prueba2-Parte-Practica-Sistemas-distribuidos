defmodule Prueba2.UserInterface do
  use GenServer
  require Logger
  import IO.ANSI
  alias Prueba2.IpDetector

  # Definir colores para diferentes tipos de mensajes
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
    # Pedir el nombre de usuario
    username = get_username()

    # Obtener IP local real antes de pedir el puerto
    ip_local = IpDetector.get_real_local_ip()

    # Solicitar y verificar puerto disponible
    port = get_available_port()

    # Usamos la IP local para mostrarla, pero escuchamos en todas las interfaces (0.0.0.0)
    address = "#{ip_local}:#{port}"
    Application.put_env(:prueba2, :address, address)
    Application.put_env(:prueba2, :username, username)

    # Escuchar en todas las interfaces (0.0.0.0) para aceptar conexiones externas
    {:ok, _} = Plug.Cowboy.http(Prueba2.ApiRouter, [], port: port, ip: {0, 0, 0, 0})

    # Usar el nuevo módulo para obtener la IP pública
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
    IO.puts("\n" <> @title_color <> "==== Sistema P2P de Dados ====" <> @reset)
    IO.puts(@info_color <> "¡Bienvenido al juego de dados P2P!" <> @reset)
    IO.write(@input_color <> "Introduce tu nombre de usuario: " <> @reset)

    name = IO.gets("") |> String.trim()
    if String.length(name) == 0 do
      IO.puts(@error_color <> "El nombre no puede estar vacío, intenta de nuevo." <> @reset)
      get_username()
    else
      name
    end
  end

  def handle_info(:show_welcome, state) do
    IO.puts("\n" <> @title_color <> "===== Sistema P2P de Dados =====" <> @reset)
    IO.puts(@info_color <> "Usuario: " <> @highlight_color <> state.username <> @reset)
    IO.puts(@info_color <> "Tu dirección local: " <> @highlight_color <> state.ip_local <> ":" <> Integer.to_string(state.port) <> @reset)
    IO.puts(@info_color <> "Tu IP pública: " <> @highlight_color <> state.public_ip <> ":" <> Integer.to_string(state.port) <> @reset <> @info_color <> " (usa esta para conexiones desde Internet)" <> @reset)
    IO.puts("\n" <> @input_color <> "¿Qué desea hacer?" <> @reset)
    IO.puts("1. " <> @highlight_color <> "Iniciar una nueva red" <> @reset)
    IO.puts("2. " <> @highlight_color <> "Unirse a una red existente" <> @reset)
    choice = IO.gets(@input_color <> "> " <> @reset) |> String.trim()

    case choice do
      "1" -> handle_new_network(state)
      "2" -> handle_join_network(state)
      _ ->
        IO.puts(@error_color <> "Opción no válida, intente de nuevo." <> @reset)
        Process.send_after(self(), :show_welcome, 100)
    end

    {:noreply, state}
  end

  def handle_info(:show_menu, state) do
    IO.puts("\n" <> @title_color <> "===== Menú del Sistema =====" <> @reset)
    IO.puts(@info_color <> "Usuario: " <> @highlight_color <> state.username <> @reset)
    IO.puts(@info_color <> "Tu dirección local: " <> @highlight_color <> state.ip_local <> ":" <> Integer.to_string(state.port) <> @reset)
    IO.puts(@info_color <> "Tu IP pública: " <> @highlight_color <> state.public_ip <> ":" <> Integer.to_string(state.port) <> @reset)
    IO.puts("\n" <> @input_color <> "Selecciona una opción:" <> @reset)
    IO.puts("1. " <> @highlight_color <> "Tirar un dado" <> @reset)
    IO.puts("2. " <> @highlight_color <> "Ver lista de peers conectados" <> @reset)
    IO.puts("3. " <> @highlight_color <> "Salir de la red" <> @reset)
    choice = IO.gets(@input_color <> "> " <> @reset) |> String.trim()

    case choice do
      "1" -> handle_dice_roll(state)
      "2" -> handle_show_peers()
      "3" -> handle_exit()
      _ ->
        IO.puts(@error_color <> "Opción no válida, intente de nuevo." <> @reset)
    end

    Process.send_after(self(), :show_menu, 1000)
    {:noreply, state}
  end

  # Manejo de opciones de menú
  defp handle_new_network(state) do
    IO.puts("\n" <> @title_color <> "=== Información de Red ===" <> @reset)
    IO.puts(@info_color <> "Iniciando nueva red P2P como " <> @highlight_color <> state.username <> @reset)
    IO.puts(@info_color <> "Dirección local: " <> @highlight_color <> state.ip_local <> ":" <> Integer.to_string(state.port) <> @reset)
    IO.puts(@info_color <> "IP pública: " <> @highlight_color <> state.public_ip <> ":" <> Integer.to_string(state.port) <> @reset)
    IO.puts(@info_color <> "Comparte tu dirección local para red local o pública para Internet" <> @reset)
    Process.send_after(self(), :show_menu, 500)
  end

  defp handle_join_network(state) do
    IO.puts("\n" <> @title_color <> "=== Conexión ===" <> @reset)
    IO.puts(@info_color <> "Tu dirección local: " <> @highlight_color <> state.ip_local <> ":" <> Integer.to_string(state.port) <> @reset)
    IO.puts(@info_color <> "IP pública: " <> @highlight_color <> state.public_ip <> ":" <> Integer.to_string(state.port) <> @reset)
    IO.puts(@input_color <> "¿A qué red desea unirse? (IP:puerto)" <> @reset)
    target_address = IO.gets(@input_color <> "> " <> @reset) |> String.trim()
    IO.puts(@info_color <> "Intentando unirse a la red a través de " <> @highlight_color <> target_address <> @reset <> "...")
    join_network(target_address, state.address, state.username)
  end

  defp handle_dice_roll(state) do
    IO.puts(@info_color <> "Tirando un dado..." <> @reset)
    value = Enum.random(1..6)
    IO.puts(@dice_color <> "El resultado es: " <> bright() <> to_string(value) <> @reset)
    Prueba2.P2PNetwork.notify_dice_roll(value, state.username)
  end

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

  defp handle_exit do
    IO.puts(@info_color <> "Saliendo de la red..." <> @reset)
    Prueba2.P2PNetwork.exit_network()
    IO.puts(@highlight_color <> "¡Hasta luego!" <> @reset)
    System.stop(0)
  end

  defp get_available_port do
    port = get_port_input()
    case check_port_availability(port) do
      :ok -> port
      :error ->
        IO.puts(@error_color <> "El puerto #{port} no está disponible." <> @reset)
        get_available_port()
    end
  end

  defp check_port_availability(port) do
    try do
      case :gen_tcp.listen(port, []) do
        {:ok, socket} ->
          :gen_tcp.close(socket)
          :ok
        {:error, _reason} ->
          :error
      end
    rescue
      _ -> :error
    end
  end

  defp get_port_input do
    IO.puts(@input_color <> "Introduzca el puerto para su servidor:" <> @reset)
    port = IO.gets(@input_color <> "> " <> @reset) |> String.trim()
    case Integer.parse(port) do
      {port_num, _} when port_num > 0 and port_num < 65536 -> port_num
      _ ->
        IO.puts(@error_color <> "Puerto inválido, debe ser un número entre 1 y 65535." <> @reset)
        get_port_input()
    end
  end

  # Actualizado para usar HTTPoison y enviar nombre de usuario
  defp join_network(target_address, my_address, username) do
    url = "http://#{target_address}/api/join-network"

    payload = %{
      address: my_address,
      username: username
    }

    # Usar HTTPoison en lugar de :httpc para simplificar
    try do
      headers = [{"Content-Type", "application/json"}]
      response = HTTPoison.post!(url, Jason.encode!(payload), headers, [timeout: 10_000, recv_timeout: 10_000])

      case response do
        %HTTPoison.Response{status_code: 200, body: body} ->
          decoded = Jason.decode!(body)
          peers = decoded["peers"]
          IO.puts(@info_color <> "Conectado a la red exitosamente!" <> @reset)
          IO.puts(@info_color <> "Recibidos " <> @highlight_color <> "#{length(peers)}" <> @reset <> @info_color <> " peers existentes." <> @reset)

          # Agregar todos los peers recibidos
          Enum.each(peers, fn peer ->
            Prueba2.P2PNetwork.add_peer(peer["address"], peer["username"])
          end)

          # Agregar el nodo al que nos conectamos inicialmente
          Prueba2.P2PNetwork.add_peer(target_address, decoded["host_username"])

          Process.send_after(self(), :show_menu, 500)

        %HTTPoison.Response{status_code: status_code} ->
          IO.puts(@error_color <> "Error al conectarse a la red: código #{status_code}." <> @reset)
          Process.send_after(self(), :show_welcome, 1000)
      end
    rescue
      e ->
        IO.puts(@error_color <> "Error al conectarse a la red: #{inspect(e)}." <> @reset)
        Process.send_after(self(), :show_welcome, 1000)
    end
  end
end
