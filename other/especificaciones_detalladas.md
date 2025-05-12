# Especificaciones Detalladas del Proyecto Elixir

## Índice
1. [Descripción General](#descripción-general)
2. [Requisitos Técnicos](#requisitos-técnicos)
3. [Estructura de Datos](#estructura-de-datos)
4. [Funcionalidades](#funcionalidades)
   - [Inicialización](#inicialización)
   - [Conexión y Red](#conexión-y-red)
   - [Gestión de Equipos](#gestión-de-equipos)
   - [Mecánica del Juego](#mecánica-del-juego)
   - [Comunicación entre Procesos](#comunicación-entre-procesos)
   - [Integración gRPC](#integración-grpc)
5. [Interfaz de Usuario](#interfaz-de-usuario)
6. [Pruebas](#pruebas)
7. [Consideraciones de Diseño](#consideraciones-de-diseño)
8. [Tecnologías Recomendadas](#tecnologías-recomendadas)

## Descripción General

Este proyecto consiste en un juego distribuido implementado en Elixir donde múltiples procesos independientes se comunican entre sí para formar una red de juego. Cada proceso representa un jugador que puede unirse a equipos, participar en turnos de juego y comunicarse con otros jugadores. El juego utiliza un modelo de comunicación distribuida sin memoria compartida, permitiendo que los procesos estén en diferentes ubicaciones geográficas.

## Requisitos Técnicos

### Entorno y Configuración
- Lenguaje: Elixir
- Archivo de configuración: `.env` para almacenar parámetros configurables como:
  - Número máximo de jugadores por equipo
  - IP y puerto del servidor gRPC de logs
  - Otros parámetros de configuración
- Protocolo de comunicación: HTTP para la comunicación entre procesos
- Logging: Integración con gRPC para envío de logs centralizados

### Comunicación
- Cada proceso debe exponer un servidor HTTP en un puerto especificado por el usuario
- Los procesos deben poder enviar y recibir mensajes entre sí
- Implementación de un mecanismo de "distribución" de mensajes a través de equipos
- Tolerancia a fallos: detección y manejo de procesos desconectados

## Estructura de Datos

### Tabla de Jugadores
Cada proceso mantiene una tabla con la siguiente estructura:

| Campo | Tipo | Descripción |
|-------|------|-------------|
| Dirección | String | Dirección IP y puerto del jugador |
| Alias | String | Nombre identificador del jugador, modificable desde el menú principal |
| Equipo | Atom | Nombre del equipo al que pertenece o `nil` si no tiene equipo |
| Número Secreto | Integer | Generado automáticamente al iniciar, usado para validación |

Esta tabla está indexada por equipo para facilitar la búsqueda y agrupación de jugadores.

### Estado de Juego
Estructura que mantiene:

| Campo | Tipo | Descripción |
|-------|------|-------------|
| ID de Instancia | Integer | Identificador único para la instancia del juego, generado al crear la red |
| Número de Turno | Integer | Contador del turno actual del juego |
| Puntaje por Equipo | Map<Atom, Integer> | Mapa que asocia cada equipo con su puntaje actual |
| Tabla de Turnos | Map<Atom, List<String>> | Registro de qué jugadores ya han participado en el turno actual para cada equipo |
| Puntuación Máxima | Integer | Puntuación objetivo para ganar el juego |
| Estado del Juego | Atom | Puede ser `:en_espera`, `:en_curso` o `:finalizado` |

## Funcionalidades

### Inicialización

#### Obtención de Direcciones IP
- Al iniciar, cada proceso debe:
  1. Obtener su IP local (para comunicaciones en la misma red)
  2. Obtener su IP pública usando el servicio api.ipify.org
  ```elixir
  :inets.start
  {:ok, {_, _, inet_addr}} = :httpc.request('http://api.ipify.org')
  :inets.stop
  ```
  3. Establecer un alias inicial modificable

#### Configuración del Servidor HTTP
- Al iniciar, solicitar al usuario un número de puerto para el servidor HTTP
- Inicializar el servidor HTTP en el puerto especificado
- Configurar rutas y endpoints necesarios para la comunicación

### Conexión y Red

#### Creación de una Red
Cuando un usuario decide crear una red:
1. Solicitar los siguientes parámetros de configuración:
   - Cantidad de equipos (rango: 1-15)
   - Puntuación máxima para ganar
   - Cantidad máxima de jugadores por equipo (1 a N, donde N está definido en .env)
2. Seleccionar nombres de equipos disponibles desde una lista predefinida de átomos sin repetición:
   - `[:equipo_dragon, :equipo_planta, :equipo_rojo, ...]`
3. Establecer una clave de acceso que se almacena usando hash SHA-256
4. Generar un ID de instancia único para el juego (entero aleatorio entre 1 y 999999)
5. Registrar el evento de creación de red mediante el servicio gRPC de logs
6. Entrar en modo de espera para aceptar conexiones entrantes

#### Unirse a una Red Existente
Cuando un usuario decide unirse a una red:
1. Solicitar la IP y puerto del servidor al que desea conectarse
2. Enviar una solicitud con sus datos: 
   - Dirección (IP:puerto) 
   - Alias
   - Número secreto generado
   - Clave de acceso
3. Si la clave es correcta, recibir:
   - La tabla de jugadores sin los números secretos de los demás jugadores
   - El ID de instancia del juego para registro de logs
   - La configuración actual del juego (equipos disponibles, puntuación máxima, etc.)
4. El jugador queda inicialmente sin equipo asignado
5. Registrar el evento de unión a la red mediante el servicio gRPC de logs

### Gestión de Equipos

#### Protocolo para Unirse a un Equipo
1. El jugador selecciona un equipo al que desea unirse
2. Se envía una solicitud a todos los miembros actuales del equipo
3. Cada miembro responde:
   - Si acepta al nuevo miembro: devuelve su número secreto
   - Si rechaza al nuevo miembro: devuelve -1
4. Condiciones para unirse:
   - Si al menos la mitad de los miembros responden afirmativamente, se procede
   - Se elige aleatoriamente un miembro del equipo para verificación
   - Se le envían:
     - Las direcciones de quienes respondieron afirmativamente
     - La suma de los números secretos recibidos
5. El miembro elegido verifica la suma y:
   - Si es correcta: envía un mensaje "distribuye" para informar al resto del equipo
   - Si es incorrecta: rechaza la unión
6. Al unirse exitosamente, el nuevo miembro:
   - Recibe los números secretos del equipo al que se une
   - Elimina de su tabla los números secretos que conocía de otros equipos

#### Caso Especial: Equipo Vacío
1. Si un jugador intenta unirse a un equipo vacío:
   - Se selecciona un jugador aleatorio (de cualquier equipo) para verificar
   - Este confirma que efectivamente el equipo está vacío
   - Se envía un mensaje "distribuye" para que todos actualicen la pertenencia del jugador a ese equipo

### Mecánica del Juego

#### Turnos
1. En cada turno, un jugador por equipo lanza un dado:
   - El jugador puede elegir entre (2 + 1d4), (1 + 1d6) o 1d10 (dados de 4, 6 u 10 caras respectivamente)
   - La elección del tipo de dado es estratégica, mayor riesgo (d4) o mayor recompensa potencial (d10)
2. El resultado se comunica a todos los jugadores mediante un mensaje "distribuye"
3. Todos actualizan el puntaje del equipo correspondiente
4. Tiempo máximo por turno: 10 segundos (si no se realiza acción, se salta automáticamente)
5. Cada acción de lanzamiento se registra mediante el servicio gRPC de logs

#### Selección de Jugadores
1. Se selecciona un jugador arbitrario por equipo que no haya participado en el turno actual
2. Cuando todos los jugadores de un equipo hayan participado, se reinicia ese registro
3. Se debe mantener un seguimiento de quién ha participado en cada turno

#### Fin del Juego
1. El juego termina cuando un equipo alcanza o supera la puntuación máxima establecida
2. Cálculo para ganar: Puntuación actual del equipo + Valor de la tirada > Puntuación máxima
3. Al ganar, se envía un mensaje "distribuye" informando:
   - La nueva puntuación del equipo
   - El fin del juego

### Comunicación entre Procesos

#### Mensaje "distribuye"
Este es el mecanismo principal de comunicación:
1. Al enviar un mensaje "distribuye":
   - Se selecciona un miembro aleatorio de cada equipo (los jugadores sin equipo también cuentan como grupo)
   - Cada seleccionado envía el mensaje a todos los miembros de su propio equipo (incluyéndose)
2. Si algún miembro no responde:
   - Se elimina de la tabla de jugadores
   - Se envía un nuevo mensaje "distribuye" para que todos lo eliminen también
3. Este proceso continúa recursivamente hasta que todos los jugadores restantes estén sincronizados

#### Estructura del Mensaje "distribuye"
Todos los mensajes "distribuye" siguen una estructura común:
- Tipo de acción (actualizar puntaje, eliminar jugador, añadir jugador a equipo, etc.)
- Datos relevantes según el tipo de acción
- Timestamp o identificador para evitar procesamiento duplicado

#### Logging
- Todas las funciones de comunicación deben llamar a una función de logging
- Esta función enviará información al servidor gRPC de logs

### Integración gRPC

#### Configuración gRPC
- La dirección IP y puerto del servidor gRPC de logs se define en el archivo `.env`
- Cada proceso se conecta al servidor gRPC al iniciar
- Si la conexión falla, los logs se almacenan localmente y se intenta reenviar periódicamente

#### Estructura de los Mensajes de Log
Basado en la definición del archivo `log.proto`:

```protobuf
message LogEntry {
  int64 timestamp = 1;    // Timestamp de la acción en formato Unix epoch
  int32 id_instancia = 2; // ID único de la instancia del juego
  string marcador = 3;    // "INICIO", "FIN" o "NA" (acción autofinalizante)
  string ip = 4;          // IP del proceso que genera el log
  string alias = 5;       // Alias del jugador que genera el log
  string accion = 6;      // Nombre de la función que altera el estado del juego
  string args = 7;        // Argumentos de entrada/salida como JSON serializado
}
```

#### Eventos a Registrar
Se debe enviar un mensaje de log en los siguientes eventos:

1. **Creación de red**
   - Marcador: "INICIO"
   - Acción: "create_network"
   - Args: Configuración inicial (equipos, puntuación máxima, resultado del dado, dado escogido, etc.)

2. **Unirse a una red**
   - Marcador: "INICIO"
   - Acción: "join_network"
   - Args: IP del servidor, alias

3. **Unirse a un equipo**
   - Marcador: "INICIO"
   - Acción: "join_team"
   - Args: Nombre del equipo

4. **Aceptar/Rechazar solicitud de unión**
   - Marcador: "FIN"
   - Acción: "process_join_request"
   - Args: Resultado (aceptado/rechazado), alias del solicitante

5. **Lanzamiento de dados**
   - Marcador: "INICIO"
   - Acción: "roll_dice"
   - Args: Equipo, tipo de dado

6. **Resultado de lanzamiento**
   - Marcador: "FIN"
   - Acción: "roll_dice"
   - Args: Equipo, resultado, puntuación actual

7. **Finalización de juego**
   - Marcador: "FIN"
   - Acción: "game_finished"
   - Args: Equipo ganador, puntuación final

8. **Abandono de red**
   - Marcador: "NA"
   - Acción: "leave_network"
   - Args: Alias, IP

9. **Detección de desconexión**
   - Marcador: "NA"
   - Acción: "connection_lost"
   - Args: IP del jugador desconectado

10. **Distribución de mensaje**
    - Marcador: "INICIO"
    - Acción: "distribute_message"
    - Args: Tipo de mensaje, equipos destinatarios

11. **Finalización de distribución**
    - Marcador: "FIN"
    - Acción: "distribute_message"
    - Args: Éxito/fallo, jugadores no alcanzados

## Interfaz de Usuario

### Terminal
- La interfaz debe limpiarse periódicamente para mantener una visualización clara
- Mostrar constantemente el estado actual del juego:
  - Equipos y sus miembros
  - Puntuaciones actuales
  - Turno actual
  - Jugador que debe realizar la acción
  - Tiempo restante (si aplica)

### Menú Principal
Debe incluir dos niveles de menú:

#### Menú Inicial (antes de unirse a una red)
1. Cambiar el alias del jugador
2. Crear una red nueva
3. Unirse a una red existente
4. Salir del juego

#### Menú dentro del Juego (tras unirse a una red)
1. Ver el estado actual del juego
2. Ver la tabla de jugadores completa
3. Mostrar tabla de rutas (información de conectividad entre nodos)
4. Seleccionar un equipo para unirse
5. Abandonar la red (envía un mensaje "distribuye" para que todos eliminen al jugador)
6. Volver al menú inicial

## Pruebas

### Programa de Pruebas
Se debe desarrollar un programa separado que pruebe todas las funcionalidades:
1. Pruebas unitarias de cada componente
2. Pruebas específicas para el mecanismo "distribuye":
   - Verificar la selección aleatoria de representantes por equipo
   - Confirmar la propagación correcta de mensajes
   - Validar la detección y manejo de fallos de conexión
3. Pruebas de integración del flujo completo del juego

### Casos de Prueba Específicos
1. **Inicialización y Conexión**
   - Creación de red e incorporación de jugadores
   - Verificación de transmisión correcta de la tabla de jugadores
   - Validación de la clave de acceso (casos positivos y negativos)

2. **Gestión de Equipos**
   - Unión a equipos (casos normales y límites)
   - Protocolo de validación de números secretos
   - Proceso de unión a equipos vacíos

3. **Comunicación y Distribución**
   - Simulación del mecanismo "distribuye" con diversos tamaños de red
   - Manejo de desconexiones durante el envío de mensajes
   - Verificación de la eliminación correcta de jugadores desconectados
   - Rendimiento bajo condiciones de red adversas (latencia, pérdida de paquetes)

4. **Mecánica de Juego**
   - Ejecución completa de un juego con múltiples equipos
   - Finalización correcta cuando se alcanza la puntuación máxima
   - Gestión de turnos y selección de jugadores
   - Verificación de tiempos de espera por turno

5. **Integración gRPC**
   - Envío correcto de logs al servidor gRPC
   - Manejo de fallos de conexión con el servidor de logs
   - Validación de la estructura de los mensajes enviados

6. **Interfaz de Usuario**
   - Navegación por los menús
   - Visualización correcta del estado del juego
   - Abandono de red y gestión de desconexiones manuales

## Consideraciones de Diseño

### Principios de Diseño
- **Modularidad**: Separar claramente las responsabilidades en módulos cohesivos
- **Cohesión**: Cada módulo debe tener una única responsabilidad bien definida
- **Elegancia**: Código conciso y expresivo, aprovechando las características de Elixir
- **No duplicación**: Evitar cualquier tipo de código repetido
- **Tolerancia a fallos**: Manejar adecuadamente las desconexiones y errores

### Estructuración del Código
- Utilizar GenServers para gestionar el estado
- Implementar supervisores para manejar fallos
- Crear módulos específicos para:
  - Comunicación HTTP
  - Gestión de la tabla de jugadores
  - Lógica del juego
  - Mecanismo "distribuye"
  - Interfaz de usuario

## Tecnologías Recomendadas

### Librerías Principales
Priorizar el uso de librerías existentes para simplificar el código manteniendo la simplicidad:

| Categoría | Librería | Justificación |
|-----------|----------|---------------|
| HTTP Server | **Plug** | Liviano y suficiente para nuestras necesidades, sin la complejidad completa de Phoenix |
| JSON | **Jason** | Rápido y mantenido activamente, con excelente rendimiento y API simple |
| Testing | **ExUnit** | Incluido en Elixir, proporciona todo lo necesario para pruebas unitarias y de integración |
| gRPC | **GRPC** | Cliente oficial de gRPC para Elixir, con soporte para protobuf |
| Crypto | **:crypto** | Incluido en Erlang/OTP para hashing SHA-256 |
| HTTP Client | **HTTPoison** | Cliente HTTP simple y efectivo para comunicación entre nodos |
| Terminal UI | **IO.ANSI** | Incluido en Elixir, permite formatear la salida en terminal con colores |

### Arquitectura de Aplicación
- **GenServer**: Para manejar el estado del juego y la tabla de jugadores
- **Task**: Para operaciones concurrentes como envío de mensajes a múltiples nodos
- **DynamicSupervisor**: Para supervisar procesos y manejar recuperación ante fallos
- **Application**: Para estructurar correctamente la aplicación Elixir

### Configuración y Estructura del Proyecto
- Utilizar `mix` para estructura y gestión del proyecto
- Organizar el código en módulos bien definidos:
  - `GameState`: Estado del juego
  - `PlayerRegistry`: Tabla de jugadores
  - `NetworkCommunication`: Funciones de comunicación entre nodos
  - `HTTPServer`: Servidor HTTP para recibir peticiones
  - `GRPCLogger`: Cliente gRPC para envío de logs
  - `UI`: Interfaz de usuario en terminal
  - `MessageDistribution`: Implementación del mecanismo "distribuye"

### Validaciones y Manejo de Errores
- Validar todos los datos de entrada y parámetros de configuración
- Manejar adecuadamente los timeouts de comunicación (valores recomendados):
  - Conexiones HTTP: 5 segundos
  - Respuestas del servidor gRPC: 3 segundos
  - Espera para distribución de mensajes: 2 segundos
- Implementar mecanismos de reintentos cuando sea apropiado:
  - Máximo 3 reintentos para comunicaciones críticas
  - Backoff exponencial para evitar saturación
- Proporcionar mensajes de error claros y significativos en la interfaz de usuario
- Registrar todos los errores mediante el servicio gRPC de logs
