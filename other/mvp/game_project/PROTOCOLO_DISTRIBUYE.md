# Protocolo "Distribuye" - Implementación Correcta

## Principios del Protocolo

El protocolo "distribuye" es el mecanismo central de comunicación entre nodos en este juego distribuido y se basa en los siguientes principios:

1. **Envío Único**: Un mensaje debe ser procesado exactamente una vez en cada nodo.
2. **Representantes de Equipo**: Se selecciona un miembro aleatorio de cada equipo como representante.
3. **Mensajes Marcados**: Los mensajes se marcan con una cabecera especial (`@distribute_flag`) para control del flujo.
4. **Procesamiento Local vs Remoto**: Los nodos siguen reglas específicas para procesar mensajes según su origen.

## Implementación Correcta

Para implementar correctamente el protocolo "distribuye", seguimos estas pautas:

### 1. Para Unirse a la Red

Cuando un nodo solicita unirse a la red (`/join`):
- El servidor NO agrega directamente al jugador a su registro local
- El servidor envía un mensaje con `join_network: true` usando el protocolo distribuye
- Este mensaje es procesado por representantes y distribuido a todos los nodos
- Todos los nodos (incluido el originador) reciben el mensaje y procesan la adición del jugador

### 2. Para Unirse a un Equipo

Cuando un jugador solicita unirse a un equipo:
- El nodo NO actualiza directamente su registro local
- El nodo envía un mensaje `player_joined_team` usando el protocolo distribuye
- Este mensaje es procesado por representantes y distribuido a todos los nodos
- Todos los nodos (incluido el originador) reciben el mensaje y procesan el cambio de equipo

### 3. Procesamiento de Mensajes Distribuye

Cuando un nodo recibe un mensaje distribuye:
- Si es representante:
  1. Procesa el mensaje localmente
  2. Reenvía el mensaje a todos los miembros del equipo (sin la cabecera `@distribute_flag`)
- Si es destinatario final:
  1. Procesa el mensaje directamente sin redistribuir

## Ventajas de Esta Implementación

1. **Simplicidad**: El código es más limpio y sigue un patrón consistente
2. **Unicidad**: Los mensajes se procesan exactamente una vez en cada nodo
3. **Consistencia**: Todos los nodos mantienen estados consistentes
4. **Escalabilidad**: El protocolo es eficiente y escala bien con el número de nodos

## Errores Comunes a Evitar

1. **Procesamiento Duplicado**: Actualizar localmente y luego enviar/recibir el mismo mensaje por distribuye
2. **Lógica de Caché Innecesaria**: Implementar sistema de caché de mensajes cuando el protocolo ya evita duplicación
3. **Procesamiento Asimétrico**: Tratar de manera diferente al nodo originador y los demás nodos

## Reglas de Oro

- El nodo originador NUNCA procesa directamente un mensaje que también enviará por distribuye
- Todos los cambios de estado deben llegar a través del protocolo distribuye
- Cada representante procesa localmente Y distribuye a su equipo
- Los miembros del equipo solo procesan, sin redistribuir
