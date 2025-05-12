defmodule GameProject.NetworkTest do
  use ExUnit.Case
  import Mock
  alias GameProject.Network

  describe "Network functions" do
    test "get_local_ip returns a valid IP address" do
      ip = Network.get_local_ip()
      assert is_binary(ip)

      # Verificar formato básico de dirección IPv4
      assert String.match?(ip, ~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)
    end

    # Esta prueba requiere conexión a Internet, se puede omitir en CI/CD
    @tag :external
    test "get_public_ip returns a value when internet is available" do
      ip = Network.get_public_ip()

      # Puede ser nil si no hay conexión a Internet
      if ip != nil do
        assert is_binary(ip)
        assert String.match?(ip, ~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)
      end
    end

    test "http_get handles responses" do
      # Mock para pruebas - esto no realiza realmente una solicitud HTTP
      result = {:ok, %HTTPoison.Response{status_code: 200, body: "success"}}

      with_mock HTTPoison, [get: fn(_url, _headers, _options) -> result end] do
        assert {:ok, _} = Network.http_get("http://example.com")
      end
    end

    test "check_node_status returns boolean" do
      # Mock con nodo activo
      with_mock HTTPoison, [get: fn(_url, _headers, _options) ->
        {:ok, %HTTPoison.Response{status_code: 200}}
      end] do
        assert Network.check_node_status("192.168.1.1:4000") == true
      end

      # Mock con nodo inactivo
      with_mock HTTPoison, [get: fn(_url, _headers, _options) ->
        {:error, %HTTPoison.Error{reason: :timeout}}
      end] do
        assert Network.check_node_status("192.168.1.1:4001") == false
      end
    end
  end
end
