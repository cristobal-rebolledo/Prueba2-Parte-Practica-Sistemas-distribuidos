# 🎲 P2P Mesh Grid Game

Bienvenido a **P2P Mesh Grid Game**, un juego distribuido en red P2P donde los usuarios pueden conectarse, formar equipos y competir en una partida de dados por turnos. El sistema implementa mecanismos de consenso y sincronización para asegurar el correcto funcionamiento en red, todo basado en la confianza mutua entre los peers.

---

## 🚀 Características principales
- Red P2P sin servidor central mediante sockets
- Equipos dinámicos con votación para unirse
- Coordinador automático para inicio de partida
- Sincronización de turnos y tiradas con tolerancia a fallos
- Interfaz gráfica moderna (Tkinter)
- Logging distribuido vía gRPC a un servior remoto

---

## 📦 Dependencias

- Python 3.8+
- grpcio
- protobuf
- tk (Tkinter)

Instala las dependencias con:
```bash
pip install -r requirements.txt
```

---

## 🖥️ Ejecución rápida

Desde la raíz del proyecto:
```bash
python main.py
```

---

## 🛠️ Comandos útiles

| Acción                        | Comando ejemplo                                 |
|------------------------------|-------------------------------------------------|
| Instalar dependencias        | `pip install -r requirements.txt`               |
| Ejecutar la app (GUI)        | `python main.py`                                |
| Ejecutar con alias/puerto    | `python main.py --alias Bob --port 8081`        |
| (Opcional) Regenerar proto   | `python -m grpc_tools.protoc -I./proto --python_out=./proto --grpc_python_out=./proto ./proto/log.proto` |

---

## ⚙️ Configuración: api.conf y game.conf

El comportamiento de la aplicación puede personalizarse editando los siguientes archivos de configuración en la raíz del proyecto:

### `game.conf`
Define los parámetros del juego y los equipos disponibles. Ejemplo:
```ini
game.conf
MIN_DADO=1
MAX_DADO=6
PUNTAJE_MAXIMO=21
TEAMS=ROJO,AZUL,VERDE
```
- `MIN_DADO` y `MAX_DADO`: valores mínimo y máximo del dado.
- `PUNTAJE_MAXIMO`: puntaje necesario para ganar.
- `TEAMS`: lista separada por comas de los nombres de los equipos.

### `api.conf`
Configura la dirección del servidor gRPC para el logging distribuido. Ejemplo:
```ini
api.conf
ADDR=127.0.0.1
PORT=50051
```
- `ADDR`: dirección IP o hostname del servidor de logs.
- `PORT`: puerto del servidor gRPC.

Asegúrate de que estos archivos existan y estén correctamente configurados antes de ejecutar la aplicación, especialmente si cambias el entorno de red o el servidor de logs.

---

## 🤝 Flujos y mecanismos de consenso principales

> **Nota:** La red funciona en base a la confianza mutua entre los peers. No hay autoridad central ni verificación criptográfica: se asume que los nodos respetan los mensajes y reglas del protocolo.

### 1️⃣ Unirse a una partida (descubrimiento de peers)
Cuando un usuario se conecta a otro peer, envía un mensaje `intro` y recibe un `intro_ack` con la lista de peers y equipos conocidos. Así, cada nodo va agregando a los nuevos peers a su lista local y propagando la información:
```python
# mesh_peer.py
msg = {
    'type': 'intro',
    'me': [self.host, self.port],
    'alias': self.alias,
    'team': self.team,
    'peers': [[h, p] for (h, p) in self.peers.keys()],
    'teams': {self._str_key(k): v for k, v in self.teams.items()}
}
s.sendall((json.dumps(msg)+'\n').encode())
# Al recibir intro_ack:
for p in msg.get('peers', []):
    pt = tuple(p)
    if pt != (self.host, self.port) and pt not in self.peers:
        self.peers[pt] = '?'
```
Esto permite que la red se expanda y todos los nodos conozcan a los demás, confiando en la información recibida.

### 2️⃣ Unirse a un equipo (con y sin votación)
- **Sin votación:** Si el equipo está vacío, el usuario se une directamente y notifica a los demás:
```python
# peer_gui.py
if len(miembros) == 0:
    self.peer.team = team
    self.peer.teams[(self.peer.host, self.peer.port)] = team
    self.status.config(text=f"¡Unido a {team} (sin votos)!")
    self.peer.broadcast_peers()
    self.peer.broadcast({'type': 'team_update', 'peer': [self.peer.host, self.peer.port], 'team': team})
```
- **Con votación:** Si el equipo ya tiene miembros, se solicita unirse y los miembros votan. Se requiere mayoría simple:
```python
# peer_gui.py
self.peer._joining = True
self.peer._proposed = team
self.peer._votes = 0
self.peer._voters = set()
self.peer._total_voters = set(miembros)
self.peer.broadcast({'type': 'join_req', 'team': team, 'from': [self.peer.host, self.peer.port]})
# mesh_peer.py
def handle_message(self, msg, conn):
    if msg['type'] == 'join_req':
        self.send_to(peer, {'type': 'join_vote', 'team': team, 'from': [self.host, self.port], 'vote': True})
# El solicitante cuenta los votos y si hay mayoría, se une:
if self._votes >= max(1, total//2+1):
    self.team = self._proposed
    self.teams[(self.host, self.port)] = self.team
    self.broadcast({'type': 'team_update', 'peer': [self.host, self.port], 'team': self.team})
```
La votación es por confianza: se asume que los peers votan honestamente.

