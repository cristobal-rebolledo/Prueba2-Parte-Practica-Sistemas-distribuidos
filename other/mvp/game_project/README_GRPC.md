# Sistema de logging gRPC para juego distribuido en Elixir

Este módulo implementa el sistema de logging mediante gRPC para el juego distribuido, siguiendo las especificaciones detalladas en el proyecto.

## Características

- **Cliente gRPC en Elixir**: Implementado como un `GenServer` para enviar logs a un servidor externo Node.js
- **No bloqueante**: Las operaciones de logging son asíncronas y utilizan timeouts para evitar bloquear el juego
- **Tolerancia a fallos**: Si el servidor de logging no está disponible, los eventos se guardan localmente y se reintenta su envío
- **Generación automática de código**: Los archivos `.pb.ex` se generan automáticamente a partir de los `.proto`

## Configuración del entorno de desarrollo

El proyecto incluye un script PowerShell (`setup_grpc_codegen.ps1`) que automatiza la configuración del entorno de desarrollo, especialmente para Windows:

1. Configura el PATH para incluir los escripts de Mix
2. Instala el plugin de Protobuf para Elixir
3. Utiliza un binario local de `protoc` (o el del PATH)
4. Genera los archivos Elixir a partir de los `.proto`

### Pasos para configurar el entorno:

```
# En PowerShell
cd path/to/game_project
./setup_grpc_codegen.ps1
```

### Variables de entorno

El proyecto utiliza las siguientes variables de entorno (que pueden configurarse en un archivo `.env`):

```
GRPC_SERVER_IP=127.0.0.1
GRPC_SERVER_PORT=50051
GRPC_SERVER_TIMEOUT=5000
```

## Estructura de logs

Los eventos de log tienen la siguiente estructura:

```elixir
%{
  timestamp: timestamp,       # Unix epoch en segundos
  id_instancia: id,           # ID único de la instancia del juego
  marcador: marker,           # "INICIO", "FIN" o "NA"
  ip: ip,                     # IP del proceso que genera el log
  alias: alias,               # Alias del jugador o "system"
  accion: action,             # Nombre de la función/acción
  args: args_json             # Args como JSON serializado
}
```

## Uso en el código

Para registrar eventos en el juego:

```elixir
alias GameProject.GRPCLogger

# Ejemplo de evento
event = %{
  timestamp: System.system_time(:second),
  id_instancia: GameProject.GameServer.get_instance_id(),
  marcador: "INICIO",
  ip: GameProject.Network.get_my_ip(),
  alias: player.alias,
  accion: "join_game",
  args: Jason.encode!(%{team: "rojo"})
}

# Enviar el evento (no bloqueante)
GRPCLogger.log_event(event)
```

## Para desarrolladores que trabajan con Protobuf en Windows

El script `setup_grpc_codegen.ps1` maneja automáticamente:

1. La instalación del plugin `protoc-gen-elixir`
2. La configuración correcta del PATH
3. La detección y uso de `protoc.exe` local o global
4. La generación de código `.pb.ex` a partir de `.proto`

Si ocurren problemas con la generación de código, asegúrate de que:
- El binario `protoc.exe` esté disponible (en PATH o en la carpeta `bin/`)
- El plugin `protoc-gen-elixir` esté instalado y en el PATH
- Los archivos `.proto` estén correctamente ubicados
