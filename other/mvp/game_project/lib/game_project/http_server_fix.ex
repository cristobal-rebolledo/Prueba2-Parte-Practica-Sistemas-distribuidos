defmodule GameProject.HTTPServerFix do
  @moduledoc """
  Implementación corregida del servidor HTTP para manejar las solicitudes de red,
  con especial foco en el correcto procesamiento del protocolo "distribuye".
  """

  use Plug.Router
  alias GameProject.Models.Player
  alias GameProject.PlayerRegistry
  alias GameProject.GameServer
  alias GameProject.GRPCLogger
  alias GameProject.Network
  alias GameProject.MessageHandlerFix, as: MessageHandler
  alias GameProject.MessageDistributionFix, as: MessageDistribution

  plug Plug.Logger
  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason

  plug :match
  plug :dispatch

  # Endpoint para recibir mensajes distribuidos
  post "/message" do
    with %{"message" => message_content,
          "from" => from_address,
          "timestamp" => _timestamp_str} <- conn.body_params do

      # Normalizar formato del mensaje para mayor consistencia
      normalized_message = normalize_message(message_content)

      # Debug: mostrar el mensaje recibido
      IO.puts("\n#{IO.ANSI.yellow()}Recibido en /message: #{inspect(normalized_message)}#{IO.ANSI.reset()}")

      # Determinar el tipo de mensaje y procesarlo adecuadamente
      case normalized_message do
        # CASO 1: Es una instrucción de distribución (para un representante)
        %{action: action, message: inner_message, team: team}
        when action == :distribute_to_team or action == "distribute_to_team" ->
          IO.puts("\n#{IO.ANSI.bright_cyan()}Recibida instrucción para distribuir mensaje al equipo #{inspect(team)}#{IO.ANSI.reset()}")

          # Obtener todos los miembros del equipo a los que distribuir
          team_members = PlayerRegistry.get_players_by_team(team)
          IO.puts("#{IO.ANSI.cyan()}Equipo #{inspect(team)} tiene #{length(team_members)} miembros#{IO.ANSI.reset()}")

          # CORRECCIÓN PROTOCOLO DISTRIBUYE:
          # El representante NO procesa el mensaje aquí, sólo lo distribuye
          # Se procesará cuando llegue a cada destinatario final
          normalized_inner_message = normalize_message(inner_message)
          MessageDistribution.distribute_to_team(normalized_inner_message, team_members)

        # CASO 2: Mensaje directo (ya sin cabecera de distribución)
        _ ->
          IO.puts("\n#{IO.ANSI.bright_green()}Procesando mensaje directo: #{inspect(normalized_message[:type])}#{IO.ANSI.reset()}")

          # Este es el caso de un mensaje final que debe ser procesado localmente
          MessageHandler.handle_message(normalized_message)
      end

      # Respuesta estándar para todos los casos
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

  # Normalizar el formato del mensaje para mayor consistencia
  defp normalize_message(message) when is_map(message) do
    # Step 1: Normalizar los keys de primer nivel
    message_with_atom_keys =
      Enum.reduce(message, %{}, fn
        {"action", "distribute_to_team"}, acc ->
          Map.put(acc, :action, :distribute_to_team)
        {"type", type_str}, acc when is_binary(type_str) ->
          type_atom = case type_str do
            "player_joined_team" -> :player_joined_team
            "player_disconnected" -> :player_disconnected
            "new_player_joined" -> :new_player_joined
            "score_update" -> :score_update
            "roll_dice" -> :roll_dice
            "game_ended" -> :game_ended
            _ -> String.to_atom(type_str)
          end
          Map.put(acc, :type, type_atom)
        {"team", team_str}, acc when is_binary(team_str) ->
          Map.put(acc, :team, String.to_atom(team_str))
        {"message", inner_message}, acc when is_map(inner_message) ->
          # Normalizar recursivamente cualquier mensaje anidado
          Map.put(acc, :message, normalize_message(inner_message))
        {"player_data", player_data}, acc when is_map(player_data) ->
          # Normalizar datos de jugador
          normalized_player_data =
            Enum.reduce(player_data, %{}, fn
              {k, v} when is_binary(k) -> Map.put(%{}, String.to_atom(k), v)
              pair -> Map.new([pair])
            end)
          Map.put(acc, :player_data, normalized_player_data)
        {k, v}, acc when is_binary(k) ->
          Map.put(acc, String.to_atom(k), v)
        {k, v}, acc ->
          Map.put(acc, k, v)
      end)

    # Step 2: Manejar casos especiales de conversión de tipos
    case message_with_atom_keys do
      %{distribute_protocol: true} = msg ->
        # Si tiene la cabecera de protocolo distribuye, garantizar que sea un átomo
        Map.put(msg, :distribute_protocol, true)
      msg -> msg
    end
  end

  defp normalize_message(message), do: message

  # Establece una ruta comodín para manejar peticiones a rutas no definidas
  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{status: "error", message: "Route not found"}))
  end
end
