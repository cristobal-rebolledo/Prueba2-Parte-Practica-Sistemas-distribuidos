defmodule Prueba2.UserInterface.Display do
  @moduledoc """
  Funciones de presentación para la interfaz de usuario del sistema P2P de dados.
  """
  import IO.ANSI
  alias Prueba2.UserInterface.Helpers

  @title_color bright() <> blue()
  @info_color green()
  @error_color bright() <> red()
  @highlight_color yellow()
  @input_color bright() <> cyan()
  @dice_color magenta()
  @peer_color bright() <> white()
  @team_color cyan()
  @reset reset()

  def show_peers(peers) do
    peer_count = Helpers.safe_size(peers)
    IO.puts("\n" <> @title_color <> "=== Peers conectados (#{peer_count}) ===" <> @reset)
    if peer_count == 0 do
      IO.puts(@info_color <> "No hay peers conectados todavía." <> @reset)
    else
      Enum.each(peers, fn {address, username} ->
        IO.puts(@peer_color <> "- #{username}" <> @reset <> @info_color <> " en " <> @highlight_color <> address <> @reset)
      end)
    end
  end
  def show_team_controller_peers(peers) do
    peer_count = Helpers.safe_size(peers)
    IO.puts("\n" <> @title_color <> "=== Lista detallada de Peers (#{peer_count}) ===" <> @reset)

    # Obtener información del peer local para marcar
    local_address = Application.get_env(:prueba2, :address)

    if peer_count == 0 do
      IO.puts(@info_color <> "No hay peers registrados en el TeamController." <> @reset)
    else
      IO.puts(@peer_color <> "Dirección" <> @reset <> " | " <>
              @peer_color <> "Usuario" <> @reset <> " | " <>
              @peer_color <> "Equipo" <> @reset)
      IO.puts(String.duplicate("-", 60))
      Enum.each(peers, fn {address, username, team} ->
        team_str = if team == :NA, do: "No asignado", else: to_string(team)
        # Marcar al peer local con [TÚ]
        local_mark = if address == local_address, do: bright() <> " [TÚ] " <> reset(), else: ""
        IO.puts(@highlight_color <> "#{address}#{local_mark}" <> @reset <> " | " <>
                @info_color <> "#{username}" <> @reset <> " | " <>
                @team_color <> "#{team_str}" <> @reset)
      end)
    end
  end


  def show_team_controller_my_team(teams) do
    team_count = Prueba2.UserInterface.Helpers.safe_size(teams)

    # Obtener información del equipo local
    local_username = Application.get_env(:prueba2, :username)
    local_address = Application.get_env(:prueba2, :address)

    # Buscar el nombre del equipo del primer elemento (todos deben ser del mismo equipo)
    team_name = case teams do
      [{_, _, equipo} | _] -> equipo
      _ -> :NA
    end

    team_name_str = if team_name == :NA, do: "No asignado", else: to_string(team_name)

    IO.puts("\n" <> @title_color <> "=== Lista de Peers de Mi Equipo: #{team_name_str} (#{team_count}) ===" <> @reset)

    if team_count == 0 do
      IO.puts(@info_color <> "No hay otros peers en tu equipo." <> @reset)
    else
      IO.puts(@team_color <> "Dirección" <> @reset <> " | " <>
              @team_color <> "Número Secreto (ID)" <> @reset <> " | " <>
              @team_color <> "Equipo" <> @reset)
      IO.puts(String.duplicate("-", 70))

      Enum.each(teams, fn
        {address, secret_number, equipo} ->
          # Marcar al peer local con [TÚ]
          local_mark = if address == local_address, do: bright() <> " [TÚ] " <> reset(), else: ""
          equipo_str = if equipo == :NA, do: "No asignado", else: to_string(equipo)

          IO.puts(@highlight_color <> "#{address}#{local_mark}" <> @reset <> " | " <>
                  @info_color <> "#{secret_number}" <> @reset <> " | " <>
                  @team_color <> "#{equipo_str}" <> @reset)
        {address, secret_number} ->
          # Marcar al peer local con [TÚ]
          local_mark = if address == local_address, do: bright() <> " [TÚ] " <> reset(), else: ""

          IO.puts(@highlight_color <> "#{address}#{local_mark}" <> @reset <> " | " <>
                  @info_color <> "#{secret_number}" <> @reset <> " | " <>
                  @team_color <> "No asignado" <> @reset)
      end)
    end
  end
end