### 3️⃣ Iniciar partida (coordinador y orden)
Cuando la mayoría de los peers están listos (`ready`), el peer con menor IP:puerto actúa como coordinador y genera el orden de juego y el id de la partida. El coordinador envía el mensaje `game_start` a todos:
```python
# mesh_peer.py
if count >= (total // 2) + (total % 2):
    if self.me() == min(list(self.peers.keys()) + [self.me()]):
        self.id_instancia = random.randint(1, 2**31-1)
        self._start_game_as_coordinator()
def _start_game_as_coordinator(self):
    msg = {
        'type': 'game_start',
        'equipos': {self._str_key(k): v for k, v in equipos.items()},
        'orden': {k: [list(p) for p in v] for k, v in orden.items()},
        'id_instancia': self.id_instancia,
        'from': list(self.me())
    }
    self.broadcast(msg)
```
Todos los peers confían en el coordinador para el inicio y orden de la partida.

### 4️⃣ Tirar el dado, timeout y sincronización de turno
Cada equipo tira el dado en su turno. Si un jugador no tira en 20 segundos, se realiza un `auto_roll` (tirada automática en 0):
```python
# mesh_peer.py
def _tick_turn_timer(self, turno_id=None):
    if self._turno_time_left > 0:
        self._turno_time_left -= 1
        self._turno_timer = self.root.after(1000, lambda: self._tick_turn_timer(turno_id))
    else:
        self._auto_roll(turno_id)
def _auto_roll(self, turno_id=None):
    for team, jugador in self._turno_actual.items():
        if not self._turno_ya_lanzo.get(team):
            msg = {'type': 'game_roll', 'jugador': list(jugador), 'equipo': team, 'roll': 0}
            self.broadcast(msg)
            self._procesar_roll(jugador, team, 0)
```
Cuando todos los equipos han tirado, el primer peer que detecta esto emite `game_next_turn` para sincronizar el avance de ronda en toda la red:
```python
# mesh_peer.py
if all(self._turno_ya_lanzo.values()):
    if not hasattr(self, '_turno_sync_sent'):
        self._turno_sync_sent = set()
    if turno_id not in self._turno_sync_sent:
        self._turno_sync_sent.add(turno_id)
        msg = {'type': 'game_next_turn', 'turno_id': turno_id, 'from': list(self.me()), 'marcador': dict(self._marcador)}
        self.broadcast(msg)
        self._handle_game_next_turn(msg)
```
Esto asegura que todos los peers avancen de turno de forma coordinada, confiando en que el primero que detecta el fin de ronda actúa correctamente.

---

## Sincronización robusta de turnos y rolls

Para evitar desincronización cuando un peer deja expirar el timer (no tira el dado manualmente), el sistema implementa un mecanismo robusto de sincronización:

- Cada peer lleva un registro de los `game_roll` recibidos por turno y equipo.
- Solo se avanza de turno (enviando y procesando `game_next_turn`) cuando:
  - Todos los equipos han lanzado (manual o automático).
  - Se han recibido los `game_roll` de todos los equipos para ese turno.
- Si un peer recibe un `game_next_turn` antes de que su timer expire, cancela su timer y no ejecuta el auto-roll, evitando quedarse desfasado.
- Esto garantiza que todos los peers avancen de turno y actualicen el marcador exactamente al mismo tiempo, sin importar si algún peer deja expirar el timer.

Este mecanismo hace el juego reducir condiciones de carrera y dessincronización en la lógica de turnos y scores. 

---

### 5️⃣ Salida de un peer y actualización de equipos en caliente
Cuando un peer se desconecta voluntariamente o por error, se envía un mensaje `leave` y todos los peers actualizan sus estructuras internas (equipos, turnos, marcador):
```python
# mesh_peer.py
def graceful_leave(self):
    self.broadcast({'type': 'leave', 'from': [self.host, self.port], 'alias': self.alias})
    for s in self.sockets.values():
        try: s.close()
        except: pass
# ...
def handle_message(self, msg, conn):
    if msg.get('type') == 'leave':
        peer = tuple(msg['from'])
        self.peers.pop(peer, None)
        self.teams.pop(peer, None)
        self.sockets.pop(peer, None)
        self._remove_peer_from_game(peer)
        self.broadcast_peers()
```
Esto permite que la red se adapte dinámicamente a la salida de nodos, manteniendo la coherencia de los equipos y el juego en curso.

---

## 📚 Detalles de confianza y tolerancia a fallos
- Todos los mecanismos de consenso y sincronización dependen de la honestidad de los peers.
- No hay autoridad central: cualquier peer puede ser coordinador.
- Si un peer falla, la red sigue funcionando mientras haya mayoría.
- El sistema es ideal para entornos colaborativos, educativos o de experimentación.

---

## 📝 Logging distribuido vía gRPC (opcional)
El sistema puede enviar logs de eventos importantes a un servidor central usando gRPC. Esto es útil para auditoría, depuración o análisis, pero no afecta el consenso ni la lógica principal del juego.

Ejemplo de uso:
```python
# game_log_client.py
log_client.send_log(marcador, ip, alias, accion, args)
```
El logging es asíncrono y tolerante a fallos: si el servidor no responde tras 3 retries, el juego sigue funcionando normalmente.

---
