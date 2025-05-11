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
1. Instalar Elixir y Erlang
### Windows:

macOS:
Usar Homebrew:

Linux (Ubuntu/Debian):
Seguir instrucciones oficiales o instalar mediante apt.

2. Clonar el repositorio
sh
Copiar
Edita
git clone https://github.com/tu-usuario/sistema-p2p-dados.git
cd sistema-p2p-dados
3. Instalar las dependencias
sh
Copiar
Editar
mix deps.get
🚀 Ejecución
Para iniciar la aplicación:

sh
Copiar
Editar
mix run --no-halt
Este comando compila la aplicación y la mantiene en ejecución, lo cual es necesario para que la red P2P funcione continuamente.

🛠️ Tecnologías utilizadas
Elixir/OTP: Lenguaje y plataforma base

GenServer: Para gestión de estado y comportamiento

Plug/Cowboy: API HTTP para comunicación entre nodos

Jason: Codificación/decodificación de JSON

HTTPoison: Cliente HTTP para comunicación entre nodos

Dotenv: Gestión de variables de entorno

🧭 Flujo de uso
Al iniciar, se pedirá un nombre de usuario

Selecciona crear una nueva red o unirse a una existente

Si creas, configura equipos y contraseña (opcional)

Si te unes, introduce la dirección IP de un peer existente

Usa el menú para:

Tirar dados

Ver peers

Unirte a equipos

Y más...

🗂️ Estructura del proyecto
application.ex: Punto de entrada de la aplicación

p2p_network.ex: Gestión de la red P2P

team_manager.ex: Administración de equipos

user_interface.ex: Interfaz de usuario en consola

api_router.ex: API HTTP para comunicación entre nodos

user_interface_display.ex: Componente de visualización

lib/user_interface_helpers.ex: Funciones auxiliares para la UI

⚙️ Configuración
Puedes modificar opciones a través de variables de entorno en un archivo .env.
