defmodule Prueba2.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    Node.set_cookie(:mycookie)
    # Primero, conectarse a los otros nodos
    connect_other_nodes()

    # Arrancamos los GenServers
    children = [
      {Prueba2.TeamRegistry, []},
      {Prueba2.TeamJoinRequest, []}
    ]

    opts = [strategy: :one_for_one, name: Prueba2.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp connect_other_nodes do
    # Ajusta estos nombres según los que uses al levantar IEx
    other_nodes = [:"node1@cfreb", :"node2@cfreb"]

    Enum.each(other_nodes, fn node ->
      unless node == Node.self() do
        case Node.connect(node) do
          true -> IO.puts("Conectado a #{node}")
          false -> IO.puts("Error conectando a #{node}")
        end
      end
    end)
  end
end

defmodule Prueba2.TeamRegistry do
  @moduledoc """
  Lleva el registro de equipos y sus miembros con replicación distribuida.
  """
  use GenServer

  # API pública
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def create_team(name), do: GenServer.call(__MODULE__, {:create_team, name})
  def list_teams(), do: GenServer.call(__MODULE__, :list)
  def add_member(team_id, player_id), do: GenServer.call(__MODULE__, {:add_member, team_id, player_id})

  # Función para creación interna (llamada RPC)
  def internal_create_team(team_id, team_data), do:
    GenServer.call(__MODULE__, {:internal_create, team_id, team_data})

  # Callbacks
  def init(state), do: {:ok, state}

  def handle_call({:create_team, name}, _from, state) do
    team_id = UUID.uuid4()
    team_data = %{name: name, members: []}

    # Replicar en todos los nodos conectados
    Node.list()
    |> Enum.each(fn node ->
      :rpc.call(node, __MODULE__, :internal_create_team, [team_id, team_data])
    end)

    new_state = Map.put(state, team_id, team_data)
    {:reply, {:ok, team_id}, new_state}
  end

  def handle_call({:internal_create, team_id, team_data}, _from, state) do
    {:reply, :ok, Map.put(state, team_id, team_data)}
  end

  def handle_call({:add_member, team_id, player_id}, _from, state) do
    case Map.get(state, team_id) do
      nil ->
        {:reply, {:error, "Equipo no encontrado"}, state}

      team ->
        updated_members = [player_id | team.members || []]
        updated_team = %{team | members: updated_members}

        # Replicar en todos los nodos
        Node.list()
        |> Enum.each(fn node ->
          :rpc.call(node, __MODULE__, :internal_add_member, [team_id, player_id])
        end)

        new_state = Map.put(state, team_id, updated_team)
        {:reply, :ok, new_state}
    end
  end

  def handle_call(:list, _from, state) do
    {:reply, state, state}
  end
  def get_team_members(team_id) do
    GenServer.call(__MODULE__, {:get_members, team_id})
  end

  def handle_call({:get_members, team_id}, _from, state) do
    members = case Map.get(state, team_id) do
      nil -> []
      team -> team.members || []
    end
    {:reply, members, state}
  end

  # Función para añadir miembros internamente (llamada RPC)
  def internal_add_member(team_id, player_id), do:
    GenServer.call(__MODULE__, {:internal_add_member, team_id, player_id})

  def handle_call({:internal_add_member, team_id, player_id}, _from, state) do
    case Map.get(state, team_id) do
      nil -> {:reply, :ok, state}  # No hace nada si el equipo no existe

      team ->
        updated_members = [player_id | team.members || []]
        updated_team = %{team | members: updated_members}
        new_state = Map.put(state, team_id, updated_team)
        {:reply, :ok, new_state}
    end
  end
end

defmodule Prueba2.TeamJoinRequest do
  @moduledoc """
  Maneja solicitudes de unión y votaciones por consenso.
  """
  use GenServer

  # Estado: %{team_id => %{requests: %{player_id => [votes]}}}
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def request_join(team_id, player_id), do: GenServer.cast(__MODULE__, {:request, team_id, player_id})
  def vote(team_id, player_id, vote),     do: GenServer.cast(__MODULE__, {:vote, team_id, player_id, vote})

  def init(state), do: {:ok, state}

  def handle_cast({:request, team_id, player_id}, state) do
    # Inicializa la estructura si no existe
    state = Map.put_new(state, team_id, %{requests: %{}})

    state =
      update_in(state, [team_id, :requests], fn requests ->
        Map.put(requests || %{}, player_id, [])
      end)

    {:noreply, state}
  end

  def handle_cast({:vote, team_id, player_id, vote}, state) do
    # Obtener votos actuales de TODOS los nodos
    all_votes = get_combined_votes(team_id, player_id,state)

    # Añadir el nuevo voto
    updated_votes = [vote | all_votes]

    # Replicar el voto en todos los nodos
    replicate_vote(team_id, player_id, vote)

    # Tomar decisión con todos los votos
    if length(updated_votes) >= 2 do
      accepted = Enum.count(updated_votes, & &1) > length(updated_votes)/2

      if accepted do
        # Lógica para añadir miembro (solo una vez)
        unless player_already_added?(team_id, player_id) do
          Prueba2.TeamRegistry.add_member(team_id, player_id)
        end
      end

      show_result(team_id, player_id, accepted)
    end

    {:noreply, put_in(state, [team_id, :requests, player_id], updated_votes)}
  end

  defp get_combined_votes(team_id, player_id,state) do
    # Obtener votos locales
    local_votes = get_in(state, [team_id, :requests, player_id]) || []

    # Obtener votos remotos
    remote_votes = Node.list()
    |> Enum.flat_map(fn node ->
      :rpc.call(node, __MODULE__, :get_local_votes, [team_id, player_id])
    end)

    local_votes ++ remote_votes
  end

  def get_local_votes(team_id, player_id) do
    GenServer.call(__MODULE__, {:get_votes, team_id, player_id})
  end

  def handle_call({:get_votes, team_id, player_id}, _from, state) do
    votes = get_in(state, [team_id, :requests, player_id]) || []
    {:reply, votes, state}
  end

  defp replicate_vote(team_id, player_id, vote) do
    Node.list()
    |> Enum.each(fn node ->
      :rpc.call(node, __MODULE__, :internal_add_vote, [team_id, player_id, vote])
    end)
  end

  def internal_add_vote(team_id, player_id, vote) do
    GenServer.cast(__MODULE__, {:internal_vote, team_id, player_id, vote})
  end

  def handle_cast({:internal_vote, team_id, player_id, vote}, state) do
    current = get_in(state, [team_id, :requests, player_id]) || []
    {:noreply, put_in(state, [team_id, :requests, player_id], [vote | current])}
  end

  defp player_already_added?(team_id, player_id) do
    members = Prueba2.TeamRegistry.get_team_members(team_id)
    player_id in members
  end

  defp show_result(team_id, player_id, accepted) do
    message = "Votación #{team_id}: Jugador #{player_id} #{if accepted, do: "ACEPTADO", else: "RECHAZADO"}"
    IO.puts(message)
    Node.list() |> Enum.each(&:rpc.call(&1, IO, :puts, [message]))
  end
end

defmodule Prueba2.Dice do
  @moduledoc """
  Genera tiradas de dados.
  """
  def roll(:d6),  do: :rand.uniform(6)
  def roll(:d20), do: :rand.uniform(20)
  def roll({:custom, sides}) when is_integer(sides) and sides > 0, do: :rand.uniform(sides)
end
