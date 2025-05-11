import { spawn } from 'child_process';
import path from 'path';

let shutdownRequested = false;

function start() {
  console.log('Iniciando servidor log_node.js...');
  const proc = spawn('bun', ['run', path.join('src', 'log_node.js')], { 
    stdio: 'inherit',
    env: { ...process.env }
  });
  
  proc.on('exit', (code) => {
    if (shutdownRequested) {
      console.log('Supervisor cerrándose por solicitud...');
      return;
    }
    
    if (code === 0) {
      console.log('El servidor se cerró limpiamente - NO reiniciando');
      process.exit(0);
    } else {
      console.log(`log_node.js terminó con código ${code || 0}, reiniciando en 1 segundo...`);
      setTimeout(start, 1000);
    }
  });
  
  return proc;
}

const serverProcess = start();

process.on('SIGINT', () => {
  console.log('Señal de terminación recibida, deteniendo supervisor...');
  shutdownRequested = true;
  if (serverProcess) serverProcess.kill();
  process.exit(0);
});

process.on('SIGTERM', () => {
  console.log('Señal de terminación recibida, deteniendo supervisor...');
  shutdownRequested = true;
  if (serverProcess) serverProcess.kill();
  process.exit(0);
});
