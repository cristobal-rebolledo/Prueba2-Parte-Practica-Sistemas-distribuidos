defmodule Prueba2.IpDetector do
  @moduledoc """
  Módulo especializado en la detección de direcciones IP, tanto locales como públicas.
  Proporciona funciones para obtener la IP local y la IP pública.
  """

  require Logger
  import IO.ANSI

  # Colores para mensajes
  @info_color green()
  @error_color bright() <> red()
  @reset reset()

  # Lista de servicios para consultar IP pública
  @ip_services [
    ~c'http://api.ipify.org',
    ~c'http://ifconfig.me',
    ~c'http://ipinfo.io/ip',
    ~c'http://icanhazip.com',
    ~c'http://checkip.amazonaws.com'
  ]

  @doc """
  Obtiene la IP pública del host actual usando :httpc.
  Intenta con múltiples servicios de IP pública.
  """
  def get_public_ip do
    IO.puts(@info_color <> "Obteniendo IP pública..." <> @reset)

    # Asegurarnos que :inets está iniciado
    :inets.start()
    :ssl.start()

    # Intentar cada servicio hasta encontrar uno que funcione
    result = Enum.find_value(@ip_services, fn service ->
      IO.puts(@info_color <> "  Intentando con #{service}..." <> @reset)

      try do
        case :httpc.request(service) do
          {:ok, {{_, 200, _}, _, body}} ->
            ip = body |> List.to_string() |> String.trim()

            # Verificar que sea una IP válida
            if Regex.match?(~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/, ip) do
              IO.puts(@info_color <> "  ✓ IP encontrada: #{ip}" <> @reset)
              ip
            else
              IO.puts(@error_color <> "  ✗ Respuesta no válida: '#{ip}'" <> @reset)
              nil
            end

          {:ok, {{_, status, _}, _, _}} ->
            IO.puts(@error_color <> "  ✗ Error HTTP: #{status}" <> @reset)
            nil

          {:error, reason} ->
            IO.puts(@error_color <> "  ✗ Error: #{inspect(reason)}" <> @reset)
            nil
        end
      rescue
        e ->
          IO.puts(@error_color <> "  ✗ Excepción: #{inspect(e)}" <> @reset)
          nil
      end
    end)

    # Usar IP local si todos los servicios fallan
    result || get_best_local_ip() || "127.0.0.1"
  end

  @doc """
  Obtiene la IP local real (no 127.0.0.1) si está disponible.
  """
  def get_real_local_ip do
    case :inet.getifaddrs() do
      {:ok, addrs} ->
        Enum.find_value(addrs, "127.0.0.1", fn {_, opts} ->
          addr = Keyword.get(opts, :addr)
          flags = Keyword.get(opts, :flags, [])
          if is_tuple(addr) and tuple_size(addr) == 4 and
             :loopback not in flags and :up in flags and
             addr != {127, 0, 0, 1},
             do: Tuple.to_list(addr) |> Enum.join("."), else: nil
        end)
      _ -> "127.0.0.1"
    end
  end

  # Encuentra la mejor IP local que podría ser utilizada como pública
  defp get_best_local_ip do
    case :inet.getifaddrs() do
      {:ok, addrs} ->
        Enum.find_value(addrs, nil, fn {_, opts} ->
          addr = Keyword.get(opts, :addr)
          flags = Keyword.get(opts, :flags, [])
          if is_tuple(addr) and tuple_size(addr) == 4 and
             :loopback not in flags and :up in flags and
             Enum.at(Tuple.to_list(addr), 0) not in [127, 10, 172, 192],
             do: Tuple.to_list(addr) |> Enum.join("."), else: nil
        end)
      _ -> nil
    end
  end
end
