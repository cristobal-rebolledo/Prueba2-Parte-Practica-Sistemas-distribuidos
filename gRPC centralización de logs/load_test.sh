#!/bin/sh
# Script para enviar logs constantemente al servidor
# Para probar alta carga (simulando 5k+ peticiones por segundo)

# Requiere bun y el cliente de grpc funcional
bun run src/client.js &
bun run src/client.js &
bun run src/client.js &
bun run src/client.js &
bun run src/client.js &
