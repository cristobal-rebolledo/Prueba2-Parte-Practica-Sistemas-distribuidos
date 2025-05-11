// Cliente gRPC de ejemplo para enviar logs al servidor
import grpc from '@grpc/grpc-js'
import protoLoader from '@grpc/proto-loader'
import path from 'path'
import { config } from 'dotenv'

config(); // Cargar variables de entorno
const PORT = process.env.PORT || 50051

// Cargar definiciones proto con opciones para enteros largos
const packageDef = protoLoader.loadSync(path.resolve('proto/log.proto'), {
  keepCase: true,
  longs: String, // Manejar int64 como String
  enums: String,
  defaults: true,
  oneofs: true
})
const proto = grpc.loadPackageDefinition(packageDef).LogService

// Crear cliente gRPC
const client = new proto('localhost:' + PORT, grpc.credentials.createInsecure())

// Enviar un log de prueba con los campos correctos
const log_list = [{
  timestamp: Date.now(), // INT
  id_instancia: 1,      // INT
  marcador: 'INICIO',   // INICIO/FIN
  ip: '127.0.0.1:3031',      // STR
  alias: 'usuario1',    // STR
  accion: 'ACCION_X',   // ENUM (como string)
  args: JSON.stringify({ foo: 'bar', n: 42 }) // JSON stringificado
},
{  timestamp: Date.now(), // INT
  id_instancia: 3,      // INT
  marcador: 'FIN',   // INICIO/FIN
  ip: '127.0.0.1:3031',      // STR
  alias: 'benrrix',    // STR
  accion: 'ACCION_X',   // ENUM (como string)
  args: JSON.stringify({ foo: 'aaa', n: 42 })},
{  timestamp: Date.now(), // INT
  id_instancia: 1,      // INT
  marcador: 'NA',   // INICIO/FIN
  ip: '127.0.0.1:3030',      // STR
  alias: 'caro',    // STR
  accion: 'INICIAR_PARTIDA',   // ENUM (como string)
  args: JSON.stringify({ foo: 'eee', n: 42 })},
{  timestamp: Date.now(), // INT
  id_instancia: 2,      // INT
  marcador: 'NA',   // INICIO/FIN
  ip: '127.0.0.1:3030',      // STR
  alias: 'user',    // STR
  accion: 'TERMINAR_PARTIDA',   // ENUM (como string)
  args: JSON.stringify({ foo: 'iii', n: 42 })}
]

const log = log_list[~~(log_list.length * Math.random())]


client.SendLog(log, (err, response) => {
  if (err) {
    console.error('Error:', err)
    return
  }
  console.log('Log enviado:', JSON.stringify(response, null, 2))

  /* Descomentar para hacer dump de logs
  // Solicitar un dump de prueba usando el campo correcto
  const dumpStream = client.DumpLogs({ id_instancia: log.id_instancia });
  dumpStream.on('data', data => console.log(JSON.stringify(data, null, 2)))
  dumpStream.on('end', () => {
    console.log('Dump completado')
    process.exit(0)
  })
  */
});
