// Cliente gRPC de ejemplo para enviar logs al servidor
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';
import path from 'path';
import { config } from 'dotenv';

config(); // Cargar variables de entorno
const PORT = process.env.PORT || 50051;

// Cargar definiciones proto con opciones para enteros largos
const packageDef = protoLoader.loadSync(path.resolve('proto/log.proto'), {
  keepCase: true,
  longs: String, // Manejar int64 como String
  enums: String,
  defaults: true,
  oneofs: true
});
const proto = grpc.loadPackageDefinition(packageDef).LogService;

// Crear cliente gRPC
const client = new proto('localhost:' + PORT, grpc.credentials.createInsecure());

// Enviar un log de prueba
const log = {
  id_instancia: 'test-instance-1',
  hora: Date.now().toString(), // Enviar como string para int64
  accion: 'prueba-cliente'
};

client.SendLog(log, (err, response) => {
  if (err) {
    console.error('Error:', err);
    return;
  }
  // Imprimir la respuesta exactamente como la manda el servidor
  console.log('Log enviado:', JSON.stringify(response, null, 2));

  // Solicitar un dump de prueba
  const dumpStream = client.DumpLogs({ id_instancia: log.id_instancia });
  dumpStream.on('data', data => {
    // Imprimir cada log recibido exactamente como lo manda el servidor
    console.log(JSON.stringify(data, null, 2));
  });
  dumpStream.on('end', () => {
    console.log('Dump completado');
    process.exit(0);
  });
});
