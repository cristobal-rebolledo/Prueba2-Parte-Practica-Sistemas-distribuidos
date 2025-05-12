import threading, socket, json, time
import ast
import configparser
from .game_log_client import LogClient

# --- Leer configuración desde game.conf ---
def leer_configuracion(path='game.conf'):
    config = configparser.ConfigParser()
    # Permitir archivos sin sección agregando una sección por defecto
    with open(path, 'r') as f:
        content = f.read()
        if not content.strip().startswith('['):
            content = '[DEFAULT]\n' + content
    config.read_string(content)
    section = config['DEFAULT']
    # Leer TEAMS si está presente
    teams_str = section.get('TEAMS', fallback=None)
    if teams_str:
        teams = [t.strip() for t in teams_str.split(',') if t.strip()]
    else:
        teams = ["ROJO", "AZUL", "VERDE"]
    return {
        'MIN_DADO': section.getint('MIN_DADO', fallback=1),
        'MAX_DADO': section.getint('MAX_DADO', fallback=6),
        'PUNTAJE_MAXIMO': section.getint('PUNTAJE_MAXIMO', fallback=21),
        'TEAMS': teams
    }

_conf = leer_configuracion()
MIN_DADO = _conf['MIN_DADO']
MAX_DADO = _conf['MAX_DADO']
PUNTAJE_MAXIMO = _conf['PUNTAJE_MAXIMO']
TEAMS = _conf['TEAMS']

# --- Leer configuración desde api.conf ---
def leer_api_conf(path='api.conf'):
    config = configparser.ConfigParser()
    with open(path, 'r') as f:
        content = f.read()
        if not content.strip().startswith('['):
            content = '[DEFAULT]\n' + content
    config.read_string(content)
    section = config['DEFAULT']
    addr = section.get('ADDR', fallback='127.0.0.1')
    port = section.getint('PORT', fallback=50051)
    return addr, port

api_addr, api_port = leer_api_conf()

# --- Instancia global del logger gRPC ---
log_client = LogClient(server_addr=f'{api_addr}:{api_port}', id_instancia=None)

