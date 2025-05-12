# Juego Distribuido en Elixir

Un juego distribuido implementado en Elixir donde múltiples procesos independientes se comunican entre sí para formar una red de juego. Cada proceso representa un jugador que puede unirse a equipos, participar en turnos de juego y comunicarse con otros jugadores.

## Características

- **Arquitectura distribuida**: Cada jugador es un nodo independiente que se comunica mediante HTTP
- **Equipos**: Los jugadores pueden unirse a equipos para jugar juntos
- **Sistema de turnos**: Mecánica de juego basada en turnos con lanzamiento de dados
- **Logging centralizado**: Registro de eventos a través de gRPC
- **Tolerancia a fallos**: Detección y manejo de nodos desconectados
- **Interfaz de usuario**: Menú en consola para interactuar con el juego

## Requisitos

- Elixir 1.12 o superior
- Erlang OTP 24 o superior
- Archivo `.env` configurado (ver sección de configuración)

## Instalación

1. Clonar el repositorio:
```bash
git clone https://github.com/tu-usuario/game_project.git
cd game_project
```

2. Instalar dependencias:
```bash
mix deps.get
```

3. Configurar variables de entorno (ver sección siguiente)

4. Compilar el proyecto:
```bash
mix compile
```

## Configuración

Crear un archivo `.env` en la raíz del proyecto con el siguiente contenido:

```
MAX_PLAYERS_PER_TEAM=5
GRPC_SERVER_IP=127.0.0.1
GRPC_SERVER_PORT=50051
```

## Ejecución

Para iniciar el juego:

```bash
mix run -e "GameProject.UI.start()"
```

## Desarrollo y pruebas

Ejecutar las pruebas:

```bash
mix test
```

## Estructura del proyecto

- `lib/game_project/models/` - Estructuras de datos del juego
- `lib/game_project/player_registry.ex` - Gestión de jugadores
- `lib/game_project/game_server.ex` - Lógica del estado de juego
- `lib/game_project/http_server.ex` - Servidor HTTP para comunicación
- `lib/game_project/message_distribution.ex` - Mecanismo de distribución de mensajes
- `lib/game_project/grpc_logger.ex` - Cliente para logging gRPC
- `lib/game_project/ui.ex` - Interfaz de usuario en consola

## Mecánicas del juego

1. Cada jugador puede unirse a un equipo
2. Los equipos compiten lanzando dados en turnos
3. Hay tres tipos de dados disponibles con diferentes riesgos/recompensas
4. El primer equipo en alcanzar la puntuación máxima gana

## Contribución

Las contribuciones son bienvenidas. Por favor, envía un pull request o abre un issue para discutir los cambios.

