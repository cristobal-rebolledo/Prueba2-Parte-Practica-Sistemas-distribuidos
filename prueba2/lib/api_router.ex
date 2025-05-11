defmodule Prueba2.ApiRouter do
  use Plug.Router
  require Logger
  import IO.ANSI

  @notification_color bright() <> cyan()
  @dice_color magenta()
  @reset reset()

  # Helper function for safely handling collections
  defp safe_size(collection) when is_map(collection), do: map_size(collection)
  defp safe_size(collection) when is_list(collection), do: length(collection)
  defp safe_size(_), do: 0

  # Quitamos Plug.Logger para eliminar los mensajes de solicitudes HTTP
  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  post "/api/dice-roll" do
    %{"value" => value, "username" => username} = conn.body_params
    IO.puts(@dice_color <> "#{username} tiró un dado y obtuvo: " <> bright() <> to_string(value) <> @reset)
    send_resp(conn, 200, "OK")
  end

  post "/api/join-network" do
    %{"address" => requester_address, "username" => requester_username} = conn.body_params
    password_hash = Map.get(conn.body_params, "password_hash")

    # Verificar si el nombre de usuario es muy largo
    max_length = Application.get_env(:prueba2, :max_alias_length, 15)
    my_username = Application.get_env(:prueba2, :username)

    cond do
      # Verificar la contraseña primero
      not Prueba2.P2PNetwork.verify_password(password_hash) ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{
          status: "error",
          message: "Contraseña incorrecta"
        }))

      # Verificar longitud máxima
      String.length(requester_username) > max_length ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{
          status: "error",
          message: "Nombre de usuario demasiado largo (máximo #{max_length} caracteres)"
        }))

      # Verificar nombre vacío
      String.length(requester_username) == 0 ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{
          status: "error",
          message: "El nombre de usuario no puede estar vacío"
        }))

      # Verificar si coincide con el nombre del host
      requester_username == my_username ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(409, Jason.encode!(%{
          status: "error",
          message: "El nombre de usuario ya está en uso"
        }))

      # Verificar si ya existe en la red
      Prueba2.P2PNetwork.username_exists?(requester_username) ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(409, Jason.encode!(%{
          status: "error",
          message: "El nombre de usuario ya está en uso"
        }))

      # Si todo está en orden, añadir al peer
      true ->
        Prueba2.P2PNetwork.add_peer(requester_address, requester_username)

        # Obtenemos los peers para enviar al nuevo miembro
        peers_list = Prueba2.P2PNetwork.get_peers()
                    |> Enum.reject(fn {addr, _} -> addr == requester_address end)
                    |> Enum.map(fn {addr, name} -> %{address: addr, username: name} end)

        # Obtenemos la información de equipos para enviar al nuevo miembro
        teams_data = Prueba2.TeamManager.get_teams()
        # Obtenemos la lista de equipos con IDs secretos
        lista_equipos = Prueba2.TeamManager.get_lista_equipos()

        # Convertir tuplas a mapas para serialización JSON
        lista_equipos_serializable = Enum.map(lista_equipos, fn
          {address, secret, equipo} ->
            %{address: address, secret: secret, equipo: to_string(equipo)}
          {address, secret} ->
            %{address: address, secret: secret, equipo: "No especificado"}
        end)

        # Convertir cualquier MapSet a lista por robustez (aunque TeamManager ya lo hace)
        teams_data_map = Enum.into(teams_data, %{}, fn {team, info} ->
          players = if Map.has_key?(info, :players), do: Map.get(info, :players), else: []
          players_list = if is_list(players), do: players, else: Enum.to_list(players)
          {team, %{info | players: players_list}}
        end)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{
          status: "success",
          peers: peers_list,
          host_username: my_username,
          teams: teams_data_map,
          lista_equipos: lista_equipos_serializable
        }))
    end
  end

  post "/api/new-peer" do
    %{"peer" => %{"address" => new_address, "username" => new_username}, "from_username" => notifier_username} = conn.body_params

    # Verificar si el nombre ya existe antes de añadirlo
    if Prueba2.P2PNetwork.username_exists?(new_username) do
      # Silenciar mensajes de error
    else
      # Mostrar un mensaje más sencillo solo cuando un peer se une
      IO.puts(@notification_color <> "#{new_username} se unió a la red" <> @reset)
      Prueba2.P2PNetwork.add_peer(new_address, new_username)
    end

    send_resp(conn, 200, "OK")
  end
  post "/api/peer-exit" do
    %{"peer" => exiting_peer, "username" => exiting_username} = conn.body_params
    # Mostrar un mensaje sencillo cuando un peer se va
    IO.puts(@notification_color <> "#{exiting_username} salió de la red" <> @reset)

    # Eliminar el peer de la red y actualizar las listas de equipos
    Prueba2.P2PNetwork.remove_peer(exiting_peer)
    Prueba2.TeamManager.remove_peer_from_lists(exiting_peer)

    send_resp(conn, 200, Jason.encode!(%{status: "ok"}))
  end

  post "/api/team-membership-update" do
    %{"player_name" => player_name, "team_name" => team_name} = conn.body_params

    # Actualizar registro local de membresía (usando la nueva API)
    Prueba2.TeamManager.join_team(player_name, team_name)

    # Actualizar la información del peer si se trata de un usuario local
    try do
      Process.send_after(Prueba2.P2PNetwork, {:update_player_team, player_name, team_name}, 100)
    rescue
      _ -> nil # Silenciar errores
    end

    send_resp(conn, 200, Jason.encode!(%{status: "ok"}))
  end

  post "/api/message" do
    %{"message" => message, "from" => from_username} = conn.body_params

    if String.starts_with?(message, "TEAM_EVENT: ") do
      # Es un evento de equipo, lo mostramos con formato especial
      team_message = String.replace_prefix(message, "TEAM_EVENT: ", "")
      # Mantener los mensajes de equipo para mejor experiencia de usuario
      IO.puts(cyan() <> "[EQUIPO] " <> reset() <> team_message)
    else
      # Solo mostrar mensajes importantes o de jugadas
      if String.contains?(message, ["jugó", "ganó", "avanzó", "posición", "terminó"]) do
        IO.puts(bright() <> "#{from_username}: " <> reset() <> message)
      end
      # Eliminamos logs de otros mensajes menos importantes
    end

    send_resp(conn, 200, "OK")
  end

  get "/api/get-teams" do
    # Obtener todos los equipos y enviarlos como respuesta
    teams = Prueba2.TeamManager.get_teams()

    # Convertir cualquier MapSet a lista por robustez
    teams_map = Enum.into(teams, %{}, fn {team, info} ->
      players = if Map.has_key?(info, :players), do: Map.get(info, :players), else: []
      players_list = if is_list(players), do: players, else: Enum.to_list(players)
      {team, %{info | players: players_list}}
    end)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{
      status: "success",
      teams: teams_map
    }))
  end

  get "/api/get-lista-equipos" do
    # Obtener lista de equipos con IDs secretos
    lista_equipos = Prueba2.TeamManager.get_lista_equipos()

    # Convertir tuplas a mapas para serialización JSON
    lista_equipos_serializable = Enum.map(lista_equipos, fn
      {address, secret, equipo} ->
        %{address: address, secret: secret, equipo: to_string(equipo)}
      {address, secret} ->
        %{address: address, secret: secret, equipo: "No especificado"}
    end)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{
      status: "success",
      lista_equipos: lista_equipos_serializable
    }))
  end

  get "/api/get-lista-peers" do
    # Obtener lista de peers con información de equipo
    lista_peers = Prueba2.TeamManager.get_lista_peers()

    # Convertir tuplas a mapas para serialización JSON
    lista_peers_serializable = Enum.map(lista_peers, fn
      {address, username, equipo} ->
        %{address: address, username: username, equipo: to_string(equipo)}
      {address, username} ->
        %{address: address, username: username, equipo: "NA"}
    end)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{
      status: "success",
      lista_peers: lista_peers_serializable
    }))
  end

  match _ do
    send_resp(conn, 404, "Ruta no encontrada")
  end
end
