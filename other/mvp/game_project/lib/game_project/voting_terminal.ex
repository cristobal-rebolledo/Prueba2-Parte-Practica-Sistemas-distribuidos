defmodule GameProject.VotingTerminal do
  @moduledoc """
  Módulo para manejar la terminal separada de votación para unirse a equipos.
  Esta terminal muestra solicitudes de unión y permite a los miembros del equipo votar.
  Utiliza HTTP para comunicarse con los miembros del equipo y recolectar votos reales.
  """

  alias GameProject.PlayerRegistry
  alias GameProject.GRPCLogger
  alias GameProject.MessageDistribution
  alias GameProject.Network

  @voting_timeout 30_000  # 30 segundos para votar

  # Estado del voto
  defmodule VoteState do
    defstruct [
      :requester_alias,
      :requester_address,
      :target_team,
      :timestamp,
      :votes,
      :team_members,
      :votes_needed,
      :status,  # :pending, :approved, :rejected, :timeout
      :instance_id
    ]
  end

  @doc """
  Inicia una nueva terminal para votar sobre una solicitud de unión a equipo.
  Devuelve el resultado de la votación.

  Esta función lanza un proceso separado que muestra una interfaz para votar.
  """
  def start_vote(requester_alias, requester_address, target_team, instance_id) do
    # Crear un nuevo proceso para manejar la votación y mostrar la interfaz
    vote_id = "vote_#{:erlang.unique_integer([:positive, :monotonic])}"

    task = Task.async(fn ->
      manage_voting_process(requester_alias, requester_address, target_team, instance_id, vote_id)
    end)

    # Esperar a que termine la votación con un timeout
    Task.yield(task, @voting_timeout) || Task.shutdown(task)
  end

  # Función privada para gestionar el proceso de votación
  defp manage_voting_process(requester_alias, requester_address, target_team, instance_id, _vote_id) do
    # Obtener los miembros actuales del equipo
    team_members = PlayerRegistry.get_players_by_team(target_team)

    # Crear terminal separada del proceso principal para la votación
    terminal_title = "Votación: #{requester_alias} solicita unirse a #{target_team}"

    # En sistemas basados en Unix se puede usar 'x-terminal-emulator' o similar
    # En Windows, cmd /c start cmd /k
    # Para el MVP, simulamos un terminal separado usando IO.puts con un formato especial
    show_voting_terminal(terminal_title, requester_alias, requester_address, target_team, team_members)

    # Calcular votos necesarios (mayoría simple)
    votes_needed = max(1, div(length(team_members), 2))

    # Inicializar el estado de la votación
    vote_state = %VoteState{
      requester_alias: requester_alias,
      requester_address: requester_address,
      target_team: target_team,
      timestamp: System.system_time(:second),
      votes: [],
      team_members: team_members,
      votes_needed: votes_needed,
      status: :pending,
      instance_id: instance_id
    }

    # Proceso de recolección de votos
    vote_result = collect_votes(vote_state, team_members)

    # Procesamiento del resultado
    process_vote_result(vote_result)
  end

  defp show_voting_terminal(title, requester_alias, requester_address, team, members) do
    # Generar contenido para la terminal
    vote_id = :rand.uniform(9999)
    terminal_content = """
    ======= #{title} =======
    ID de votación: #{vote_id}
    ----------------------------------------
    Solicitante: #{requester_alias} (#{requester_address})
    Equipo destino: #{team}
    Miembros actuales del equipo (#{length(members)}):
    #{Enum.map_join(members, "\n", fn m -> "  - #{m.alias} (#{m.address})" end)}
    ----------------------------------------
    VOTACIÓN EN CURSO...
    (Los miembros del equipo están votando)
    ----------------------------------------
    """

    # Guardar el contenido en un archivo temporal
    temp_file = Path.join(System.tmp_dir(), "vote_terminal_#{vote_id}.txt")
    File.write!(temp_file, terminal_content)    # Lanzar PowerShell en una ventana separada con el contenido - comando mejorado
    # Usamos el powershell.exe directo con -File para evitar problemas de comillas y escapes
    escaped_path = String.replace(temp_file, "\\", "\\\\")

    # Crear un script temporal de PowerShell que se ejecutará
    ps_script_file = Path.join(System.tmp_dir(), "vote_script_#{vote_id}.ps1")
    ps_script_content = """
    Get-Content '#{escaped_path}' | Out-Host
    Write-Host 'La ventana se cerrará automáticamente al finalizar la votación.' -ForegroundColor Yellow
    Start-Sleep -Seconds 60
    """
    File.write!(ps_script_file, ps_script_content)

    # Abrir la terminal en segundo plano ejecutando ese script
    System.cmd("powershell.exe", ["-NoExit", "-ExecutionPolicy", "Bypass", "-File", ps_script_file], stderr_to_stdout: true)

    # También mostramos en la consola actual para depuración
    IO.puts(IO.ANSI.clear())
    IO.puts(IO.ANSI.bright() <> "======= #{title} =======" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.green() <> "ID de votación: #{vote_id}" <> IO.ANSI.reset())
    IO.puts("----------------------------------------")
    IO.puts("Solicitante: #{requester_alias} (#{requester_address})")
    IO.puts("Equipo destino: #{team}")
    IO.puts("Miembros actuales del equipo (#{length(members)}):")

    Enum.each(members, fn member ->
      IO.puts("  - #{member.alias} (#{member.address})")
    end)

    IO.puts("----------------------------------------")
    IO.puts(IO.ANSI.yellow() <> "VOTACIÓN EN CURSO..." <> IO.ANSI.reset())
    IO.puts("(Los miembros del equipo están votando)")
    IO.puts("----------------------------------------")
  end

  defp collect_votes(vote_state, team_members) do
    IO.puts("Solicitando votos a #{length(team_members)} miembros del equipo...")
    local_ip = Network.get_local_ip()
    # Buscar el miembro local (el que tiene la IP local)
    {local_member, remote_members} = Enum.split_with(team_members, fn m -> m.address == local_ip end)

    # 1. Preguntar al usuario local directamente en el terminal (si es miembro del equipo)
    local_vote =
      case local_member do
        [member] ->
          question = "¿Permitir que '#{vote_state.requester_alias}' se una a tu equipo '#{vote_state.target_team}'? (s/n) [10s]: "
          IO.puts("")
          IO.puts(IO.ANSI.bright() <> IO.ANSI.yellow() <> "\n============================\nSOLICITUD DE UNIÓN AL EQUIPO\n============================" <> IO.ANSI.reset())
          IO.puts("Solicitante: #{vote_state.requester_alias}")
          IO.puts("Equipo: #{vote_state.target_team}")
          IO.puts("Tu alias: #{member.alias}")
          IO.write(question)
          answer =
            Task.async(fn -> IO.gets("") end)
            |> Task.yield(10_000)
            |> case do
              {:ok, resp} when is_binary(resp) -> String.trim(resp)
              _ -> ""
            end
          approved = String.downcase(answer) in ["s", "si", "y", "yes"]
          IO.puts(IO.ANSI.cyan() <> "Respuesta: " <> (if approved, do: "APROBADO", else: "RECHAZADO") <> IO.ANSI.reset())
          [%{
            member_alias: member.alias,
            approved: approved,
            secret_number: if(approved, do: member.secret_number, else: -1)
          }]
        _ -> []
      end

    # 2. Solicitar votos a los miembros remotos vía HTTP
    remote_votes = Task.async_stream(
      remote_members,
      fn member ->
        url = "http://#{member.address}/approve_join"
        body = Jason.encode!(%{
          player_alias: member.alias,
          team: vote_state.target_team,
          requester: vote_state.requester_alias
        })
        headers = [{"Content-Type", "application/json"}]
        IO.puts("Enviando solicitud de voto a #{member.alias} (#{member.address})...")
        result = try do
          case HTTPoison.post(url, body, headers, [timeout: 5000, recv_timeout: 5000]) do
            {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
              response = Jason.decode!(resp_body)
              approved = Map.get(response, "approved", false)
              secret_number = Map.get(response, "secret_number", -1)
              vote_text = if approved, do: "APRUEBA", else: "RECHAZA"
              IO.puts("#{IO.ANSI.green()}► #{member.alias} #{vote_text} la solicitud#{IO.ANSI.reset()}")
              {:ok, %{
                member_alias: member.alias,
                approved: approved,
                secret_number: secret_number
              }}
            {:ok, %HTTPoison.Response{status_code: code}} ->
              IO.puts("#{IO.ANSI.red()}✗ Error de #{member.alias}: Código de respuesta #{code}#{IO.ANSI.reset()}")
              {:error, "HTTP error code: #{code}"}
            {:error, %HTTPoison.Error{reason: reason}} ->
              IO.puts("#{IO.ANSI.red()}✗ Error de #{member.alias}: #{inspect(reason)}#{IO.ANSI.reset()}")
              {:error, reason}
          end
        catch
          _kind, reason ->
            IO.puts("#{IO.ANSI.red()}✗ Error inesperado al contactar a #{member.alias}: #{inspect(reason)}#{IO.ANSI.reset()}")
            {:error, "Unexpected error: #{inspect(reason)}"}
        end
        result
      end,
      timeout: 8000,
      on_timeout: :kill_task
    ) |> Enum.reduce([], fn
      {:ok, {:ok, vote}}, acc -> [vote | acc]
      {:ok, {:error, reason}}, acc ->
        IO.puts("#{IO.ANSI.yellow()}⚠ No se pudo obtener voto remoto: #{inspect(reason)}#{IO.ANSI.reset()}")
        acc
      {:exit, _reason}, acc ->
        IO.puts("#{IO.ANSI.yellow()}⚠ Timeout al esperar voto remoto#{IO.ANSI.reset()}")
        acc
    end)

    # 3. Unir todos los votos (local primero, luego remotos)
    votes = local_vote ++ Enum.reverse(remote_votes)

    # Guardar los votos recolectados
    positive_votes = Enum.filter(votes, fn vote -> vote.approved end)
    updated_state = %{vote_state |
      votes: votes,
      status: (if length(positive_votes) >= vote_state.votes_needed, do: :approved, else: :rejected)
    }

    # Mostrar resultado final en la terminal
    vote_id = :rand.uniform(9999)
    IO.puts("----------------------------------------")
    IO.puts("Resultado de la votación: #{length(positive_votes)}/#{length(team_members)} votos positivos")

    status_text_ansi = case updated_state.status do
      :approved -> IO.ANSI.green() <> "APROBADA" <> IO.ANSI.reset()
      :rejected -> IO.ANSI.red() <> "RECHAZADA" <> IO.ANSI.reset()
      :timeout -> IO.ANSI.yellow() <> "TIEMPO AGOTADO" <> IO.ANSI.reset()
    end

    status_text_plain = case updated_state.status do
      :approved -> "APROBADA"
      :rejected -> "RECHAZADA"
      :timeout -> "TIEMPO AGOTADO"
    end

    IO.puts("Estado final: #{status_text_ansi}")

    # Actualizar el archivo del terminal con los resultados
    result_content = """
    ========= RESULTADOS DE LA VOTACION =========
    Votos: #{length(positive_votes)}/#{length(team_members)} positivos
    Estado: #{status_text_plain}
    ----------------------------------------
    """

    # Guardar en archivo temporal para mostrar en el PowerShell
    temp_file = Path.join(System.tmp_dir(), "vote_result_#{vote_id}.txt")
    File.write!(temp_file, result_content)    # Actualiza la ventana PowerShell con los resultados - enfoque mejorado con script
    escaped_path = String.replace(temp_file, "\\", "\\\\")
    result_script_id = :rand.uniform(9999)
    ps_script_file = Path.join(System.tmp_dir(), "vote_result_script_#{result_script_id}.ps1")
    ps_script_content = """
    Get-Content '#{escaped_path}' | Out-Host
    Write-Host 'La ventana se cerrará en 30 segundos...' -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    """
    File.write!(ps_script_file, ps_script_content)

    # Ejecutar el script de PowerShell
    System.cmd("powershell.exe", ["-NoExit", "-ExecutionPolicy", "Bypass", "-File", ps_script_file], stderr_to_stdout: true)

    # Realizar verificación si la votación fue aprobada
    verified_state = if updated_state.status == :approved do
      IO.puts("----------------------------------------")
      IO.puts("Realizando verificación de números secretos...")

      # Seleccionar un miembro aleatorio para verificación
      verifier = Enum.random(team_members)
      IO.puts("Verificador seleccionado: #{verifier.alias}")

      # Calcular la suma de números secretos
      secret_sum = positive_votes
        |> Enum.map(fn vote -> vote.secret_number end)
        |> Enum.sum()

      # Preparar los datos para enviar al verificador
      positive_voter_addresses = positive_votes
        |> Enum.map(fn vote ->
          member = Enum.find(team_members, fn m -> m.alias == vote.member_alias end)
          member && member.address
        end)
        |> Enum.filter(&(&1))

      IO.puts("Suma de números secretos: #{secret_sum}")

      # Realizar la solicitud HTTP al verificador
      url = "http://#{verifier.address}/verify_join"
      body = Jason.encode!(%{
        requester_alias: vote_state.requester_alias,
        team: vote_state.target_team,
        voter_addresses: positive_voter_addresses,
        secret_sum: secret_sum
      })
      headers = [{"Content-Type", "application/json"}]

      IO.puts("Enviando solicitud de verificación a #{verifier.alias}...")

      _verification_result = try do
        case HTTPoison.post(url, body, headers, [timeout: 5000, recv_timeout: 5000]) do
          {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
            response = Jason.decode!(resp_body)
            verified = Map.get(response, "verified", false)

            if verified do
              IO.puts("#{IO.ANSI.green()}✓ Verificación exitosa!#{IO.ANSI.reset()}")
              updated_state
            else
              IO.puts("#{IO.ANSI.red()}✗ Verificación fallida: La suma no coincide#{IO.ANSI.reset()}")
              %{updated_state | status: :rejected}
            end

          {:ok, %HTTPoison.Response{}} ->
            IO.puts("#{IO.ANSI.red()}✗ Error en la verificación: Respuesta inválida#{IO.ANSI.reset()}")
            %{updated_state | status: :rejected}

          {:error, _} ->
            IO.puts("#{IO.ANSI.red()}✗ Error en la verificación: No se pudo contactar al verificador#{IO.ANSI.reset()}")
            %{updated_state | status: :rejected}
        end
      catch
        _, _ ->
          IO.puts("#{IO.ANSI.red()}✗ Error inesperado durante la verificación#{IO.ANSI.reset()}")
          %{updated_state | status: :rejected}
      end    else
      # Si no fue aprobada, mantener el estado actualizado
      updated_state
    end

    IO.puts("----------------------------------------")

    # Generar un ID único para este resultado
    result_id = "#{:erlang.unique_integer([:positive, :monotonic])}"

    # Crear contenido de resultado para la ventana PowerShell
    status_text = case verified_state.status do
      :approved -> "APROBADA"
      :rejected -> "RECHAZADA"
      :timeout -> "TIEMPO AGOTADO"
    end

    result_content = """
    =============================================
          RESULTADO FINAL DE LA VOTACIÓN
    =============================================
    Solicitante: #{verified_state.requester_alias}
    Equipo: #{verified_state.target_team}
    Estado: #{status_text}
    Votos positivos: #{length(Enum.filter(verified_state.votes, fn v -> v.approved end))}/#{length(verified_state.votes)}
    =============================================
    """

    # Guardar en archivo temporal para mostrar en el PowerShell
    temp_file = Path.join(System.tmp_dir(), "vote_final_#{result_id}.txt")
    File.write!(temp_file, result_content)    # Mostrar resultados finales en una nueva ventana PowerShell - enfoque mejorado con script
    escaped_path = String.replace(temp_file, "\\", "\\\\")
    final_script_id = :rand.uniform(9999)
    ps_script_file = Path.join(System.tmp_dir(), "vote_final_script_#{final_script_id}.ps1")
    ps_script_content = """
    Get-Content '#{escaped_path}' | Out-Host
    Write-Host 'La ventana se cerrará en 30 segundos...' -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    """
    File.write!(ps_script_file, ps_script_content)

    # Ejecutar el script de PowerShell
    System.cmd("powershell.exe", ["-NoExit", "-ExecutionPolicy", "Bypass", "-File", ps_script_file], stderr_to_stdout: true)

    IO.puts(IO.ANSI.bright() <> "La ventana de votación se cerrará en 3 segundos..." <> IO.ANSI.reset())
    :timer.sleep(3000)

    verified_state
  end

  defp process_vote_result(vote_state) do
    case vote_state.status do
      :approved ->
        # Preparar los datos para el mensaje de distribución
        positive_votes_data = vote_state.votes
          |> Enum.filter(fn vote -> vote.approved end)
          |> Enum.map(fn vote -> %{alias: vote.member_alias, secret_number: vote.secret_number} end)

        # Calcular la suma de números secretos
        secret_sum = positive_votes_data
          |> Enum.map(fn vote -> vote.secret_number end)
          |> Enum.sum()

        # Registrar en el log
        GRPCLogger.log_event(%{
          timestamp: System.system_time(:second),
          id_instancia: vote_state.instance_id,
          marcador: "FIN",
          ip: Network.get_local_ip(),
          alias: "system",
          accion: "team_join_vote",
          args: Jason.encode!(%{
            requester: vote_state.requester_alias,
            team: vote_state.target_team,
            approved: true,
            votes_count: length(positive_votes_data),
            total_votes: length(vote_state.votes)
          })
        })

        # Enviar mensaje distribuye para unir al jugador al equipo
        MessageDistribution.distribute_message(
          %{
            type: :player_joined_team,
            player_alias: vote_state.requester_alias,
            team: vote_state.target_team,
            timestamp: System.system_time(:millisecond),
            # Incluir información de los votos y verificación para fines informativos
            vote_info: %{
              positive_votes: length(positive_votes_data),
              total_votes: length(vote_state.votes),
              secret_sum: secret_sum
            }
          },
          PlayerRegistry.get_players()
        )

        # Devolver resultado exitoso
        {:ok, %{
          status: :approved,
          team: vote_state.target_team,
          positive_votes: length(positive_votes_data),
          total_votes: length(vote_state.votes),
          secret_sum: secret_sum
        }}

      :rejected ->
        # Registrar en el log
        GRPCLogger.log_event(%{
          timestamp: System.system_time(:second),
          id_instancia: vote_state.instance_id,
          marcador: "FIN",
          ip: Network.get_local_ip(),
          alias: "system",
          accion: "team_join_vote",
          args: Jason.encode!(%{
            requester: vote_state.requester_alias,
            team: vote_state.target_team,
            approved: false,
            votes_count: Enum.count(vote_state.votes, fn v -> v.approved end),
            total_votes: length(vote_state.votes)
          })
        })
          # Contar los votos positivos explícitamente para evitar errores de acceso
        positive_vote_count = Enum.count(vote_state.votes, fn v -> v.approved end)
        total_vote_count = length(vote_state.votes)

        {:error, %{
          status: :rejected,
          message: "No se obtuvo la cantidad requerida de votos positivos",
          positive_votes: positive_vote_count,
          total_votes: total_vote_count
        }}

      :timeout ->
        # Registrar en el log
        GRPCLogger.log_event(%{
          timestamp: System.system_time(:second),
          id_instancia: vote_state.instance_id,
          marcador: "ERROR",
          ip: Network.get_local_ip(),
          alias: "system",
          accion: "team_join_vote",
          args: Jason.encode!(%{
            requester: vote_state.requester_alias,
            team: vote_state.target_team,
            timeout: true
          })
        })
          # Agregamos información adicional para el caso de timeout
        positive_vote_count = vote_state.votes |> Enum.filter(fn v -> v.approved end) |> length()
        total_vote_count = length(vote_state.votes)

        {:error, %{
          status: :timeout,
          message: "Tiempo de votación agotado",
          positive_votes: positive_vote_count,
          total_votes: total_vote_count
        }}
    end
  end
end
