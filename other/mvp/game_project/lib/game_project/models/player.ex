defmodule GameProject.Models.Player do
  @moduledoc """
  Estructura que define a un jugador y sus propiedades.
  """

  @derive {Jason.Encoder, only: [:address, :alias, :team]}
  defstruct [
    # Dirección IP y puerto del jugador (ej: "192.168.1.1:4000")
    address: nil,
    # Alias o nombre de usuario
    alias: nil,
    # Equipo al que pertenece o nil si no tiene equipo
    team: nil,
    # Número secreto generado automáticamente
    secret_number: nil
  ]

  @doc """
  Crea una nueva estructura de jugador.
  """
  def new(address, player_alias, team \\ nil) do
    %__MODULE__{
      address: address,
      alias: player_alias,
      team: team,
      secret_number: generate_secret_number()
    }
  end

  @doc """
  Genera un número secreto aleatorio para el jugador.
  """
  def generate_secret_number do
    :rand.uniform(10_000)
  end

  @doc """
  Actualiza el equipo de un jugador.
  """
  def update_team(player, team) do
    %__MODULE__{player | team: team}
  end
  @doc """
  Retorna una versión del jugador sin el número secreto para compartir con otros jugadores.
  """
  def without_secret(player) do
    %__MODULE__{player | secret_number: nil}
  end

  @doc """
  Convierte un mapa (generalmente proveniente de JSON) en una estructura de jugador.
  """
  def from_map(player_map) when is_map(player_map) do
    # Convert string keys to atoms if necessary
    map_with_atom_keys = if is_binary(Map.keys(player_map) |> List.first) do
      for {key, val} <- player_map, into: %{} do
        {String.to_atom(key), val}
      end
    else
      player_map
    end

    # Create a new Player struct with the data from the map
    %__MODULE__{
      address: map_with_atom_keys[:address],
      alias: map_with_atom_keys[:alias],
      team: map_with_atom_keys[:team],
      # We don't receive the secret_number from the network for security reasons
      # so we generate a new one
      secret_number: generate_secret_number()
    }
  end
end
