# Script para enviar logs constantemente al servidor (PowerShell)
# Para probar alta carga (simulando 5k+ peticiones por segundo)

# Ejecutar múltiples instancias del cliente en paralelo
1..10 | ForEach-Object -Parallel {
    bun run src/client.js
}
