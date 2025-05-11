// Servidor gRPC con buffer circular en SQLite
import { config } from 'dotenv'
import grpc from '@grpc/grpc-js'
import protoLoader from '@grpc/proto-loader'
import path from 'path'
import { Database } from 'bun:sqlite'
import os from 'os'
import zlib from 'zlib'

config()
const PORT = process.env.PORT || 50051
const MAX_LOGS = +process.env.MAX_LOGS || 500
const DB_FILE = process.env.DB_FILE || 'logs.db'

// Inicializar base de datos y buffer circular
const db = new Database(DB_FILE)
// db.run(`DROP TABLE IF EXISTS logs;`)
// db.run(`DROP TABLE IF EXISTS buffer_meta;`)
db.run(`CREATE TABLE IF NOT EXISTS logs (
  idx INTEGER PRIMARY KEY,
  timestamp INTEGER,
  id_instancia INTEGER,
  marcador TEXT,
  ip TEXT,
  alias TEXT,
  accion TEXT,
  args TEXT
);`)
db.run(`CREATE TABLE IF NOT EXISTS buffer_meta (key TEXT PRIMARY KEY, value INTEGER);`)
db.run(`CREATE TABLE IF NOT EXISTS enums (hash INTEGER PRIMARY KEY, valor TEXT UNIQUE);`)

// Hash rápido tipo djb2
function fastHash(str) {
  let hash = 5381
  for (let i = 0; i < str.length; ++i) hash = ((hash << 5) + hash) + str.charCodeAt(i)
  return hash >>> 0 // unsigned 32-bit
}

// Eliminar cache en memoria, solo usar la tabla
function getEnumHash(str) {
  const hash = fastHash(str);
  let row = db.query('SELECT valor FROM enums WHERE hash = ?').get(hash);
  if (!row) 
    db.query('INSERT OR IGNORE INTO enums (hash, valor) VALUES (?, ?)').run(hash, str);
  return hash;
}

if (!db.query('SELECT 1 FROM buffer_meta WHERE key = "max_logs"').get()) {
  db.query('INSERT INTO buffer_meta (key, value) VALUES (?, ?)').run('max_logs', MAX_LOGS)
  db.query('INSERT INTO buffer_meta (key, value) VALUES (?, ?)').run('current_position', 0)
}

const maxLogs = db.query("SELECT value FROM buffer_meta WHERE key = 'max_logs'").get().value
let currentPosition = db.query("SELECT value FROM buffer_meta WHERE key = 'current_position'").get().value

if (db.query('SELECT COUNT(*) as count FROM logs').get().count < maxLogs) {
  const stmt = db.prepare('INSERT INTO logs (idx, timestamp, id_instancia, marcador, ip, alias, accion, args) VALUES (?, NULL, NULL, NULL, NULL, NULL, NULL, NULL)')
  for (let i = db.query('SELECT COUNT(*) as count FROM logs').get().count; i < maxLogs; ++i) stmt.run(i + 1)
}

const proto = grpc.loadPackageDefinition(protoLoader.loadSync(path.resolve('proto/log.proto'), {
  keepCase: true, longs: String, enums: String, defaults: true, oneofs: true
})).LogService

const server = new grpc.Server()
server.addService(proto.service, {
  SendLog: (call, cb) => {
    let { timestamp, id_instancia, marcador, ip, alias, accion, args } = call.request;
    const idx = (currentPosition % maxLogs) + 1;
    // Convertir accion y marcador a hash
    const accionHash = getEnumHash(accion);
    const marcadorHash = getEnumHash(marcador);
    db.query('UPDATE logs SET timestamp = ?, id_instancia = ?, marcador = ?, ip = ?, alias = ?, accion = ?, args = ? WHERE idx = ?')
      .run(+timestamp, +id_instancia, marcadorHash, ip, alias, accionHash, args, idx);
    currentPosition = (currentPosition + 1) % maxLogs;
    db.query("UPDATE buffer_meta SET value = ? WHERE key = 'current_position'").run(currentPosition);
    cb(null, { ok: true });
  },
  DumpLogs: call => {
    // Optimización: obtener todos los enums una sola vez
    const enumMap = new Map(db.query('SELECT hash, valor FROM enums').all().map(e => [e.hash, e.valor]))
    db.query('SELECT timestamp, id_instancia, marcador, ip, alias, accion, args FROM logs WHERE id_instancia = ? ORDER BY timestamp ASC')
      .all(+call.request.id_instancia)
      .forEach(row => {
        call.write({
          ...row,
          timestamp: row.timestamp?.toString(),
          id_instancia: row.id_instancia?.toString(),
          accion: enumMap.get(Number(row.accion)) ?? row.accion,
          marcador: enumMap.get(Number(row.marcador)) ?? row.marcador
        })
      })
    call.end()
  }
})

// Colores y utilidades
const color = (t, c) => `\x1b[${c}m${t}\x1b[0m`
const CYAN = '36', YELLOW = '33', GREEN = '32', RED = '31', MAGENTA = '35', BOLD = '1'
let lastResult, serverIp = '', serverPort = PORT

