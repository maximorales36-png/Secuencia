# SECUENCIA - WebSocket Setup

Comunicación bidireccional entre Python (detector de postits) y Godot 4 (visualización y lógica) vía WebSocket.

## Instalación

### Python

```bash
pip install -r requirements.txt
```

Dependencias:
- `opencv-python` - Detección de video
- `websockets` - Cliente/servidor WebSocket
- `numpy` - Cálculos numéricos

### Godot 4

**No necesita plugins externos.** Godot 4 tiene WebSocket nativo en `WebSocketPeer`.

## Estructura

```
secuencia/
├── Python/
│   ├── secuencia_detector_ws.py    # Detecta piezas, servidor WebSocket
│   └── requirements.txt             # Dependencias Python
│
└── Godot/
    ├── scripts/
    │   ├── WebSocketManager.gd      # Conecta a WebSocket, gestiona piezas
    │   └── PiecesVisualizer.gd      # Dibuja las piezas en pantalla
    └── project.godot
```

## Cómo usar

### 1. Setup de Godot

Abre Godot 4 y crea una escena simple:

```
Main (Node)
├── WebSocketManager (Node)
│   └── Script: WebSocketManager.gd
│
└── Canvas (Node2D)
    └── PiecesVisualizer (Node2D)
        └── Script: PiecesVisualizer.gd
```

Guarda la escena como `main.tscn`.

### 2. Ejecutar Python

En una terminal:

```bash
cd secuencia/Python
python secuencia_detector_ws.py
```

Deberías ver:

```
[SECUENCIA] Iniciando detector de postits (WebSocket)...
Resolución: 640x480
WebSocket: ws://localhost:8765
Frecuencia envío: 10 Hz
----
[WebSocket] Servidor escuchando en ws://localhost:8765
[Video] Iniciando captura...
```

### 3. Ejecutar Godot

En Godot, presiona **F5** o **Play**.

Deberías ver:

```
[WebSocketManager] Inicializando...
[WebSocketManager] Intentando conectar a ws://localhost:8765 (intento 1/5)...
[PiecesVisualizer] Inicializando...
[WebSocketManager] Conectado a servidor
```

En la pantalla:

- Rectángulo verde arriba a la izquierda: "WebSocket: CONECTADO"
- Contador de piezas
- Círculos de colores donde están las piezas detectadas

## Protocolo WebSocket

### Python → Godot

Cada 100ms, Python envía:

```json
{
  "piezas": [
    {"color": "yellow", "x": 0.45, "y": 0.60},
    {"color": "pink", "x": 0.80, "y": 0.35}
  ]
}
```

### Godot → Python (opcional)

Godot puede enviar comandos a Python (implementar según necesidad):

```gdscript
websocket_manager.send_message("comando")
```

## API de WebSocketManager

### Propiedades

```gdscript
var pieces: Array[Piece]           # Piezas detectadas actualmente
var is_connected: bool              # ¿Conectado a Python?
```

### Métodos

```gdscript
get_pieces() -> Array[Piece]
# Retorna todas las piezas

get_piece_count() -> int
# Retorna cantidad de piezas

get_pieces_by_color(color: String) -> Array[Piece]
# Retorna piezas de un color específico

send_message(message: String) -> void
# Envía un mensaje a Python (si está conectado)

close_connection() -> void
# Cierra la conexión WebSocket
```

### Signals

```gdscript
pieces_updated.emit(new_pieces: Array[Piece])
# Se emite cuando cambian las piezas

connection_changed.emit(connected: bool)
# Se emite cuando cambia el estado de conexión
```

### Estructura Piece

```gdscript
class Piece:
    var color: String  # "yellow", "orange", "pink", "neon_green"
    var x: float       # [0, 1] posición horizontal
    var y: float       # [0, 1] posición vertical
```

## Ejemplo de uso

```gdscript
extends Node

var websocket_manager: WebSocketManager

func _ready():
    websocket_manager = get_tree().root.find_child("WebSocketManager", true, false)
    websocket_manager.pieces_updated.connect(_on_pieces_updated)
    websocket_manager.connection_changed.connect(_on_connection_changed)

func _on_pieces_updated(pieces):
    print("Piezas actualizadas:")
    for piece in pieces:
        print("  %s en (%.2f, %.2f)" % [piece.color, piece.x, piece.y])

func _on_connection_changed(connected):
    if connected:
        print("Conectado a Python")
    else:
        print("Desconectado de Python")

func _process(_delta):
    var yellow_pieces = websocket_manager.get_pieces_by_color("yellow")
    if yellow_pieces.size() > 0:
        var first_yellow = yellow_pieces[0]
        print("Primera pieza amarilla: (%.2f, %.2f)" % [first_yellow.x, first_yellow.y])
```

## Troubleshooting

### "Esperando conexión..." en Godot

Python no está ejecutándose o no está escuchando en `ws://localhost:8765`.

Solución:
1. Verifica que Python esté corriendo
2. Verifica que no hay otro programa usando puerto 8765
3. En Python, busca: `[WebSocket] Servidor escuchando en ws://localhost:8765`

### "No se reciben piezas" en Godot

Python está corriendo pero no detecta postits.

Solución:
1. Verifica que los postits estén bien iluminados
2. En Python, verifica que aparezca en consola: `Enviado: X piezas`
3. Los rangos HSV pueden necesitar calibración (edita `COLOR_RANGES` en Python)

### Error: "Address already in use" en Python

El puerto 8765 ya está en uso.

Solución:
1. Cambia el puerto en `secuencia_detector_ws.py`:
   ```python
   WEBSOCKET_PORT = 8766  # o cualquier otro puerto libre
   ```
2. Cambia el mismo puerto en `WebSocketManager.gd`:
   ```gdscript
   const WEBSOCKET_URL = "ws://localhost:8766"
   ```

### La cámara no abre

Verifica que:
1. La cámara esté conectada
2. No esté en uso por otra aplicación
3. En Linux: `sudo chmod 666 /dev/video0`

## Próximos pasos

1. **Lógica de barrido**: Crear una línea que se mueve de izq a der (basada en BPM)
2. **Detección de cruces**: Cuando la línea cruza una pieza, disparar evento
3. **Efectos visuales**: Ondas expansivas, partículas, distorsión
4. **Integración Wwise**: Conectar eventos a síntesis de audio

---

**SECUENCIA - Universidad Maimónides**
