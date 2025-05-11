import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';
import path from 'path';
import { config } from 'dotenv';

config();

const PORT = process.env.PORT || 50051;

// Cargar definiciones proto
const packageDef = protoLoader.loadSync(path.resolve('proto/log.proto'), {
  keepCase: true,
  longs: String, // Manejar int64 como String
  enums: String,
  defaults: true,
  oneofs: true
});
const proto = grpc.loadPackageDefinition(packageDef).LogService;
const client = new proto('localhost:' + PORT, grpc.credentials.createInsecure());

// Crea y envía logs de prueba en bucle para test de carga
async function sendTestLogs(numLogs = 1000) {
  for (let i = 0; i < numLogs; i++) {
    const log = {
      id_instancia: `stress-test-${Math.floor(Math.random() * 10)}`, // 10 instancias distintas
      hora: Date.now().toString(),
      accion: `accion-${i}`
    };

    await new Promise((resolve, reject) => {
      client.SendLog(log, (err, response) => {
        if (err) {
          console.error('Error:', err);
          reject(err);
          return;
        }
        resolve(response);
      });
    });
    
    if (i % 100 === 0) {
      console.log(`Enviados ${i} logs`);
    }
  }
  console.log('Test de carga completado');
}

// Ejecutar prueba de carga
sendTestLogs(5000).catch(console.error);
