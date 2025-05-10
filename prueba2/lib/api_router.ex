defmodule Prueba2.ApiRouter do
  use Plug.Router
  require Logger
  import IO.ANSI

  @notification_color bright() <> cyan()
  @dice_color magenta()
  @error_color bright() <> red()
  @reset reset()

  plug Plug.Logger
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

    IO.puts(@notification_color <> "#{requester_username} (#{requester_address}) solicita unirse a la red" <> @reset)

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
        IO.puts(@error_color <> "Error: Nombre de usuario demasiado largo (máximo #{max_length} caracteres)" <> @reset)
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{
          status: "error",
          message: "Nombre de usuario demasiado largo (máximo #{max_length} caracteres)"
        }))

      # Verificar nombre vacío
      String.length(requester_username) == 0 ->
        IO.puts(@error_color <> "Error: El nombre de usuario no puede estar vacío" <> @reset)
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{
          status: "error",
          message: "El nombre de usuario no puede estar vacío"
        }))

      # Verificar si coincide con el nombre del host
      requester_username == my_username ->
        IO.puts(@error_color <> "Error: El nombre de usuario coincide con el del host" <> @reset)
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(409, Jason.encode!(%{
          status: "error",
          message: "El nombre de usuario ya está en uso"
        }))

      # Verificar si ya existe en la red
      Prueba2.P2PNetwork.username_exists?(requester_username) ->
        IO.puts(@error_color <> "Error: El nombre de usuario ya está en uso en la red" <> @reset)
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

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{
          status: "success",
          peers: peers_list,
          host_username: my_username
        }))
    end
  end

  post "/api/new-peer" do
    %{"peer" => %{"address" => new_address, "username" => new_username}, "from_username" => notifier_username} = conn.body_params

    # Verificar si el nombre ya existe antes de añadirlo
    if Prueba2.P2PNetwork.username_exists?(new_username) do
      IO.puts(@error_color <> "Ignorando notificación: nombre '#{new_username}' ya existe en la red" <> @reset)
    else
      IO.puts(@notification_color <> "#{notifier_username} notifica sobre nuevo peer: #{new_username} (#{new_address})" <> @reset)
      Prueba2.P2PNetwork.add_peer(new_address, new_username)
    end

    send_resp(conn, 200, "OK")
  end

  post "/api/peer-exit" do
    %{"peer" => exiting_peer, "username" => exiting_username} = conn.body_params
    IO.puts(@notification_color <> "#{exiting_username} (#{exiting_peer}) ha salido de la red" <> @reset)
    Prueba2.P2PNetwork.remove_peer(exiting_peer)
    send_resp(conn, 200, Jason.encode!(%{status: "ok"}))
  end

  match _ do
    send_resp(conn, 404, "Ruta no encontrada")
  end
end
