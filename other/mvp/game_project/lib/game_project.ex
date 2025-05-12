defmodule GameProject do
  @moduledoc """
  GameProject es un juego distribuido en Elixir donde múltiples procesos independientes
  se comunican entre sí para formar una red de juego.
  """

  @doc """
  Inicia el cliente del juego con la interfaz de usuario.
  """
  def start do
    GameProject.UI.start()
  end

  @doc """
  Obtiene la IP local del nodo actual.
  """
  def get_local_ip do
    GameProject.Network.get_local_ip()
  end

  @doc """
  Obtiene la IP pública del nodo actual.
  """
  def get_public_ip do
    GameProject.Network.get_public_ip()
  end

  @doc """
  Lanza un dado de tipo especificado.

  ## Tipos de dados disponibles:
  - :d4 - 2 + valor aleatorio entre 1 y 4
  - :d6 - 1 + valor aleatorio entre 1 y 6
  - :d10 - valor aleatorio entre 1 y 10
  """
  def roll_dice(type) do
    case type do
      :d4 -> 2 + :rand.uniform(4)
      :d6 -> 1 + :rand.uniform(6)
      :d10 -> :rand.uniform(10)
      _ -> raise "Tipo de dado no válido: #{inspect(type)}"
    end
  end
end
