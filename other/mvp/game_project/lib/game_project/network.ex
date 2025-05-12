defmodule GameProject.Network do
  @moduledoc """
  Módulo para gestionar operaciones de red como obtener IPs y comunicarse con otros nodos.
  """

  @doc """
  Obtiene la dirección IP local del sistema.
  """
  def get_local_ip do
    {:ok, addrs} = :inet.getifaddrs()

    # Filtrar para encontrar la interfaz con una dirección IPv4 no local
    result = Enum.find_value(addrs, fn {interface, data} ->
      addr = Keyword.get(data, :addr)

      cond do
        # Asegurarse que es IPv4 y no es loopback
        tuple_size(addr) == 4 && addr != {127, 0, 0, 1} ->
          ip = addr |> Tuple.to_list() |> Enum.join(".")
          {interface, ip}
        true ->
          nil
      end
    end)

    case result do
      {_interface, ip} -> ip
      nil -> "127.0.0.1"  # Fallback a localhost si no se encuentra otra IP
    end
  end

  @doc """
  Obtiene la dirección IP pública usando el servicio api.ipify.org
  """
  def get_public_ip do
    :inets.start()

    case :httpc.request('http://api.ipify.org') do
      {:ok, {_, _, inet_addr}} ->
        :inets.stop()
        List.to_string(inet_addr)

      _ ->
        :inets.stop()
        # Si falla, devolver nil
        nil
    end
  end

  @doc """
  Realiza una solicitud HTTP GET a la dirección especificada.
  """
  def http_get(url, headers \\ [], options \\ []) do
    HTTPoison.get(url, headers, options)
  end

  @doc """
  Realiza una solicitud HTTP POST a la dirección especificada.
  """
  def http_post(url, body, headers \\ [], options \\ []) do
    HTTPoison.post(url, body, headers, options)
  end

  @doc """
  Comprueba si un nodo está activo haciendo una solicitud HTTP a su endpoint de status.
  """
  def check_node_status(address) do
    url = "http://#{address}/status"

    case HTTPoison.get(url, [], [timeout: 5000, recv_timeout: 5000]) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        true
      _ ->
        false
    end
  end
end