async function saveDump(comprimir = false) {
  // Obtener enums y logs traducidos
  const enumsArr = db.query('SELECT hash, valor FROM enums').all()
  const enumMap = new Map(enumsArr.map(e => [e.hash, e.valor]))
  const rows = db.query('SELECT timestamp, id_instancia, marcador, ip, alias, accion, args FROM logs WHERE id_instancia IS NOT NULL ORDER BY timestamp ASC').all()
  const translatedRows = rows.map(row => ({
    ...row,
    accion: enumMap.get(Number(row.accion)) ?? row.accion,
    marcador: enumMap.get(Number(row.marcador)) ?? row.marcador
  }))
  const fs = require('fs'), path = require('path')
  const dumpsDir = path.join(process.cwd(), 'dumps')
  if (!fs.existsSync(dumpsDir)) fs.mkdirSync(dumpsDir)
  
  // Usamos .gz para gzip que es más compatible
  const ext = comprimir ? 'gz' : 'json'
  const file = path.join(dumpsDir, `dump_buffer_${Date.now()}.json${comprimir ? ".gz":""}`)
  
  try {
    if (comprimir) {
      // Usar zlib.gzipSync para compresión
      const jsonString = JSON.stringify(translatedRows)
      const compressed = zlib.gzipSync(jsonString, { level: 5 })
      fs.writeFileSync(file, compressed)
    } else {
      fs.writeFileSync(file, JSON.stringify(translatedRows, null, 2))
    }
    lastResult = color(`Dump guardado en ${file}`, GREEN)
  } catch (err) {
    lastResult = color(`Error al crear dump: ${err.message}`, RED)
    throw err
  }
}

function showMenu() {
  process.stdout.write('\x1Bc')
  console.log(color(`Servidor gRPC de logs (buffer circular) escuchando en ${serverIp}:${serverPort}`, `${BOLD};${CYAN}`))
  console.log(color('==== Menú del Servidor de Logs ====', `${BOLD};${MAGENTA}`))
  if (lastResult) console.log(lastResult, '\n')
  console.log(color('1. Limpiar base de datos', YELLOW))
  console.log(color('2. Mostrar cantidad de registros', YELLOW))
  console.log(color('3. Dump buffer a JSON bruto', YELLOW))
  console.log(color('4. Mostrar diccionario de enums', YELLOW))
  console.log(color('5. Reiniciar servidor', YELLOW))
  console.log(color('6. Cerrar servidor (sin reinicio)', YELLOW))
  console.log(color('7. Exportar buffer comprimido (zlib)', YELLOW))
  console.log(color('0. Volver', YELLOW))
  process.stdout.write(color('Selecciona una opción: ', CYAN))
}

function handleMenuInput(data) {
  const opt = (data || '').toString().trim()
  if (opt === '1') {
    db.query('UPDATE logs SET timestamp = NULL, id_instancia = NULL, marcador = NULL, ip = NULL, alias = NULL, accion = NULL, args = NULL').run()
    db.query('DELETE FROM enums').run()
    db.query('UPDATE buffer_meta SET value = 0 WHERE key = "current_position"').run()
    currentPosition = 0
    lastResult = color('Base de datos limpiada.', GREEN)
  } else if (opt === '2') {
    lastResult = color(`Cantidad de registros en buffer: ${db.query('SELECT COUNT(*) as c FROM logs WHERE id_instancia IS NOT NULL').get().c}`, GREEN)
  } else if (opt === '3') {
    saveDump(false).then(showMenu).catch(e => { lastResult = color('Error al crear dump: ' + e.message, RED); showMenu() })
    return
  } else if (opt === '4') {
    // Diccionario de enums como tabla simple y corta
    const enums = db.query('SELECT hash, valor FROM enums ORDER BY valor ASC').all()
    if (enums.length) {
      const maxV = Math.max(5, ...enums.map(e => e.valor.length))
      lastResult = [
        color('Valor'.padEnd(maxV) + ' | Hash', CYAN),
        color('-'.repeat(maxV) + '-+-----', CYAN),
        ...enums.map(e => `${e.valor.padEnd(maxV)} | ${e.hash}`)
      ].join('\n')
    } else lastResult = color('Diccionario de enums vacío.', YELLOW)
  } else if (opt === '5') {
    lastResult = color('Reiniciando servidor...', MAGENTA); shutdown(false)
  } else if (opt === '6') {
    lastResult = color('Cerrando servidor (sin reinicio)...', RED); shutdown(true)
  } else if (opt === '7') {
    saveDump(true).then(showMenu).catch(e => { lastResult = color('Error al crear dump: ' + e.message, RED); showMenu() })
    return
  } else if (opt !== '0') {
    lastResult = color('Opción no válida', RED)
  }
  if (!['5', '6'].includes(opt)) setTimeout(showMenu, 0)
}

function setupMenu() {
  process.stdin.setEncoding('utf8')
  if (process.stdin.isTTY) process.stdin.setRawMode(false)
  process.stdin.resume()
  process.stdin.on('data', handleMenuInput)
  process.on('SIGINT', () => shutdown(false))
  process.on('SIGTERM', () => shutdown(false))
  showMenu()
}

function shutdown(noRestart) {
  process.exitCode = noRestart ? 0 : 1
  server.tryShutdown(() => process.exit(process.exitCode))
}

server.bindAsync(`0.0.0.0:${PORT}`, grpc.ServerCredentials.createInsecure(), (err, port) => {
  if (err) return console.error('Error al iniciar servidor gRPC:', err), process.exit(1)
  serverPort = port
  serverIp = Object.values(os.networkInterfaces()).flat().find(i => i.family === 'IPv4' && !i.internal)?.address || 'localhost'
  setupMenu()
})
