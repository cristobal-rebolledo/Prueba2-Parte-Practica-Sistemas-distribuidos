# Script para enviar logs constantemente al servidor (PowerShell)
# Para probar alta carga (simulando 600 peticiones en paralelo)

1..600 | ForEach-Object -Parallel {
    bun run src/client.js
}
