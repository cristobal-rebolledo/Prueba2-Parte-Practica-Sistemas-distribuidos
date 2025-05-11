defmodule Prueba2.UserInterface.Helpers do
  @moduledoc """
  Funciones auxiliares para la interfaz de usuario del sistema P2P de dados.
  """
  def safe_size(collection) when is_map(collection), do: map_size(collection)
  def safe_size(collection) when is_list(collection), do: length(collection)
  def safe_size(_), do: 0

  def find_user_team(teams, username) do
    Enum.find_value(teams, fn {team_name, team_data} ->
      if username in team_data.players, do: team_name, else: nil
    end)
  end
end