class MeshPeer:
    def __init__(self, alias, host, port, on_event):
        self.alias = alias
        self.host = host
        self.port = port
        self.on_event = on_event
        self.team = None
        self.peers = {}  # (host, port) -> alias
        self.teams = {}  # (host, port) -> team
        self.sockets = {}  # (host, port) -> socket
        self.id_instancia = None  # UUID de la partida actual
        self.server = threading.Thread(target=self.listen, daemon=True)
        self.server.start()

    def listen(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((self.host, self.port))
        s.listen(10)
        while True:
            conn, addr = s.accept()
            threading.Thread(target=self.handle_peer, args=(conn,), daemon=True).start()

    def handle_peer(self, conn):
        try:
            while True:
                data = conn.recv(4096)
                if not data:
                    break
                for line in data.split(b'\n'):
                    if line:
                        try:
                            msg = json.loads(line.decode())
                        except Exception as e:
                            print(f"[DEBUG] handle_peer: error decodificando: {e}")
                            continue
                        self.handle_message(msg, conn)
        except Exception as e:
            print(f"[DEBUG] handle_peer: excepción: {e}")
        finally:
            conn.close()

    def broadcast_peer_joined(self):
        msg = {
            'type': 'peer_joined',
            'peer': [self.host, self.port],
            'alias': self.alias,
            'team': self.team
        }
        self.broadcast(msg)

    def _tuple_key(self, k):
        """Convierte una clave string o tupla en tupla."""
        if isinstance(k, tuple):
            return k
        if isinstance(k, str):
            try:
                return tuple(ast.literal_eval(k))
            except Exception:
                return (k,)
        return (k,)

    def _str_key(self, t):
        """Convierte una tupla en string para usar como clave serializada."""
        if isinstance(t, tuple):
            return str(t)
        return str(tuple(t))

    def _remove_peer_from_game(self, peer):
        # Elimina un peer de todos los equipos, orden de turnos y marcador
        if hasattr(self, '_orden'):
            for team, jugadores in list(self._orden.items()):
                nuevos = [j for j in jugadores if j != peer]
                if len(nuevos) != len(jugadores):
                    self._orden[team] = nuevos
                    # Si el equipo queda vacío, eliminarlo de todas las estructuras
                    if not nuevos:
                        self._orden.pop(team)
                        if hasattr(self, '_marcador') and team in self._marcador:
                            self._marcador.pop(team)
                        if hasattr(self, '_turno_idx') and team in self._turno_idx:
                            self._turno_idx.pop(team)
                        if hasattr(self, '_turno_actual') and team in self._turno_actual:
                            self._turno_actual.pop(team)
            # Ajustar índices y turnos actuales si es necesario
            for team, jugadores in self._orden.items():
                if hasattr(self, '_turno_idx') and team in self._turno_idx:
                    idx = self._turno_idx[team]
                    if idx >= len(jugadores):
                        self._turno_idx[team] = 0
                if hasattr(self, '_turno_actual') and team in self._turno_actual:
                    idx = self._turno_idx[team] if team in self._turno_idx else 0
                    if jugadores:
                        self._turno_actual[team] = jugadores[idx]
        # Eliminar del equipo y marcador
        if hasattr(self, '_equipos') and peer in self._equipos:
            self._equipos.pop(peer)
        if hasattr(self, 'teams') and peer in self.teams:
            self.teams.pop(peer)
        if hasattr(self, 'peers') and peer in self.peers:
            self.peers.pop(peer)
        if hasattr(self, '_marcador'):
            for team, jugadores in list(self._orden.items()):
                if not jugadores and team in self._marcador:
                    self._marcador.pop(team)
        self.on_event('update_scores', dict(getattr(self, '_marcador', {})))

    def handle_message(self, msg, conn):
        print(f"[DEBUG] handle_message: type={msg.get('type')}, from={msg.get('from')}, msg={msg}")
        t = msg.get('type')
        if t == 'intro':
            peer = tuple(msg['me'])
            self.peers[peer] = msg['alias']
            self.sockets[peer] = conn
            teams_recv = msg.get('teams', {})
            for k, v in teams_recv.items():
                self.teams[self._tuple_key(k)] = v
            if (self.host, self.port) not in self.teams:
                self.teams[(self.host, self.port)] = None
            self.on_event('log', f"INTRO de {msg['alias']}@{peer[0]}:{peer[1]}")
            for p in msg.get('peers', []):
                if tuple(p) != (self.host, self.port) and tuple(p) not in self.peers:
                    self.peers[tuple(p)] = '?'
            if len(msg.get('peers', [])) <= 1:
                self.send_to(peer, {
                    'type': 'intro_ack',
                    'me': [self.host, self.port],
                    'alias': self.alias,
                    'peers': [[h, p] for (h, p) in self.peers.keys()],
                    'teams': {self._str_key(k): v for k, v in self.teams.items()}
                })
            else:
                self.send_to(peer, {
                    'type': 'intro_ack',
                    'me': [self.host, self.port],
                    'alias': self.alias,
                    'peers': [],
                    'teams': {self._str_key((self.host, self.port)): self.team}
                })
        elif t == 'intro_ack':
            peer = tuple(msg['me'])
            self.peers[peer] = msg.get('alias', '?')
            teams_recv = msg.get('teams', {})
            for k, v in teams_recv.items():
                self.teams[self._tuple_key(k)] = v
            if (self.host, self.port) not in self.teams:
                self.teams[(self.host, self.port)] = None
            self.on_event('log', f"INTRO_ACK de {peer[0]}:{peer[1]}")
            new_peers = 0
            for p in msg.get('peers', []):
                pt = tuple(p)
                if pt != (self.host, self.port) and pt not in self.peers and pt not in self.sockets:
                    self.peers[pt] = '?'
                    new_peers += 1
                    self.connect_to(pt)
            if new_peers > 0:
                self.on_event('log', f"Agregados {new_peers} peers. Total: {len(self.peers)}")
            if hasattr(self, '_joining_mesh') and self._joining_mesh:
                self._intro_acks = getattr(self, '_intro_acks', 0) + 1
                if self._intro_acks >= getattr(self, '_expected_acks', 1):
                    self._joining_mesh = False
                    self.broadcast_peer_joined()
        elif t == 'peer_joined':
            peer = tuple(msg['peer'])
            alias = msg.get('alias', '?')
            team = msg.get('team')
            if peer not in self.peers or self.peers[peer] != alias or self.teams.get(peer) != team:
                self.peers[peer] = alias
                self.teams[peer] = team
                self.on_event('log', f"Nuevo peer unido: {alias}@{peer[0]}:{peer[1]} ({team})")
        elif t == 'join_req':
            team = msg['team']
            peer = tuple(msg['from'])
            if self.team == team:
                self.on_event('join_req', peer, team, self.peers.get(peer, str(peer)))
        elif t == 'join_vote':
            # Solo el solicitante debe iniciar la partida si alcanza mayoría
            if hasattr(self, '_joining') and self._joining and msg['team'] == self._proposed:
                voter = tuple(msg['from'])
                if not hasattr(self, '_voters'):
                    self._voters = set()
                if voter not in self._voters:
                    self._voters.add(voter)
                    total = len(getattr(self, '_total_voters', []))
                    if msg.get('vote'):
                        self._votes = getattr(self, '_votes', 0) + 1
                        self.on_event('log', f"Voto SÍ de {self.peers.get(voter, voter)} ({self._votes} de {total})")
                    else:
                        votos_no = len(self._voters) - self._votes
                        self.on_event('log', f"Voto NO de {self.peers.get(voter, voter)} ({votos_no} NO de {total})")
                if self._votes >= max(1, total//2+1):
                    self.team = self._proposed
                    self.teams[(self.host, self.port)] = self.team
                    self.on_event('log', f"¡Unido a {self.team} por mayoría!")
                    self._joining = False
                    self.broadcast_peers()
                    self.broadcast({'type': 'team_update', 'peer': [self.host, self.port], 'team': self.team})
                    # Ya no llamar a ready_and_maybe_start_game aquí. El usuario debe presionar 'Listo' manualmente.
            else:
                # Los demás solo muestran el log del voto recibido
                voter = tuple(msg['from'])
                total = len(getattr(self, '_total_voters', []))
                if msg.get('vote'):
                    self.on_event('log', f"Voto SÍ de {self.peers.get(voter, voter)}")
                else:
                    self.on_event('log', f"Voto NO de {self.peers.get(voter, voter)}")
            return
        elif t == 'leave':
            peer = tuple(msg['from'])
            self.peers.pop(peer, None)
            self.teams.pop(peer, None)
            self.sockets.pop(peer, None)
            self._remove_peer_from_game(peer)
            self.on_event('log', f"{msg.get('alias', peer)} salió de la red.")
            self.broadcast_peers()
        elif t == 'team_update':
            peer = tuple(msg['peer'])
            team = msg['team']
            prev_team = self.teams.get(peer)
            self.teams[peer] = team
            if prev_team != team:
                self.on_event('log', f"{self.peers.get(peer, peer)} ahora es parte de {team}")
        elif t == 'game_roll':
            jugador = tuple(msg['jugador'])
            equipo = msg['equipo']
            roll = msg['roll']
            self.on_event('log', f"[Juego] Recibida tirada de {jugador} ({equipo}): {roll}")
            self._procesar_roll(jugador, equipo, roll)
        elif t == 'game_start':
            self.on_event('log', f"[Juego] Recibido inicio de partida")
            self._handle_game_start(msg)
        elif t == 'ready':
            peer = tuple(msg['from'])
            alias = msg.get('alias', str(peer))
            self.ready_peers = getattr(self, 'ready_peers', set())
            self.ready_peers.add(peer)
            total = len(self.peers) + 1
            count = len(self.ready_peers)
            self.on_event('log', f"{alias} está listo para comenzar! ({count}/{total})")
            # Solo actualizar lista y log. NO iniciar partida ni chequear mayoría aquí.
            self.on_event('log', f"[Juego] Esperando mayoría para iniciar partida...")
            return
        elif t == 'game_next_turn':
            self._handle_game_next_turn(msg)
        elif t and t.startswith('game_'):
            print(f"[DEBUG] handle_message: Procesando mensaje de juego {t} localmente")
            if hasattr(self, 'on_game_msg'):
                self.on_game_msg(msg)

    def connect_to(self, peer):
        if peer in self.sockets or peer == (self.host, self.port):
            return
        try:
            self.switch_team('')
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.connect(peer)
            self.sockets[peer] = s
            self.on_event('log', f"Conectado a {peer[0]}:{peer[1]}")
            threading.Thread(target=self.handle_peer, args=(s,), daemon=True).start()
            time.sleep(0.05)
            msg = {
                'type': 'intro',
                'me': [self.host, self.port],
                'alias': self.alias,
                'team': self.team,
                'peers': [[h, p] for (h, p) in self.peers.keys()],
                'teams': {self._str_key(k): v for k, v in self.teams.items()}
            }
            s.sendall((json.dumps(msg)+'\n').encode())
            self.on_event('log', f"Enviado intro a {peer[0]}:{peer[1]}")
            if not hasattr(self, '_joining_mesh') or not self._joining_mesh:
                self._joining_mesh = True
                self._intro_acks = 0
                self._expected_acks = 1
            # --- gRPC log: ACEPTAR_PRIMER_PEER si era el primero ---
            if len(self.peers) == 1:
                self._log_action('INICIO', 'ACEPTAR_PRIMER_PEER', {'peer': str(peer)})
        except Exception as e:
            self.on_event('log', f"Error conectando a {peer}: {e}")

    def _serialize_for_json(self, obj):
        """Convierte tuplas a listas recursivamente para serialización JSON"""
        if isinstance(obj, tuple):
            return list(obj)
        elif isinstance(obj, dict):
            # CRÍTICO: También convertir keys que sean tuplas
            serialized_dict = {}
            for k, v in obj.items():
                # Convertir key si es tupla
                if isinstance(k, tuple):
                    new_key = str(k)  # Convertir tupla a string para JSON
                else:
                    new_key = k
                # Serializar value recursivamente
                serialized_dict[new_key] = self._serialize_for_json(v)
            return serialized_dict
        elif isinstance(obj, list):
            return [self._serialize_for_json(v) for v in obj]
        else:
            return obj

    def send_to(self, peer, msg):
        s = self.sockets.get(peer)
        if s:
            try:
                # Serializar tuplas a listas antes del JSON
                serialized_msg = self._serialize_for_json(msg)
                json_data = json.dumps(serialized_msg)
                s.sendall((json_data + '\n').encode())
                return True
            except Exception as e:
                print(f"[DEBUG] send_to: ERROR enviando a {peer}: {e}")
                # Remover socket roto y intentar reconectar
                if peer in self.sockets:
                    try:
                        self.sockets[peer].close()
                    except:
                        pass
                    del self.sockets[peer]
                return False
        else:
            return False

    def broadcast(self, msg):
        print(f"[DEBUG] broadcast: Enviando {msg.get('type', 'unknown')} a {len(self.sockets)} peers")
        success_count = 0
        for peer in list(self.sockets.keys()):
            if self.send_to(peer, msg):
                success_count += 1
        print(f"[DEBUG] broadcast: Enviado exitosamente a {success_count}/{len(list(self.sockets.keys()))} peers")
        return success_count

    def broadcast_peers(self):
        msg = {'type': 'peers_update', 'peers': [[h, p] for (h, p) in self.peers.keys()]}
        self.broadcast(msg)

    def graceful_leave(self):
        # Loguear salida voluntaria antes de cerrar sockets
        self._log_action('NA', 'SALIR_RED', {
            'alias': self.alias,
            'ip': f"{self.host}:{self.port}",
            'motivo': 'El usuario salió voluntariamente de la red'
        })
        self.broadcast({'type': 'leave', 'from': [self.host, self.port], 'alias': self.alias})
        time.sleep(0.1)
        for s in self.sockets.values():
            try: s.close()
            except: pass

    def me(self):
        return (self.host, self.port)

    def connect_to_peer(self, host, port):
        peer = (host, port)
        if peer not in self.peers:
            self.peers[peer] = '?'
        self.connect_to(peer)

    def switch_team(self, new_team):
        new_team = [new_team, None][new_team == '']
        if new_team != self.team:
            self.team = new_team
            self.teams[(self.host, self.port)] = new_team
            self.broadcast_peers()
            msg = {'type': 'team_update', 'peer': [self.host, self.port], 'team': new_team}
            self.broadcast(msg)
            self._log_action('NA', 'CAMBIO_EQUIPO', {'nuevo_equipo': new_team})

    def request_join_team(self, team_name):
        if team_name not in TEAMS or team_name == self.team:
            return
        team_peers = [p for p, t in self.teams.items() if t == team_name]
        if not team_peers:
            self.switch_team(team_name)
            return
        self._joining = True
        self._proposed = team_name
        self._votes = 0
        self._voters = set()
        self._total_voters = team_peers
        self.on_event('log', f"Pidiendo unirme a {team_name}...")
        msg = {'type': 'join_req', 'team': team_name, 'from': [self.host, self.port]}
        for peer in team_peers:
            self.send_to(peer, msg)

    def send_join_vote(self, requestor, team, accept):
        msg = {'type': 'join_vote', 'team': team, 'vote': accept, 'from': [self.host, self.port]}
        self.send_to(requestor, msg)

    # --- INTEGRACIÓN CON LA GUI ---
    def set_root(self, root):
        """Permite a la lógica de juego usar after de Tkinter para timers."""
        self.root = root

    # --- LÓGICA DE JUEGO SIMPLIFICADA ---
    def ready_and_maybe_start_game(self):
        """Llamar cuando un jugador presiona 'listo'. Si hay mayoría, inicia la partida."""
        self.ready_peers = getattr(self, 'ready_peers', set())
        self.ready_peers.add(self.me())
        # Notificar a todos que este jugador está listo
        alias = self.alias
        total = len(self.peers) + 1
        count = len(self.ready_peers)
        self.on_event('log', f"{alias} está listo para comenzar! ({count}/{total})")
        # --- NUEVO: avisar a los demás ---
        msg = {'type': 'ready', 'from': [self.host, self.port], 'alias': self.alias}
        self.broadcast(msg)
        # --- gRPC log: INICIAR_PARTIDA (solo si soy el primero en estar listo) ---
        if count == 1:
            self._log_action('INICIO', 'INICIAR_PARTIDA', {
                'evento': 'El usuario presionó Listo',
                'total_peers': total
            })
        if count >= (total // 2) + (total % 2):
            self.on_event('log', f"[Juego] Mayoría lista, iniciando partida...")
            # Solo el coordinador genera el id_instancia y loguea START_GAME
            if self.me() == min(list(self.peers.keys()) + [self.me()]):
                import random
                self.id_instancia = random.randint(1, 2**31-1)  # Genera un entero aleatorio positivo
                log_client.id_instancia = self.id_instancia
                self._log_action('INICIO', 'START_GAME', {
                    'evento': 'Se inicia la partida (mayoría lista)',
                    'equipos': {str(k): v for k, v in getattr(self, 'teams', {}).items()},
                    'ready_peers': [str(p) for p in self.ready_peers],
                    'id_instancia': self.id_instancia
                })
                self._start_game_as_coordinator()
            else:
                self.on_event('log', f"[Juego] Esperando inicio de partida del coordinador...")

    def _start_game_as_coordinator(self):
        equipos = {p: self.teams.get(p, None) for p in list(self.peers.keys()) + [self.me()]}
        equipos = {p: t for p, t in equipos.items() if t}
        orden = {}
        for team in TEAMS:
            jugadores = [p for p, t in equipos.items() if t == team]
            if jugadores:
                orden[team] = jugadores
        # No generes un nuevo id_instancia aquí, usa el ya generado
        msg = {
            'type': 'game_start',
            'equipos': {self._str_key(k): v for k, v in equipos.items()},
            'orden': {k: [list(p) for p in v] for k, v in orden.items()},
            'id_instancia': self.id_instancia,
            'from': list(self.me())
        }
        self.broadcast(msg)
        self.on_event('log', f"[Juego] Enviando inicio de partida a todos...")
        self._log_action('INICIO', 'START_GAME', {'equipos': equipos, 'orden': orden, 'id_instancia': self.id_instancia})
        # El coordinador también debe procesar el mensaje localmente para iniciar el countdown y logs
        self.handle_message(msg, None)

    def _handle_game_start(self, msg):
        equipos = {self._tuple_key(k): v for k, v in msg['equipos'].items()}
        orden = {k: [tuple(p) for p in v] for k, v in msg['orden'].items()}
        self._equipos = equipos
        self._orden = orden
        self._marcador = {k: 0 for k in orden}
        self._turno_idx = {k: 0 for k in orden}
        self._turno_actual = {k: orden[k][0] for k in orden}
        self._turno_timer = None
        self.id_instancia = msg.get('id_instancia')
        log_client.id_instancia = str(self.id_instancia) if self.id_instancia else ''
        self.on_event('log', f"[Juego] Equipos: {equipos}")
        self.on_event('log', f"[Juego] Orden de turnos: {orden}")
        self.on_event('update_scores', dict(self._marcador))
        self._cuenta_regresiva(3)

    def _cuenta_regresiva(self, n):
        if n == 3:
            # Bloquear controles de equipo y listo al iniciar countdown
            self.on_event('lock_team_and_ready')
        if n == 0:
            self.on_event('log', f"[Juego] ¡Comienza la partida!")
            self._iniciar_turno()
        else:
            self.on_event('log', f"[Juego] Comienza en {n}...")
            if hasattr(self, 'root'):
                self.root.after(1000, lambda: self._cuenta_regresiva(n-1))

    def _iniciar_turno(self):
        print(f"[DEBUG] _iniciar_turno: Iniciando turno_id={getattr(self, '_turno_id', 0)+1}")
        # Cancelar timer anterior si existe
        if hasattr(self, '_turno_timer') and self._turno_timer:
            print(f"[DEBUG] _iniciar_turno: Cancelando timer anterior.")
            try:
                self.root.after_cancel(self._turno_timer)
            except Exception:
                print(f"[DEBUG] _iniciar_turno: Error al cancelar timer anterior.")
                pass
            self._turno_timer = None
        # Control de id de turno para evitar duplicidad
        self._turno_id = getattr(self, '_turno_id', 0) + 1
        turno_id = self._turno_id
        self._turno_ya_lanzo = {k: False for k in self._turno_actual}
        self._turno_time_left = 20  # segundos
        self._turno_finalizado = False  # Flag para evitar doble avance/auto_roll
        print(f"[DEBUG] _iniciar_turno: _turno_actual={self._turno_actual}")
        print(f"[DEBUG] _iniciar_turno: _turno_ya_lanzo={self._turno_ya_lanzo}")
        self._rolls_recibidos = getattr(self, '_rolls_recibidos', {})
        self._rolls_recibidos[self._turno_id] = set()  # Set de equipos que ya recibieron roll en este turno
        self.on_event('turn_number', self._turno_id)
        self.on_event('turn_start_timer', self._turno_time_left)
        self._tick_turn_timer(turno_id)  # Inicia el contador visual y el after
        for team, jugador in self._turno_actual.items():
            if jugador == self.me():
                alias = self.alias
            else:
                alias = self.peers.get(jugador)
                if alias is None:
                    alias = self.peers.get(tuple(jugador), '?')
            ip, puerto = jugador
            self.on_event('log', f"Turno de {team}:{alias}@{ip}:{puerto}")
        if self.team in self._turno_actual and self._turno_actual[self.team] == self.me():
            self.on_event('enable_roll', True)
        else:
            self.on_event('enable_roll', False)

    def _tick_turn_timer(self, turno_id=None):
        if turno_id is None:
            turno_id = getattr(self, '_turno_id', 0)
        print(f"[DEBUG] _tick_turn_timer: turno_id={turno_id}, _turno_time_left={self._turno_time_left}")
        if getattr(self, '_turno_finalizado', False):
            print(f"[DEBUG] _tick_turn_timer: Turno ya finalizado, no se ejecuta timer ni auto_roll.")
            return
        if hasattr(self, 'root'):
            if self._turno_time_left == 10:
                self.on_event('log', '[Juego] ¡Quedan 10 segundos para lanzar el dado!')
            if self._turno_time_left == 5:
                self.on_event('log', '[Juego] ¡Quedan 5 segundos para lanzar el dado!')
            self.on_event('turn_timer', self._turno_time_left)
            if self._turno_time_left > 0:
                self._turno_time_left -= 1
                self._turno_timer = self.root.after(1000, lambda: self._tick_turn_timer(turno_id))
            else:
                self._turno_timer = None
                print(f"[DEBUG] _tick_turn_timer: Timer llegó a cero, llamando a _auto_roll para turno_id={turno_id}")
                if turno_id == getattr(self, '_turno_id', 0) and not getattr(self, '_turno_finalizado', False):
                    self._auto_roll(turno_id)
                else:
                    print(f"[DEBUG] _tick_turn_timer: turno_id desincronizado o turno finalizado, no se llama a _auto_roll.")

    def lanzar_dado(self):
        # Solo si es mi turno y no lancé
        if not self.team or self._turno_actual.get(self.team) != self.me() or self._turno_ya_lanzo.get(self.team):
            return
        roll = self._roll()
        msg = {'type': 'game_roll', 'jugador': list(self.me()), 'equipo': self.team, 'roll': roll}
        self.broadcast(msg)
        self.on_event('log', f"[Juego] Enviando mi tirada: {roll}")
        self._log_action('NA', 'LANZAR_DADO', {'roll': roll, 'equipo': self.team})
        self._procesar_roll(self.me(), self.team, roll)

    def _auto_roll(self, turno_id=None):
        if getattr(self, '_turno_finalizado', False):
            print(f"[DEBUG] _auto_roll: Turno ya finalizado, no se ejecuta auto_roll.")
            return
        # Solo ejecutar si el turno_id es el actual
        if turno_id is not None and turno_id != getattr(self, '_turno_id', 0):
            return
        for team, jugador in self._turno_actual.items():
            if not self._turno_ya_lanzo.get(team):
                msg = {'type': 'game_roll', 'jugador': list(jugador), 'equipo': team, 'roll': 0}
                self.broadcast(msg)
                self.on_event('log', f"[Juego] {jugador} ({team}) no lanzó a tiempo. Tirada automática: 0")
                self._procesar_roll(jugador, team, 0)

    def _procesar_roll(self, jugador, equipo, roll):
        print(f"[DEBUG] _procesar_roll: jugador={jugador}, equipo={equipo}, roll={roll}")
        print(f"[DEBUG] _procesar_roll: _turno_ya_lanzo antes: {getattr(self, '_turno_ya_lanzo', {})}")
        turno_id = getattr(self, '_turno_id', 0)
        # --- Sincronización: registrar roll recibido por equipo y turno ---
        self._rolls_recibidos = getattr(self, '_rolls_recibidos', {})
        if turno_id not in self._rolls_recibidos:
            self._rolls_recibidos[turno_id] = set()
        self._rolls_recibidos[turno_id].add(equipo)
        # Prevenir doble procesamiento por equipo y turno
        if self._turno_ya_lanzo.get(equipo):
            print(f"[DEBUG] _procesar_roll: Ya se procesó el roll para equipo {equipo}, ignorando.")
            return
        self._marcador[equipo] += roll
        self._turno_ya_lanzo[equipo] = True
        print(f"[DEBUG] _procesar_roll: _turno_ya_lanzo después: {self._turno_ya_lanzo}")
        # Obtener alias del jugador
        if jugador == self.me():
            alias = self.alias
        else:
            alias = self.peers.get(jugador)
            if alias is None:
                alias = self.peers.get(tuple(jugador), '?')
        self.on_event('log', f"[{equipo}] {alias} sacó {roll} en su dado.")
        self.on_event('update_scores', dict(self._marcador))
        print(f"[DEBUG] _procesar_roll: marcador actual: {self._marcador}")
        # Si todos lanzaron, pasar turno SOLO si se recibieron todos los rolls de todos los equipos
        equipos_esperados = set(self._turno_actual.keys())
        equipos_con_roll = self._rolls_recibidos[turno_id]
        if all(self._turno_ya_lanzo.values()) and equipos_con_roll == equipos_esperados:
            print(f"[DEBUG] _procesar_roll: Todos lanzaron y se recibieron todos los rolls. Equipos: {list(self._turno_ya_lanzo.keys())}")
            equipos_ganadores = [k for k, v in self._marcador.items() if v >= PUNTAJE_MAXIMO]
            if equipos_ganadores:
                print(f"[DEBUG] _procesar_roll: Equipos ganadores detectados: {equipos_ganadores}")
                if len(equipos_ganadores) == 1:
                    ganador = equipos_ganadores[0]
                    resultado = {'ganador': ganador}
                else:
                    resultado = {'empate': equipos_ganadores}
                if self.me() == min(list(self.peers.keys()) + [self.me()]):
                    print(f"[DEBUG] _procesar_roll: Soy el coordinador, logueando FIN_PARTIDA")
                    self._log_action('FIN', 'FIN_PARTIDA', {'resultado': resultado, 'marcador': dict(self._marcador)})
                self.on_event('game_over', resultado)
                return  # No continuar el juego
            if not hasattr(self, '_turno_sync_sent'):
                self._turno_sync_sent = set()
            if turno_id not in self._turno_sync_sent:
                print(f"[DEBUG] _procesar_roll: Enviando game_next_turn para turno_id={turno_id}")
                self._turno_sync_sent.add(turno_id)
                msg = {'type': 'game_next_turn', 'turno_id': turno_id, 'from': list(self.me()), 'marcador': dict(self._marcador)}
                self.broadcast(msg)
                self._handle_game_next_turn(msg)
            else:
                print(f"[DEBUG] _procesar_roll: game_next_turn ya enviado para turno_id={turno_id}")
        else:
            if not all(self._turno_ya_lanzo.values()):
                print(f"[DEBUG] _procesar_roll: No todos lanzaron aún.")
            if equipos_con_roll != equipos_esperados:
                print(f"[DEBUG] _procesar_roll: Faltan rolls de equipos: {equipos_esperados - equipos_con_roll}")

    def _handle_game_next_turn(self, msg):
        print(f"[DEBUG] _handle_game_next_turn: recibido msg: {msg}")
        turno_id = msg.get('turno_id')
        if not hasattr(self, '_last_turn_synced'):
            self._last_turn_synced = set()
        if turno_id in self._last_turn_synced:
            print(f"[DEBUG] _handle_game_next_turn: turno_id {turno_id} ya procesado, ignorando.")
            return  # Ya procesado
        self._last_turn_synced.add(turno_id)
        self._turno_finalizado = True  # Marcar turno como finalizado para evitar auto_roll tardío
        # Cancelar timer si existe
        if hasattr(self, '_turno_timer') and self._turno_timer:
            print(f"[DEBUG] _handle_game_next_turn: Cancelando timer actual.")
            try:
                self.root.after_cancel(self._turno_timer)
            except Exception:
                print(f"[DEBUG] _handle_game_next_turn: Error al cancelar timer.")
                pass
            self._turno_timer = None
        else:
            print(f"[DEBUG] _handle_game_next_turn: No hay timer activo para cancelar.")
        marcador_msg = msg.get('marcador')
        if marcador_msg:
            print(f"[DEBUG] _handle_game_next_turn: Actualizando marcador con: {marcador_msg}")
            self._marcador.update(marcador_msg)
            self.on_event('update_scores', dict(self._marcador))
        self._siguiente_turno()

    def _siguiente_turno(self):
        # Avanzar al siguiente jugador de cada equipo
        for team, jugadores in self._orden.items():
            idx = (self._turno_idx[team] + 1) % len(jugadores)
            self._turno_idx[team] = idx
            self._turno_actual[team] = jugadores[idx]
        self._iniciar_turno()

    def _roll(self):
        import random
        return random.randint(MIN_DADO, MAX_DADO)

    def _log_action(self, marcador, accion, args=None):
        # Llama al cliente gRPC para loguear la acción, evitando duplicados inmediatos
        ip = f"{self.host}:{self.port}"
        alias = self.alias
        # --- Evitar duplicados: guarda el último log enviado por acción y args ---
        if not hasattr(self, '_last_log_sent'):
            self._last_log_sent = {}
        # Serializar args para deduplicación y para JSON
        safe_args = self._serialize_for_json(args or {})
        key = (marcador, accion, str(safe_args))
        now = int(time.time() * 1000)
        last = self._last_log_sent.get(key)
        # Si el último log igual fue hace menos de 2 segundos, no lo reenvíes
        if last and now - last < 2000:
            return
        self._last_log_sent[key] = now
        # Usar el id_instancia actual si existe
        if self.id_instancia:
            log_client.id_instancia = self.id_instancia
        else:
            print("[WARN] id_instancia no está definido, no se enviará log.")
            return
        log_client.send_log(marcador, ip, alias, accion, safe_args)
