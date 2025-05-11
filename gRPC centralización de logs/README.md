# gRPC Log Server (Bun/Node/SQLite)

Servidor de logs distribuido, concurrente y persistente, usando gRPC, Bun/Node.js y SQLite, con buffer circular y compresión eficiente de datos.

## ¿Qué hace este proyecto?
- Recibe logs vía gRPC desde múltiples clientes concurrentes.
- Almacena los logs en un buffer circular persistente sobre SQLite.
- Usa enums dinámicos para los campos `accion` y `marcador` (hash + diccionario).
- Comprime el campo `args` usando zstd (Bun) para máxima eficiencia de espacio.
- Provee un menú interactivo en consola para administración, exportación y monitoreo.
- Exportación de logs a formato JSON plano y comprimido (zlib).

## Estructura principal
- **src/log_node.js**: Servidor gRPC, buffer circular, enums, menú interactivo, lógica de compresión y dumps.
- **src/client.js**: Cliente de ejemplo para enviar logs y consultar dumps.
- **proto/log.proto**: Definición del servicio y mensajes gRPC.
- **dumps/**: Carpeta donde se guardan los dumps/exportaciones de logs.
- **logs.db**: Base de datos SQLite persistente.

## Dependencias
- [Bun](https://bun.sh/) (runtime principal, incluye zstd nativo)
- [@grpc/grpc-js](https://www.npmjs.com/package/@grpc/grpc-js)
- [@grpc/proto-loader](https://www.npmjs.com/package/@grpc/proto-loader)
- [dotenv](https://www.npmjs.com/package/dotenv)
- [zlib](https://www.npmjs.com/package/zlib) (para compresión de dumps)
- SQLite (a través de bun:sqlite)

## Cómo ejecutar
1. **Instala Bun** (https://bun.sh/docs/installation)
2. Instala dependencias:
   ```sh
   bun install
   ```
3. Inicia el servidor de logs:
   ```sh
   bun run src/log_node.js
   # o usando el script
   bun run start-node
   ```
4. Ejecuta el cliente de ejemplo:
   ```sh
   bun run src/client.js
   # o usando el script
   bun run client
   ```
5. Usa el menú interactivo en consola para administrar, exportar y monitorear el buffer de logs.

## Menú interactivo del servidor
- Limpiar base de datos (buffer y enums)
- Mostrar cantidad de registros
- Dump/exportar logs a archivo JSON (descomprime y traduce enums)
- Mostrar diccionario de enums (hash <-> string)
- Reiniciar/cerrar servidor
- Exportar buffer comprimido con zlib (.gz)

## ¿Cómo funciona cada parte de log_node.js?
- **gRPC Server**: Expone métodos para recibir logs (`SendLog`) y exportar logs (`DumpLogs`).
- **Buffer circular**: El buffer tiene tamaño fijo (`MAX_LOGS`), y los logs nuevos sobrescriben los más antiguos.
- **Enums dinámicos**: Los valores string de `accion` y `marcador` se almacenan como hash (djb2) y se mantienen en una tabla `enums` para traducción rápida.
- **Compresión zstd**: El campo `args` se almacena comprimido (binario) usando zstd de Bun, ahorrando espacio. Al exportar/dumpear, se descomprime automáticamente.
- **Menú interactivo**: Permite limpiar, exportar, ver enums y controlar el servidor desde la consola.
- **Dump comprimido**: Utiliza zlib (gzip) para comprimir el dump de datos y guardarlo con extensión `.json.gz`.

## Formatos de entrada/salida

### Entrada (desde clientes gRPC)
- Los clientes envían logs estructurados vía gRPC con campos como `timestamp`, `id_instancia`, `marcador`, etc.
- Los campos `accion` y `marcador` se transforman en hashes y se almacenan en la tabla de enums.
- El archivo proto detalla la estructura:
```c#
   message LogEntry {
      int64 timestamp = 1;
      int32 id_instancia = 2;
      string marcador = 3;
      string ip = 4;
      string alias = 5;
      string accion = 6;
      string args = 7;
   }
```

### Salida (dumps y exportaciones)
- **JSON (opción 3)**: Archivo JSON legible con indentación, donde los enums son traducidos a sus valores originales.
- **JSON comprimido (opción 7)**: El mismo contenido JSON pero comprimido con zlib (gzip) para ahorro de espacio. Esta debe ser la opción defecto para exportar.

## Notas técnicas
- El sistema es altamente concurrente y persistente.
- El dump/exportación traduce los enums a string y descomprime `args` para máxima legibilidad.
- El código es compatible con Bun y Node.js.
- La compresión utiliza zlib (nivel 5) por su compatibilidad multiplataforma, especialmente con Windows.

---

**Autor:** [Benjamín Enrique Parra Barbet]

