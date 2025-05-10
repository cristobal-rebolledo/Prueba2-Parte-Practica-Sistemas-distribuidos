defmodule Prueba2.ApiRouter do
  use Plug.Router
  require Logger
  import IO.ANSI

  # Definir colores para diferentes tipos de mensajes
  @notification_color bright() <> cyan()
  @dice_color magenta()
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
    IO.puts(@notification_color <> "#{requester_username} (#{requester_address}) solicita unirse a la red" <> @reset)

    # Añadir el nuevo peer a nuestra lista
    Prueba2.P2PNetwork.add_peer(requester_address, requester_username)

    # Enviar nuestra lista de peers como respuesta junto con nuestro nombre de usuario
    peers = Prueba2.P2PNetwork.get_peers()
             |> Enum.reject(fn {addr, _} -> addr == requester_address end)
             |> Enum.map(fn {addr, name} -> %{address: addr, username: name} end)

    my_username = Application.get_env(:prueba2, :username)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{
      peers: peers,
      host_username: my_username
    }))
  end

  post "/api/new-peer" do
    %{"peer" => %{"address" => new_address, "username" => new_username}, "from_username" => notifier_username} = conn.body_params
    IO.puts(@notification_color <> "#{notifier_username} notifica sobre nuevo peer: #{new_username} (#{new_address})" <> @reset)
    Prueba2.P2PNetwork.add_peer(new_address, new_username)
    send_resp(conn, 200, "OK")
  end

  post "/api/peer-exit" do
    %{"peer" => exiting_peer, "username" => exiting_username} = conn.body_params
    IO.puts(@notification_color <> "#{exiting_username} (#{exiting_peer}) ha salido de la red" <> @reset)

    # Eliminar al peer que sale de nuestra tabla de ruta
    Prueba2.P2PNetwork.remove_peer(exiting_peer)

    # Enviamos una respuesta OK para confirmar que hemos procesado la solicitud
    # y eliminado al peer de nuestra tabla de ruta
    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(200, Jason.encode!(%{status: "ok", message: "Peer removido correctamente"}))
  end

  match _ do
    send_resp(conn, 404, "Ruta no encontrada")
  end
end
