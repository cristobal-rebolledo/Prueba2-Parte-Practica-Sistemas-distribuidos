defmodule Prueba2.P2PNetwork do
  use GenServer
  require Logger
  import IO.ANSI

  # Solo dejamos los colores que realmente usamos
  @dice_color magenta()
  @reset reset()

  # Cliente API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_peers do
    GenServer.call(__MODULE__, :get_peers)
  end

  def add_peer(address, username) do
    GenServer.cast(__MODULE__, {:add_peer, address, username})
  end

  def remove_peer(address) do
    GenServer.cast(__MODULE__, {:remove_peer, address})
  end

  def notify_dice_roll(value, username) do
    GenServer.cast(__MODULE__, {:dice_roll, value, username})
  end

  def exit_network do
    GenServer.cast(__MODULE__, :exit_network)
  end

  # Callbacks del servidor
  @impl true
  def init(_opts) do
    {:ok, %{peers: %{}}}  # Ahora peers es un mapa con {address => username}
  end

  @impl true
  def handle_call(:get_peers, _from, state) do
    {:reply, state.peers, state}
  end

  @impl true
  def handle_cast({:add_peer, address, username}, state) do
    if Map.has_key?(state.peers, address) do
      {:noreply, state}
    else
      Logger.info("Añadiendo peer: #{username} en #{address}")
      notify_existing_peers_about_new_peer(state.peers, address, username)
      {:noreply, %{state | peers: Map.put(state.peers, address, username)}}
    end
  end

  @impl true
  def handle_cast({:remove_peer, address}, state) do
    username = Map.get(state.peers, address, "Desconocido")
    Logger.info("Eliminando peer: #{username} (#{address})")
    {:noreply, %{state | peers: Map.delete(state.peers, address)}}
  end

  @impl true
  def handle_cast({:dice_roll, value, username}, state) do
    IO.puts(@dice_color <> "#{username} tiró un dado y obtuvo: " <> bright() <> to_string(value) <> @reset)
    broadcast_dice_roll_to_peers(state.peers, value, username)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:exit_network, state) do
    Logger.info("Saliendo de la red, notificando a todos los peers")
    notify_exit_to_peers(state.peers)
    {:noreply, %{state | peers: %{}}}
  end

  # Funciones de comunicación HTTP usando HTTPoison
  defp broadcast_dice_roll_to_peers(peers, value, username) do
    Enum.each(peers, fn {address, _peer_username} ->
      Task.start(fn ->
        send_dice_roll_to_peer(address, value, username)
      end)
    end)
  end

  defp send_dice_roll_to_peer(address, value, username) do
    url = "http://#{address}/api/dice-roll"
    payload = %{
      value: value,
      username: username
    }

    try do
      headers = [{"Content-Type", "application/json"}]
      HTTPoison.post!(url, Jason.encode!(payload), headers, [timeout: 5_000, recv_timeout: 5_000])
      :ok
    rescue
      e ->
        Logger.warning("No se pudo contactar al peer #{address}: #{inspect(e)}", [])
        remove_peer(address)
    end
  end

  defp notify_existing_peers_about_new_peer(peers, new_address, new_username) do
    # Obtener nuestro propio nombre de usuario para enviarlo en las notificaciones
    my_username = Application.get_env(:prueba2, :username)

    Enum.each(peers, fn {address, _username} ->
      url = "http://#{address}/api/new-peer"
      payload = %{
        peer: %{
          address: new_address,
          username: new_username
        },
        from_username: my_username
      }

      try do
        headers = [{"Content-Type", "application/json"}]
        HTTPoison.post!(url, Jason.encode!(payload), headers, [timeout: 5_000, recv_timeout: 5_000])
        :ok
      rescue
        _ -> remove_peer(address)
      end
    end)
  end

  defp notify_exit_to_peers(peers) do
    my_address = Application.get_env(:prueba2, :address)
    my_username = Application.get_env(:prueba2, :username)

    Logger.info("Enviando notificación de salida a #{map_size(peers)} peers")

    Enum.each(peers, fn {address, peer_username} ->
      url = "http://#{address}/api/peer-exit"
      payload = %{
        peer: my_address,
        username: my_username
      }

      # Usamos Task.async para enviar las notificaciones en paralelo pero con seguimiento
      Task.start(fn ->
        try do
          headers = [{"Content-Type", "application/json"}]
          response = HTTPoison.post(url, Jason.encode!(payload), headers, [timeout: 5_000, recv_timeout: 5_000])

          case response do
            {:ok, %HTTPoison.Response{status_code: 200}} ->
              Logger.info("#{peer_username} (#{address}) confirmó eliminación")
            {:ok, _} ->
              Logger.warning("Respuesta inesperada de #{peer_username} (#{address}) al notificar salida", [])
            {:error, %HTTPoison.Error{reason: reason}} ->
              Logger.warning("Error al notificar salida a #{peer_username} (#{address}): #{inspect(reason)}", [])
          end
        rescue
          e ->
            Logger.warning("Excepción al notificar salida a #{peer_username} (#{address}): #{inspect(e)}", [])
        end
      end)
    end)

    # Esperar un momento para dar tiempo a que se envíen las notificaciones
    # antes de que la aplicación termine
    Process.sleep(500)
  end
end
