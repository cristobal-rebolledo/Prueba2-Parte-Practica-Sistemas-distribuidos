defmodule GameProject.HTTPServer do
  @moduledoc """
  Servidor HTTP para manejar las solicitudes de red.
  """

  use Plug.Router
  alias GameProject.Models.Player
  alias GameProject.PlayerRegistry
  alias GameProject.GameServer
  alias GameProject.GRPCLogger
  alias GameProject.Network
  alias GameProject.MessageHandler

  # Helper function for debugging types
  defp typeof(x) do
    cond do
      is_binary(x) -> "String"
      is_atom(x) -> "Atom"
      true -> "Other: #{inspect(x)}"
    end
  end

  plug Plug.Logger
  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason

  plug :match
  plug :dispatch

  # Endpoint para verificar el estado del servidor
  get "/status" do
    send_resp(conn, 200, "Server is running")
  end

  # Endpoint para recibir solicitudes de unión a la red
  post "/join" do
    # Validar la autenticación con la clave de acceso
    # El cuerpo debe incluir: address, alias, secret_number, access_key
    case conn.body_params do
      %{"address" => address, "alias" => player_alias, "secret_number" => secret_number, "access_key" => access_key} ->
        # 1. Autenticar primero
        if authenticate(access_key) do          # 2. Verificar si hay un juego activo en este nodo
          case GameServer.get_game_state() do
            {:ok, game_state} when game_state != nil ->
              # 3. Crear un nuevo jugador para el solicitante, pero NO lo añadimos aún al registro
              # El jugador se añadirá cuando nos llegue el mensaje via "distribuye"
              new_player_joining = Player.new(address, player_alias, nil)
              # Asignar el número secreto proporcionado en lugar del generado automáticamente
              new_player_joining = %{new_player_joining | secret_number: secret_number}

              # Log local de unión a la red
              GRPCLogger.log_event(%{
                timestamp: System.system_time(:second),
                id_instancia: game_state.instance_id,
                marcador: "INICIO",
                ip: address,
                alias: player_alias,
                accion: "join_network_request_received",
                args: Jason.encode!(%{server_ip: Network.get_local_ip()})
              })

              # 4. Obtener la lista de jugadores conocidos (el nuevo jugador NO está incluido aún)
              all_players_known_by_this_node = PlayerRegistry.get_players()

              # OPTIMIZACIÓN: Usar SOLO el protocolo "distribuye" para anunciar al nuevo jugador
              # en lugar de enviar notificaciones directas a cada nodo.
              IO.puts("\n#{IO.ANSI.bright()}Anunciando nuevo jugador #{player_alias} usando protocolo distribuye#{IO.ANSI.reset()}")

              # Usar SOLO el protocolo distribuye para la notificación
              new_player_announcement_payload = %{
                type: :new_player_joined,
                player_data: %{
                  address: new_player_joining.address,
                  alias: new_player_joining.alias,
                  team: new_player_joining.team
                },
                # Flag para indicar que este es un mensaje de unión a la red
                # que debe ser procesado de forma especial por el protocolo distribuye
                join_network: true,
                # Añadir el secret_number para poder recuperarlo al procesar el mensaje
                secret_number: secret_number
              }

              # Distribuir el mensaje siguiendo el protocolo "distribuye"
              GameProject.MessageDistribution.distribute_message(
                new_player_announcement_payload,
                all_players_known_by_this_node
              )

              # Preparar la respuesta para el jugador que se une
              players_for_join_response =
                all_players_known_by_this_node
                |> Enum.map(&Player.without_secret/1)

              response_to_joining_player = %{
                status: "ok",
                message: "Successfully joined the network",
                players: players_for_join_response,
                instance_id: game_state.instance_id,
                game_config: %{
                  available_teams: game_state.available_teams,
                  max_score: game_state.max_score,
                  max_players_per_team: game_state.max_players_per_team,
                  status: game_state.status
                }
              }

              conn
              |> put_resp_content_type("application/json")
              |> send_resp(200, Jason.encode!(response_to_joining_player))
            {:error, :no_game_state} -> # GameServer.get_game_state() devolvió :no_game_state
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(400, Jason.encode!(%{
                status: "error",
                message: "No active network on this node. Please try another server."
              }))
            other_game_state_error -> # Otro error de GameServer.get_game_state()
              GRPCLogger.log_event(%{
                timestamp: System.system_time(:second),
                id_instancia: 0, marcador: "ERROR", ip: Network.get_local_ip(), alias: "system",
                accion: "join_network_get_state_fail",
                args: Jason.encode!(%{error: inspect(other_game_state_error)})
              })
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(500, Jason.encode!(%{status: "error", message: "Error fetching game state on this node."}))
          end
        else
          # Falló la autenticación (authenticate devolvió false)
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(401, Jason.encode!(%{status: "error", message: "Invalid access key"}))
        end
      _ -> # El cuerpo de la solicitud no coincide con el patrón esperado (parámetros incompletos)
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{status: "error", message: "Missing or invalid required fields for joining."}))
    end
  end  # Endpoint para recibir solicitudes para unirse a un equipo
  post "/join_team" do
    with %{"player_alias" => player_alias,
          "team" => team} <- conn.body_params,
          {:ok, player} <- PlayerRegistry.get_player(player_alias) do

      # Verificar si el jugador ya está en otro equipo
      if player.team != nil do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{status: "error", message: "Player already belongs to a team"}))
      else
        # Verificar si es un equipo disponible
        {:ok, game_state} = GameServer.get_game_state()

        if team in game_state.available_teams do
          # Iniciar el proceso de unión al equipo con votación
          case join_team_process(player, team) do
            {:ok, updated_player} ->
              # Registrar en el log
              GRPCLogger.log_event(%{
                timestamp: System.system_time(:second),
                id_instancia: game_state.instance_id,
                marcador: "INICIO",
                ip: updated_player.address,
                alias: player_alias,
                accion: "join_team",
                args: Jason.encode!(%{
                  team: team
                })
              })

              conn
              |> put_resp_content_type("application/json")
              |> send_resp(200, Jason.encode!(%{status: "ok", message: "Successfully joined the team"}))
            {:error, error_data} when is_map(error_data) ->
              # Manejar el caso donde error_data es un mapa (formato nuevo)
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(403, Jason.encode!(%{
                status: "error",
                message: error_data.message,
                positive_votes: Map.get(error_data, :positive_votes, 0),
                total_votes: Map.get(error_data, :total_votes, 0)
              }))
            {:error, reason} ->
              # Manejar el caso donde reason es una cadena (formato antiguo)
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(403, Jason.encode!(%{
                status: "error",
                message: reason,
                positive_votes: 0,
                total_votes: 0
              }))
          end
        else
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(400, Jason.encode!(%{status: "error", message: "Invalid team"}))
        end
      end
    else
      {:error, _} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{status: "error", message: "Player not found"}))

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{status: "error", message: "Missing required fields"}))
    end
  end
  # Endpoint para recibir solicitud de aprobación para unirse a un equipo
  post "/approve_join" do
    with %{"player_alias" => player_alias,
          "team" => team,
          "requester" => requester_alias} <- conn.body_params,
          {:ok, player} <- PlayerRegistry.get_player(player_alias),
          {:ok, _requester} <- PlayerRegistry.get_player(requester_alias) do
      normalized_team = if is_binary(team), do: String.to_atom(team), else: team
      if player.team == normalized_team do
        # Preguntar en el terminal con timeout de 10 segundos
        question = "¿Permitir que '#{requester_alias}' se una al equipo '#{team}'? (s/n) [10s]: "
        IO.puts("")
        IO.puts(IO.ANSI.bright() <> IO.ANSI.yellow() <> "\n============================\nSOLICITUD DE UNIÓN AL EQUIPO\n============================" <> IO.ANSI.reset())
        IO.puts("Solicitante: #{requester_alias}")
        IO.puts("Equipo: #{team}")
        IO.puts("Tu alias: #{player_alias}")
        IO.write(question)
        answer =
          Task.async(fn -> IO.gets("") end)
          |> Task.yield(10_000)
          |> case do
            {:ok, resp} when is_binary(resp) -> String.trim(resp)
            _ -> ""
          end
        approve = String.downcase(answer) in ["s", "si", "y", "yes"]
        IO.puts(IO.ANSI.cyan() <> "Respuesta: " <> (if approve, do: "APROBADO", else: "RECHAZADO") <> IO.ANSI.reset())
        response = if approve do
          %{status: "ok", approved: true, secret_number: player.secret_number}
        else
          %{status: "ok", approved: false, secret_number: -1}
        end
        {:ok, game_state} = GameServer.get_game_state()
        GRPCLogger.log_event(%{
          timestamp: System.system_time(:second),
          id_instancia: game_state.instance_id,
          marcador: "FIN",
          ip: player.address,
          alias: player_alias,
          accion: "process_join_request",
          args: Jason.encode!(%{
            result: (if approve, do: "approved", else: "rejected"),
            requester: requester_alias
          })
        })
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(response))
      else
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Jason.encode!(%{status: "error", message: "Player is not in the requested team"}))
      end
    else
      {:error, _} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{status: "error", message: "Player not found"}))
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{status: "error", message: "Missing required fields"}))
    end
  end
  # Endpoint para recibir solicitud de verificación de números secretos
  # Este endpoint implementa la parte del protocolo donde un miembro aleatorio del equipo
  # verifica la suma de los números secretos antes de permitir que un nuevo jugador se una
  post "/verify_join" do
    with %{"requester_alias" => requester_alias,
          "team" => team,
          "voter_addresses" => voter_addresses,
          "secret_sum" => secret_sum} <- conn.body_params,
          {:ok, requester} <- PlayerRegistry.get_player(requester_alias) do

      # Calcular la suma real de números secretos para logging
      real_sum = if voter_addresses == [] and secret_sum == 0 do
        0
      else
        team_votes = Enum.reduce(voter_addresses, [], fn address, acc ->
          case Enum.find(PlayerRegistry.get_players(), fn p -> p.address == address end) do
            nil -> acc
            player -> [player | acc]
          end
        end)
        Enum.reduce(team_votes, 0, fn player, acc ->
          acc + player.secret_number
        end)
      end

      # Verificar la suma de los números secretos
      # Si es una verificación para un equipo vacío (voter_addresses vacío y secret_sum 0), siempre aprobar
      verified = if voter_addresses == [] and secret_sum == 0 do
        true
      else
        # Primero obtener los jugadores correspondientes a las direcciones proporcionadas
        team_votes = Enum.reduce(voter_addresses, [], fn address, acc ->
          case Enum.find(PlayerRegistry.get_players(), fn p -> p.address == address end) do
            nil -> acc
            player -> [player | acc]
          end
        end)
        # Calcular la suma real de números secretos
        real_sum = Enum.reduce(team_votes, 0, fn player, acc ->
          acc + player.secret_number
        end)
        (secret_sum == real_sum) and
          length(team_votes) > 0 and
          (length(voter_addresses) >= max(1, div(length(PlayerRegistry.get_players_by_team(team)), 2)))
      end

      # Registrar en el log
      {:ok, game_state} = GameServer.get_game_state()
      GRPCLogger.log_event(%{
        timestamp: System.system_time(:second),
        id_instancia: game_state.instance_id,
        marcador: "VERIFICACIÓN",
        ip: Network.get_local_ip(),
        alias: "system",
        accion: "verify_team_join",
        args: Jason.encode!(%{
          requester: requester_alias,
          team: team,
          verified: verified,
          expected_sum: real_sum,
          received_sum: secret_sum
        })
      })

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{
        status: "ok",
        verified: verified,
        message: if(verified, do: "La suma coincide o es unión a equipo vacío", else: "La suma no coincide")
      }))
    else
      {:error, _} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{status: "error", message: "Requester not found"}))

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{status: "error", message: "Missing required fields for verification"}))
    end
  end

  # Endpoint para recibir mensajes distribuidos
  post "/message" do
    with %{"message" => message_content_from_json,
          "from" => from_address,
          "timestamp" => _timestamp_str} <- conn.body_params do

      # Step 1: Convert top-level keys of the message content to atoms.
      message_with_top_level_atom_keys =
        if is_map(message_content_from_json) do
          Enum.into(message_content_from_json, %{}, fn
            {k, v} when is_binary(k) -> {String.to_atom(k), v}
            pair -> pair
          end)
        else
          message_content_from_json
        end

      # Step 2: If there is a player_data field, convert those keys to atoms too
      message_after_player_data_processing =
        if is_map(message_with_top_level_atom_keys) && is_map_key(message_with_top_level_atom_keys, :player_data) && is_map(message_with_top_level_atom_keys.player_data) do
          player_data = message_with_top_level_atom_keys.player_data
          atomized_player_data = Enum.into(player_data, %{}, fn
            {k, v} when is_binary(k) -> {String.to_atom(k), v}
            pair -> pair
          end)
          Map.put(message_with_top_level_atom_keys, :player_data, atomized_player_data)
        else
          message_with_top_level_atom_keys
        end

      # Step 3: Check if type is a string and convert to atom
      final_message_for_handler =
        if is_map(message_after_player_data_processing) &&
           is_map_key(message_after_player_data_processing, :type) &&
           is_binary(message_after_player_data_processing.type) do
          Map.update!(message_after_player_data_processing, :type, &String.to_atom/1)
        else
          message_after_player_data_processing
        end

      # Step 4: Debug information
      IO.puts("\n#{IO.ANSI.yellow()}Recibido en /message: #{inspect(final_message_for_handler)}#{IO.ANSI.reset()}")      # Step 5: Check for special action field for distribution instructions
      if is_map_key(final_message_for_handler, :action) &&
         (final_message_for_handler.action == :distribute_to_team ||
          to_string(final_message_for_handler.action) == "distribute_to_team") do

        # This is a distribution instruction - we're a representative for our team
        team = final_message_for_handler.team
        original_message = final_message_for_handler.message

        # Normalizar el equipo a atom
        normalized_team = if is_binary(team), do: String.to_atom(team), else: team
        IO.puts("\n#{IO.ANSI.yellow()}Depuración de tipos: Equipo recibido: #{inspect(team)} (#{typeof(team)})#{IO.ANSI.reset()}")
        IO.puts("\n#{IO.ANSI.yellow()}Depuración de tipos: Equipo normalizado: #{inspect(normalized_team)} (#{typeof(normalized_team)})#{IO.ANSI.reset()}")

        IO.puts("\n#{IO.ANSI.green()}Recibida instrucción para distribuir mensaje al equipo #{inspect(normalized_team)}#{IO.ANSI.reset()}")

        # Debug para ver todos los jugadores y sus equipos
        all_players = PlayerRegistry.get_players()
        IO.puts("\n#{IO.ANSI.magenta()}Todos los jugadores: #{inspect(Enum.map(all_players, fn p -> "#{p.alias} (#{inspect(p.team)})" end))}#{IO.ANSI.reset()}")

        # Procesar el mensaje localmente PRIMERO para que cuando luego obtengamos
        # los miembros del equipo, el jugador actual ya aparezca como miembro del equipo
        # si la acción es unirse a un equipo
        IO.puts("#{IO.ANSI.green()}Procesando mensaje localmente primero:#{IO.ANSI.reset()}")
        # Convert any string keys to atoms in the original message
        atomized_message = if is_map(original_message) do
          Enum.reduce(original_message, %{}, fn
            {"type", "player_joined_team"}, acc -> Map.put(acc, :type, :player_joined_team)
            {"team", team}, acc when is_binary(team) ->
              # Convertir el nombre del equipo de string a atom
              Map.put(acc, :team, String.to_atom(team))
            {k, v}, acc when is_binary(k) -> Map.put(acc, String.to_atom(k), v)
            {k, v}, acc -> Map.put(acc, k, v)
          end)
        else
          original_message
        end

        # Process the message locally first
        MessageHandler.handle_message(atomized_message)

        # Asegurarnos de que el equipo del mensaje sea exactamente el mismo que se usará para obtener miembros
        consistency_check_team = case atomized_message do
          %{team: message_team} when not is_nil(message_team) -> message_team
          _ -> normalized_team  # Usar el normalizado si no hay equipo en el mensaje
        end

        # Vuelve a obtener la lista de miembros del equipo después de procesar el mensaje localmente
        # Usamos el equipo del mensaje si está disponible, o el equipo de la instrucción si no
        updated_team_members = PlayerRegistry.get_players_by_team(consistency_check_team)
        IO.puts("#{IO.ANSI.cyan()}Equipo #{inspect(consistency_check_team)} tiene #{length(updated_team_members)} miembros (actualizado)#{IO.ANSI.reset()}")

        # Then distribute to all members of our team
        IO.puts("#{IO.ANSI.cyan()}Distribuyendo a los miembros del equipo#{IO.ANSI.reset()}")
        GameProject.MessageDistribution.distribute_to_team(atomized_message, updated_team_members)

      else
        # Regular message processing - not a distribution instruction
        case final_message_for_handler do
          %{type: :score_update} ->
            # Actualizar la puntuación localmente
            GameServer.update_score(final_message_for_handler.team, final_message_for_handler.points)

          %{type: :player_disconnected} ->
            # Eliminar al jugador desconectado mediante el MessageHandler
            MessageHandler.handle_message(final_message_for_handler)

          %{type: :new_player_joined} ->
            # Procesar la unión de un nuevo jugador a la red
            IO.puts("\n#{IO.ANSI.green()}Procesando mensaje directo new_player_joined#{IO.ANSI.reset()}")
            IO.puts("#{IO.ANSI.blue()}Player data: #{inspect(final_message_for_handler.player_data)}#{IO.ANSI.reset()}")
            MessageHandler.handle_message(final_message_for_handler)

          %{type: :player_joined_team} ->
            # Normalizar el nombre del equipo si es necesario
            message_with_normalized_team = if is_map_key(final_message_for_handler, :team) and is_binary(final_message_for_handler.team) do
              # Si el equipo viene como string, convertirlo a atom
              Map.put(final_message_for_handler, :team, String.to_atom(final_message_for_handler.team))
            else
              final_message_for_handler
            end

            # Utilizar el MessageHandler para procesar el mensaje de unión a equipo con el equipo normalizado
            IO.puts("\n#{IO.ANSI.yellow()}Procesando unión a equipo con mensaje normalizado: #{inspect(message_with_normalized_team)}#{IO.ANSI.reset()}")
            MessageHandler.handle_message(message_with_normalized_team)

          %{type: :game_ended} ->
            # Marcar el juego como terminado
            GameServer.get_game_state()
            |> elem(1)
            |> Map.put(:status, :finished)
            |> then(&{:ok, &1})

          %{type: :roll_dice} ->
            # Registrar lanzamiento de dados
            GameServer.update_score(final_message_for_handler.team, final_message_for_handler.points)
            GameServer.register_turn(final_message_for_handler.team, final_message_for_handler.player_alias)

          _ ->
            # Tipo de mensaje desconocido
            IO.puts("\n#{IO.ANSI.red()}Mensaje desconocido: #{inspect(final_message_for_handler)}#{IO.ANSI.reset()}")
            :ok
        end
      end

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{status: "ok"}))
    else
      _unmatched_value ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{status: "error", message: "Invalid message format or missing fields in /message"}))
    end
  end

  # Endpoint para manejar lanzamiento de dados
  post "/roll_dice" do
    with %{"player_alias" => player_alias,
          "value" => roll_value} <- conn.body_params,
          {:ok, player} <- PlayerRegistry.get_player(player_alias),
          true <- player.team != nil do

      # Actualizar la puntuación del equipo
      GameServer.update_score(player.team, roll_value)

      # Registrar el turno
      GameServer.register_turn(player.team, player_alias)

      # Distribuir el mensaje a todos los jugadores
      GameProject.MessageDistribution.distribute_message(
        %{type: :roll_dice, player_alias: player_alias, team: player.team, points: roll_value},
        PlayerRegistry.get_players()
      )

      # Obtener el estado actualizado del juego
      {:ok, game_state} = GameServer.get_game_state()      # Verificar si el juego ha terminado
      if Enum.any?(game_state.team_scores, fn {_team, score} -> score >= game_state.max_score end) do
        # Encontrar el equipo ganador
        winner_team = Enum.max_by(game_state.team_scores, fn {_team, score} -> score end) |> elem(0)

        # Terminar el juego usando end_game que actualiza el estado a :finished
        {:ok, updated_game_state} = GameServer.end_game(winner_team)

        # Distribuir mensaje de fin de juego
        GameProject.MessageDistribution.distribute_message(
          %{type: :game_ended, winner_team: winner_team, scores: updated_game_state.team_scores},
          PlayerRegistry.get_players()
        )

        # Registrar en el log
        GRPCLogger.log_event(%{
          timestamp: System.system_time(:second),
          id_instancia: game_state.instance_id,
          marcador: "FIN",
          ip: player.address,
          alias: player_alias,
          accion: "game_ended",
          args: Jason.encode!(%{
            winner_team: winner_team,
            scores: updated_game_state.team_scores
          })
        })

        # Enviar respuesta
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "ok", game_ended: true, winner_team: winner_team}))
      else
        # Si el juego continúa, registrar en el log
        GRPCLogger.log_event(%{
          timestamp: System.system_time(:second),
          id_instancia: game_state.instance_id,
          marcador: "PUNTOS",
          ip: player.address,
          alias: player_alias,
          accion: "roll_dice",
          args: Jason.encode!(%{
            team: player.team,
            value: roll_value,
            new_score: game_state.team_scores[player.team]
          })
        })

        # Enviar respuesta
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "ok", game_ended: false}))
      end
    else
      {:error, _} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{status: "error", message: "Player not found"}))

      false ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Jason.encode!(%{status: "error", message: "Player must join a team first"}))

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{status: "error", message: "Missing required fields"}))
    end
  end

  # Endpoint para recibir el voto desde el formulario HTML
  post "/approve_join_vote" do
    with %{"vote_id" => vote_id,
          "player_alias" => player_alias,
          "team" => team,
          "requester" => requester_alias,
          "approved" => approved_str,
          "secret_number" => secret_number_str} <- conn.body_params,
          {:ok, player} <- PlayerRegistry.get_player(player_alias),
          {:ok, requester} <- PlayerRegistry.get_player(requester_alias) do

      # Convertir los valores de formulario a los tipos adecuados
      approved = approved_str == "true"
      secret_number = if approved, do: player.secret_number, else: -1

      # Normalizar el nombre del equipo
      normalized_team = if is_binary(team), do: String.to_atom(team), else: team

      # Registrar respuesta en log
      {:ok, game_state} = GameServer.get_game_state()
      GRPCLogger.log_event(%{
        timestamp: System.system_time(:second),
        id_instancia: game_state.instance_id,
        marcador: "FIN",
        ip: player.address,
        alias: player_alias,
        accion: "process_join_request",
        args: Jason.encode!(%{
          result: (if approved, do: "approved", else: "rejected"),
          requester: requester_alias,
          vote_id: vote_id
        })
      })

      # Mostrar en consola
      IO.puts("\n#{if approved, do: IO.ANSI.green(), else: IO.ANSI.red()}Voto recibido para #{requester_alias} -> #{team}: #{if approved, do: "APROBADO", else: "RECHAZADO"}#{IO.ANSI.reset()}")

      # Generar la página de resultado
      templates_dir = Path.join(__DIR__, "../templates")
      template_path = Path.join(templates_dir, "vote_result.html.eex")

      template_path = if !File.exists?(template_path) do
        priv_dir = :code.priv_dir(:game_project)
        if priv_dir == {:error, :bad_name}, do: priv_dir = "priv"
        Path.join([priv_dir, "templates", "vote_result.html.eex"])
      else
        template_path
      end

      # Leer el contenido del template
      {:ok, template} = File.read(template_path)

      # Compilar el template con los datos de resultado
      result_html = EEx.eval_string(template,
        status: (if approved, do: :approved, else: :rejected),
        requester_alias: requester_alias,
        team: team,
        positive_votes: (if approved, do: 1, else: 0),
        total_votes: 1
      )

      # Escribir el HTML de resultado a un archivo temporal
      result_file = Path.join(System.tmp_dir(), "vote_result_#{vote_id}.html")
      File.write!(result_file, result_html)

      # Devolver la respuesta HTTP con el resultado y redirección
      response_body = "<html><body><script>window.location.href='file:///" <> String.replace(result_file, "\\", "/") <> "';</script></body></html>"

      # Enviar la respuesta al proceso que gestiona la votación
      send_resp_to_voting_process(vote_id, %{approved: approved, secret_number: secret_number})

      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, response_body)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{status: "error", message: "Missing required fields"}))
    end
  end

  # Función para enviar respuesta al proceso de votación
  defp send_resp_to_voting_process(_vote_id, _response) do
    # Esta función sería implementada para comunicar con el proceso de votación
    # Por ahora es un placeholder, ya que necesitaríamos establecer un canal de comunicación
    :ok
  end

  # Autenticar con la clave de acceso
  defp authenticate(access_key) do
    # Para el MVP, siempre autenticamos correctamente
    true
  end

  # Proceso de unión a un equipo
  defp join_team_process(player, team) do
    # Asegurar que team sea un atom
    normalized_team = if is_binary(team), do: String.to_atom(team), else: team

    # Obtener miembros actuales del equipo
    team_members = PlayerRegistry.get_players_by_team(normalized_team)
    IO.puts("\n#{IO.ANSI.yellow()}Verificando unión al equipo #{inspect(normalized_team)}, miembros actuales: #{length(team_members)}#{IO.ANSI.reset()}")

    # Debug: mostrar quiénes son miembros del equipo
    if length(team_members) > 0 do
      IO.puts("\n#{IO.ANSI.yellow()}Miembros actuales: #{Enum.map(team_members, fn p -> p.alias end) |> Enum.join(", ")}#{IO.ANSI.reset()}")
    end

    if Enum.empty?(team_members) do
      # Caso especial: Equipo vacío
      handle_empty_team_join(player, normalized_team)
    else
      # Caso normal: Equipo con miembros
      handle_team_with_members_join(player, normalized_team, team_members)
    end
  end
  # Manejar unión a un equipo vacío
  defp handle_empty_team_join(player, team) do
    all_players = PlayerRegistry.get_players()

    # Obtener el ID de instancia para el log
    {:ok, game_state} = GameServer.get_game_state()
    instance_id = game_state.instance_id

    # Si solo hay un jugador (tú), unión directa sin verificación pero usando la terminal
    if length(all_players) == 1 do
      IO.puts("No hay otros jugadores para verificar. Unión directa al equipo.")

      # Usar la terminal de votación para mantener consistencia en la interfaz
      # y registro de acciones, aunque sea automáticamente aprobado
      IO.puts("\n#{IO.ANSI.bright()}Iniciando terminal de votación simulada...#{IO.ANSI.reset()}")
      result = GameProject.VotingTerminal.start_vote(player.alias, player.address, team, instance_id)

      case result do
        {:ok, _} ->
          # La votación fue exitosa y el jugador ya se actualizó por el VotingTerminal
          {:ok, updated_player} = PlayerRegistry.get_player(player.alias)
          {:ok, updated_player}

        {:error, error} ->
          # Esto no debería suceder, pero manejo por si acaso
          {:error, %{
            message: "Error inesperado al unirse a equipo vacío",
            status: error.status,
            positive_votes: 0,
            total_votes: 0
          }}
      end
    else
      # Para equipos vacíos con múltiples jugadores en la red, también usamos la terminal de votación
      # para manejar la verificación con un jugador aleatorio
      IO.puts("\n#{IO.ANSI.bright()}Iniciando proceso de votación para equipo vacío...#{IO.ANSI.reset()}")
      result = GameProject.VotingTerminal.start_vote(player.alias, player.address, team, instance_id)

      case result do
        {:ok, vote_result} ->
          # Votación exitosa
          IO.puts("#{IO.ANSI.green()}Verificación exitosa para equipo vacío#{IO.ANSI.reset()}")
          {:ok, updated_player} = PlayerRegistry.get_player(player.alias)
          {:ok, updated_player}

        {:error, error_result} ->
          # Error en la verificación
          error_message = "Verificación fallida para equipo vacío"
          IO.puts("#{IO.ANSI.red()}#{error_message}#{IO.ANSI.reset()}")
          {:error, %{
            message: error_message,
            positive_votes: Map.get(error_result, :positive_votes, 0),
            total_votes: Map.get(error_result, :total_votes, 0),
            status: error_result.status
          }}
      end
    end
  end  # Manejar unión a un equipo con miembros
  defp handle_team_with_members_join(player, team, team_members) do
    # Obtener el ID de instancia para el log
    {:ok, game_state} = GameServer.get_game_state()
    instance_id = game_state.instance_id

    # Utilizar la terminal de votación separada para gestionar el proceso
    IO.puts("\n#{IO.ANSI.bright()}Iniciando proceso de votación en terminal separada para #{player.alias}...#{IO.ANSI.reset()}")

    # Llamar al módulo VotingTerminal para iniciar el proceso de votación
    result = GameProject.VotingTerminal.start_vote(
      player.alias,
      player.address,
      team,
      instance_id
    )

    # Procesar el resultado de la votación
    case result do
      {:ok, vote_result} ->
        # La votación fue exitosa, el jugador ya fue actualizado por el VotingTerminal
        IO.puts("#{IO.ANSI.green()}Votación exitosa: #{vote_result.positive_votes}/#{vote_result.total_votes} votos positivos#{IO.ANSI.reset()}")

        # Obtener el jugador actualizado después de la votación
        {:ok, updated_player} = PlayerRegistry.get_player(player.alias)
        {:ok, updated_player}

      {:error, error_result} ->
        # La votación falló
        error_message = case error_result.status do
          :rejected -> "No se obtuvieron suficientes votos positivos"
          :timeout -> "Tiempo de votación agotado"
          _ -> "Error en el proceso de votación"
        end

        # Información adicional para el error
        positive_votes = Map.get(error_result, :positive_votes, 0)
        total_votes = Map.get(error_result, :total_votes, 0)

        IO.puts("#{IO.ANSI.red()}Votación fallida: #{positive_votes}/#{total_votes} votos positivos#{IO.ANSI.reset()}")
        {:error, %{
          message: error_message,
          positive_votes: positive_votes,
          total_votes: total_votes,
          status: error_result.status
        }}
    end
  end

  def start_link(port, opts \\ []) do
    opts = Keyword.put_new(opts, :port, port)
    Plug.Cowboy.http(__MODULE__, [], opts)
  end

  def stop() do
    Plug.Cowboy.shutdown(__MODULE__.HTTP)
  end

end
