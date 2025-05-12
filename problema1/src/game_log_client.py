import grpc
import time
import threading
import json
from proto import log_pb2, log_pb2_grpc

class LogClient:
    def __init__(self, server_addr, id_instancia=1):
        self.server_addr = server_addr
        self.id_instancia = id_instancia
        self.lock = threading.Lock()
        self._connect()

    def _connect(self):
        try:
            self.channel = grpc.insecure_channel(self.server_addr)
            self.stub = log_pb2_grpc.LogServiceStub(self.channel)
        except Exception as e:
            print(f"[gRPC] Error conectando a servidor de logs: {e}")
            self.channel = None
            self.stub = None

    def send_log(self, marcador, ip, alias, accion, args, retries=3):
        entry = log_pb2.LogEntry(
            timestamp=int(time.time() * 1000),
            id_instancia=self.id_instancia,
            marcador=marcador,
            ip=ip,
            alias=alias,
            accion=accion,
            args=json.dumps(args) if not isinstance(args, str) else args
        )
        def _send():
            for attempt in range(retries):
                try:
                    print(f"[gRPC] Enviando log al servidor central: {entry}")
                    response = self.stub.SendLog(entry)
                    print(f"[gRPC] Log aceptado por el servidor central: {entry}")
                    return True
                except Exception as e:
                    print(f"[gRPC] Error enviando log (intento {attempt+1}): {e}")
                    self._connect()
            print("[gRPC] No se pudo enviar el log tras reintentos.")
            return False
        threading.Thread(target=_send, daemon=True).start()
