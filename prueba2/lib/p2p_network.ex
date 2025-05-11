defmodule Prueba2.P2PNetwork do
  use GenServer
  require Logger
  import IO.ANSI
  alias Prueba2.PasswordManager

  @dice_color magenta()
  @reset reset()

  # API pública
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def get_peers, do: GenServer.call(__MODULE__, :get_peers)
  def add_peer(address, username), do: GenServer.cast(__MODULE__, {:add_peer, address, username})
  def remove_peer(address), do: GenServer.cast(__MODULE__, {:remove_peer, address})
  def notify_dice_roll(value, username), do: GenServer.cast(__MODULE__, {:dice_roll, value, username})
  def exit_network, do: GenServer.cast(__MODULE__, :exit_network)

  # API para gestión de equipos
  def update_peer_team(address, team_name), do: GenServer.cast(__MODULE__, {:update_peer_team, address, team_name})
  def broadcast_message(message), do: GenServer.cast(__MODULE__, {:broadcast_message, message})

  # API de contraseñas
  def set_password(password), do: GenServer.cast(__MODULE__, {:set_password, PasswordManager.hash_password(password)})
  def verify_password(password_hash), do: GenServer.call(__MODULE__, {:verify_password, password_hash})

  # API para nombres de usuario
  def username_exists?(username), do: GenServer.call(__MODULE__, {:username_exists?, username})

  # Callbacks
  @impl true
  def init(_) do
    # Inicializamos también con el nombre del host
    my_username = Application.get_env(:prueba2, :username, nil)
    initial_usernames = if my_username, do: MapSet.new([my_username]), else: MapSet.new()

    {:ok, %{peers: %{}, usernames: initial_usernames, password_hash: nil, peer_teams: %{}}}
  end

  @impl true
  def handle_call(:get_peers, _from, state), do: {:reply, state.peers, state}

  @impl true
  def handle_call({:verify_password, password_hash}, _from, state) do
    {:reply, PasswordManager.verify_password(state.password_hash, password_hash), state}
  end

  @impl true
  def handle_call({:username_exists?, username}, _from, state) do
    # Verificar si el nombre de usuario ya existe
    exists = MapSet.member?(state.usernames, username)
    {:reply, exists, state}
  end

  @impl true
  def handle_cast({:add_peer, address, username}, state) do
    # Si la dirección ya existe o el username ya está en uso, ignoramos
    cond do
      Map.has_key?(state.peers, address) ->
        {:noreply, state}
      MapSet.member?(state.usernames, username) ->
        # Nombre de usuario ya está en uso (incluye el del host)
        # Silenciamos la advertencia para reducir el ruido
        {:noreply, state}
      true ->
        # Podemos añadir el peer
        notify_existing_peers_about_new_peer(state.peers, address, username)
        new_peers = Map.put(state.peers, address, username)
        new_usernames = MapSet.put(state.usernames, username)
        {:noreply, %{state | peers: new_peers, usernames: new_usernames}}
    end
  end

  @impl true
  def handle_cast({:remove_peer, address}, state) do
    case Map.fetch(state.peers, address) do
      {:ok, username} ->
        # Eliminamos el log para reducir ruido
        new_peers = Map.delete(state.peers, address)
        new_usernames = MapSet.delete(state.usernames, username)
        {:noreply, %{state | peers: new_peers, usernames: new_usernames}}
      :error ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:set_password, password_hash}, state) do
    {:noreply, %{state | password_hash: password_hash}}
  end

  @impl true
  def handle_cast({:dice_roll, value, username}, state) do
    IO.puts(@dice_color <> "#{username} tiró un dado y obtuvo: " <> bright() <> to_string(value) <> @reset)
    broadcast_dice_roll_to_peers(state.peers, value, username)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:exit_network, state) do
    # Eliminamos el log para reducir ruido
    notify_exit_to_peers(state.peers)
    {:noreply, %{state | peers: %{}, usernames: MapSet.new()}}
  end

  @impl true
  def handle_cast({:update_peer_team, peer_address, team_name}, state) do
    # Silenciamos el mensaje de log para reducir ruido
    new_peer_teams = Map.put(state.peer_teams, peer_address, team_name)
    {:noreply, %{state | peer_teams: new_peer_teams}}
  end

  @impl true
  def handle_cast({:broadcast_message, message}, state) do
    Enum.each(state.peers, fn {address, _username} ->
      Task.start(fn -> send_broadcast_to_peer(address, message) end)
    end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:update_player_team, player_name, team_name}, state) do
    # Silenciamos el mensaje de log para reducir ruido

    # Buscar la dirección del peer con ese nombre
    peer_address = Enum.find_value(state.peers, fn {address, username} ->
      if username == player_name, do: address, else: nil
    end)

    if peer_address do
      new_peer_teams = Map.put(state.peer_teams, peer_address, team_name)
      {:noreply, %{state | peer_teams: new_peer_teams}}
    else
      # Si no encontramos el peer, puede ser porque es un jugador local
      my_username = Application.get_env(:prueba2, :username)
      my_address = Application.get_env(:prueba2, :address)

      if my_username == player_name do
        new_peer_teams = Map.put(state.peer_teams, my_address, team_name)
        {:noreply, %{state | peer_teams: new_peer_teams}}
      else
        {:noreply, state}
      end
    end
  end

  # Funciones privadas
  defp broadcast_dice_roll_to_peers(peers, value, username) do
    Enum.each(peers, fn {address, _} ->
      Task.start(fn -> send_dice_roll_to_peer(address, value, username) end)
    end)
  end

  defp send_dice_roll_to_peer(address, value, username) do
    url = "http://#{address}/api/dice-roll"
    payload = %{value: value, username: username}

    try do
      headers = [{"Content-Type", "application/json"}]
      HTTPoison.post!(url, Jason.encode!(payload), headers, [timeout: 5_000, recv_timeout: 5_000])
    rescue
      _ ->
        # Eliminamos el log para reducir ruido
        remove_peer(address)
    end
  end

  defp notify_existing_peers_about_new_peer(peers, new_address, new_username) do
    my_username = Application.get_env(:prueba2, :username)

    Enum.each(peers, fn {address, _} ->
      url = "http://#{address}/api/new-peer"
      payload = %{
        peer: %{address: new_address, username: new_username},
        from_username: my_username
      }

      try do
        HTTPoison.post!(url, Jason.encode!(payload), [{"Content-Type", "application/json"}], [timeout: 5_000])
      rescue
        _ -> remove_peer(address)
      end
    end)
  end

  defp notify_exit_to_peers(peers) do
    my_address = Application.get_env(:prueba2, :address)
    my_username = Application.get_env(:prueba2, :username)

    Enum.each(peers, fn {address, _peer_username} ->
      Task.start(fn ->
        url = "http://#{address}/api/peer-exit"
        payload = %{peer: my_address, username: my_username}

        try do
          HTTPoison.post(url, Jason.encode!(payload), [{"Content-Type", "application/json"}], [timeout: 5_000])
          |> case do
            {:ok, %HTTPoison.Response{status_code: 200}} ->
              nil # Eliminamos el log para reducir ruido
            _ ->
              nil # Eliminamos el log para reducir ruido
          end
        rescue
          _ -> nil # Eliminamos el log para reducir ruido
        end
      end)
    end)

    Process.sleep(500) # Esperar un momento para notificaciones
  end

  defp send_broadcast_to_peer(address, message) do
    url = "http://#{address}/api/message"
    payload = %{
      message: message,
      from: Application.get_env(:prueba2, :username)
    }

    try do
      headers = [{"Content-Type", "application/json"}]
      HTTPoison.post!(url, Jason.encode!(payload), headers, [timeout: 5_000, recv_timeout: 5_000])
    rescue
      _ -> nil # Eliminamos el log para reducir ruido
    end
  end
end
