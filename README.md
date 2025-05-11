# Prueba2-Parte-Practica-Sistemas-distribuidos
Este proyecto implementa un sistema P2P (peer-to-peer) para un juego de dados con equipos y gestión de peers en Elixir.

## Descripción
El Sistema P2P de Dados permite a múltiples usuarios conectarse en una red descentralizada para jugar dados en equipos.
### Cada usuario puede:
Crear una red o unirse a una existente
Seleccionar un equipo
Participar en el juego
La aplicación mantiene sincronizadas las listas de peers y equipos entre todos los nodos conectados.

## Requisitos previos
Elixir 1.13 o superior

Erlang OTP 24 o superior

Mix (incluido con Elixir)

## Instalación
### 1. Instalar Elixir y Erlang
Windows:

macOS:
Usar Homebrew:

Linux (Ubuntu/Debian):
Seguir instrucciones oficiales o instalar mediante apt.

### 2. Clonar el repositorio

git clone https://github.com/tu-usuario/sistema-p2p-dados.git

### 3. Instalar las dependencias 
mix deps.get
#### Ejecución
Para ejecutar la aplicación usar el siguiente comando en directorio prueba2

mix run --no-halt

#### Tecnologías utilizadas
Elixir/OTP: Lenguaje y plataforma base

GenServer: Para gestión de estado y comportamiento

Plug/Cowboy: API HTTP para comunicación entre nodos

Jason: Codificación/decodificación de JSON

HTTPoison: Cliente HTTP para comunicación entre nodos

Dotenv: Gestión de variables de entorno

### Configuración
Puedes modificar opciones a través de variables de entorno en un archivo .env.

MAX_ALIAS_LENGTH=15  # Longitud máxima del nombre de usuario
