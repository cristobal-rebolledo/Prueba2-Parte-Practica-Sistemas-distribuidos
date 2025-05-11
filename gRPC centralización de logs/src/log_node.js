// Servidor gRPC con buffer circular en SQLite
import { config } from 'dotenv'
import grpc from '@grpc/grpc-js'
import protoLoader from '@grpc/proto-loader'
import path from 'path'
import { Database } from 'bun:sqlite'
import os from 'os'

config()
const PORT = process.env.PORT || 50051
const MAX_LOGS = +process.env.MAX_LOGS || 500
const DB_FILE = process.env.DB_FILE || 'logs.db'

// Inicializar base de datos y buffer circular
const db = new Database(DB_FILE)
db.run(`CREATE TABLE IF NOT EXISTS logs (idx INTEGER PRIMARY KEY, id_instancia TEXT, hora INTEGER, accion TEXT);`)
db.run(`CREATE TABLE IF NOT EXISTS buffer_meta (key TEXT PRIMARY KEY, value INTEGER);`)

if (!db.query('SELECT 1 FROM buffer_meta WHERE key = "max_logs"').get()) {
  db.query('INSERT INTO buffer_meta (key, value) VALUES (?, ?)').run('max_logs', MAX_LOGS)
  db.query('INSERT INTO buffer_meta (key, value) VALUES (?, ?)').run('current_position', 0)
}

const maxLogs = db.query("SELECT value FROM buffer_meta WHERE key = 'max_logs'").get().value
let currentPosition = db.query("SELECT value FROM buffer_meta WHERE key = 'current_position'").get().value

if (db.query('SELECT COUNT(*) as count FROM logs').get().count < maxLogs) {
  const stmt = db.prepare('INSERT INTO logs (idx, id_instancia, hora, accion) VALUES (?, NULL, 0, NULL)')
  for (let i = db.query('SELECT COUNT(*) as count FROM logs').get().count; i < maxLogs; ++i) stmt.run(i + 1)
}

const proto = grpc.loadPackageDefinition(protoLoader.loadSync(path.resolve('proto/log.proto'), {
  keepCase: true, longs: String, enums: String, defaults: true, oneofs: true
})).LogService

const server = new grpc.Server()
server.addService(proto.service, {
  SendLog: (call, cb) => {
    const { id_instancia, hora, accion } = call.request
    const idx = (currentPosition % maxLogs) + 1
    db.query('UPDATE logs SET id_instancia = ?, hora = ?, accion = ? WHERE idx = ?').run(id_instancia, +hora, accion, idx)
    currentPosition = (currentPosition + 1) % maxLogs
    db.query("UPDATE buffer_meta SET value = ? WHERE key = 'current_position'").run(currentPosition)
    cb(null, { ok: true })
  },
  DumpLogs: call => {
    db.query('SELECT id_instancia, hora, accion FROM logs WHERE id_instancia = ? ORDER BY hora ASC')
      .all(call.request.id_instancia)
      .forEach(row => call.write({ ...row, hora: row.hora.toString() }))
    call.end()
  }
})

// Colores y utilidades
const color = (t, c) => `\x1b[${c}m${t}\x1b[0m`
const CYAN = '36', YELLOW = '33', GREEN = '32', RED = '31', MAGENTA = '35', BOLD = '1'
let lastResult, serverIp = '', serverPort = PORT

function showMenu() {
  process.stdout.write('\x1Bc')
  console.log(color(`Servidor gRPC de logs (buffer circular) escuchando en ${serverIp}:${serverPort}`, `${BOLD};${CYAN}`))
  console.log(color('==== Menú del Servidor de Logs ====', `${BOLD};${MAGENTA}`))
  if (lastResult) console.log(lastResult, '\n')
  console.log(color('1. Limpiar base de datos', YELLOW))
  console.log(color('2. Mostrar cantidad de registros', YELLOW))
  console.log(color('3. Dump buffer a archivo', YELLOW))
  console.log(color('4. Reiniciar servidor', YELLOW))
  console.log(color('5. Cerrar servidor (sin reinicio)', YELLOW))
  console.log(color('0. Volver', YELLOW))
  process.stdout.write(color('Selecciona una opción: ', CYAN))
}

function handleMenuInput(data) {
  const opt = (data || '').toString().trim()
  if (opt === '1') {
    db.query('UPDATE logs SET id_instancia = NULL, hora = 0, accion = NULL').run()
    db.query('UPDATE buffer_meta SET value = 0 WHERE key = "current_position"').run()
    currentPosition = 0
    lastResult = color('Base de datos limpiada.', GREEN)
  } else if (opt === '2') {
    lastResult = color(`Cantidad de registros en buffer: ${db.query('SELECT COUNT(*) as c FROM logs WHERE id_instancia IS NOT NULL').get().c}`, GREEN)
  } else if (opt === '3') {
    try {
      const rows = db.query('SELECT * FROM logs WHERE id_instancia IS NOT NULL ORDER BY hora ASC').all()
      const fs = require('fs')
      const file = `dump_buffer_${Date.now()}.json`
      fs.writeFileSync(file, JSON.stringify(rows, null, 2))
      lastResult = color(`Dump guardado en ${file}`, GREEN)
    } catch (e) {
      lastResult = color('Error al crear dump: ' + e.message, RED)
    }
  } else if (opt === '4') {
    lastResult = color('Reiniciando servidor...', MAGENTA); shutdown(false)
  } else if (opt === '5') {
    lastResult = color('Cerrando servidor (sin reinicio)...', RED); shutdown(true)
  } else if (opt !== '0') {
    lastResult = color('Opción no válida', RED)
  }
  if (!['4', '5'].includes(opt)) setTimeout(showMenu, 0)
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
