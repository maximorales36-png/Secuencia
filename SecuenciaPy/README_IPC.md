# SECUENCIA - IPC por Archivo Compartido

Comunicación entre Python (detector de postits) y Godot 4 **sin usar la red**.
No depende de WiFi, TCP/IP ni WebSocket.

## Problema original

WebSocket usa localhost (127.0.0.1), que depende del stack TCP/IP. Al desconectar el WiFi,
Windows a veces reconfigura la pila de red y el loopback deja de funcionar, cortando la
comunicación aunque todo esté en la misma máquina.

## Solución: archivo JSON compartido

Python escribe las detecciones a un archivo JSON en `%TEMP%`, Godot lo lee haciendo polling.
No hay red involucrada — solo lectura/escritura de archivos local.

```
┌──────────────┐     escribe     ┌──────────────────┐     lee (polling)     ┌──────────────┐
│  Python      │ ──────────────> │  %TEMP%          │ <────────────────── │  Godot       │
│  OpenCV      │   atómicamente  │  secuencia_      │   cada frame        │  IPCManager  │
│  Detección   │   .tmp → .json  │  pieces.json     │                     │  Señales     │
└──────────────┘                 └──────────────────┘                     └──────────────┘
```

## Archivos creados/modificados

### Python

**`secuencia_detector_ipc.py`** — Nuevo. Detective de postits con salida a archivo.
- Sin `websockets`, sin `asyncio`
- Escribe JSON atómicamente (archivo temporal + `shutil.move`)
- Usa `cv2.CAP_DSHOW` en Windows para evitar cuelgues
- Acepta índice de cámara como argumento: `python secuencia_detector_ipc.py 1`

### Godot

**`scipts/IPCManager.gd`** — Nuevo. Reemplaza a `WebSocketManager.gd`.
- Lee el archivo JSON compartido cada frame
- Emite las mismas señales (`pieces_updated`, `connection_changed`)
- Misma clase `Piece` con `color`, `x`, `y`
- Timeout: 2s sin actualización = desconectado

**`project.godot`** — Modificado. `IPCManager` agregado como autoload (singleton).

### Scripts modificados

| Script | Cambio |
|--------|--------|
| `ScanlineLogic.gd` | `WebSocketManager` → `IPCManager`. Referencia directa al singleton |
| `PiecesVisualizer.gd` | `WebSocketManager` → `IPCManager`. Referencia directa al singleton |
| `EffectsRenderer.gd` | Tipo de parámetro: `WebSocketManager.Piece` → `IPCManager.Piece` |
| `AudioManager.gd` | Tipo de parámetro: `WebSocketManager.Piece` → `IPCManager.Piece` |

**Ninguna señal cambió** — todos los scripts que escuchaban `pieces_updated` o
`connection_changed` siguen funcionando sin modificaciones en su lógica interna.

## Cómo usar

### 1. Instalar dependencias

```bash
pip install -r requirements_ipc.txt
```

### 2. Ejecutar Python

```bash
python secuencia_detector_ipc.py            # auto-detect + crop guardado
python secuencia_detector_ipc.py 1          # forzar cámara índice 1
python secuencia_detector_ipc.py --calibrate  # forzar calibración de recorte
```

Vas a ver:

```
[SECUENCIA] Iniciando detector de postits (IPC por archivo)
Resolución: 640x480
Archivo IPC: C:\Users\maxim\AppData\Local\Temp\secuencia_pieces.json
Frecuencia envío: 10 Hz
------------------------------------------------------------
[Video] Probando cámara en índice 0... ¡ENCONTRADA!
```

## Sistema de Corrección de Perspectiva (Esquinas)

La cámara está angulada respecto al televisor → la pantalla se ve
como un trapecio en el frame. En lugar de un recorte rectangular,
el usuario **marca las 4 esquinas del TV** y Python aplica una
**transformación de perspectiva** para rectificar la imagen.

Esto asegura que las coordenadas 0–1 enviadas a Godot se correspondan
exactamente con los bordes de la pantalla, aunque la cámara esté
en ángulo.

### Archivo `crop_config.json`

Se guarda automáticamente junto al script:

```json
{
  "order": ["tl", "tr", "br", "bl"],
  "corners": [
    {"x": 0.10, "y": 0.15},
    {"x": 0.88, "y": 0.12},
    {"x": 0.92, "y": 0.85},
    {"x": 0.08, "y": 0.88}
  ]
}
```

Los valores son fracciones del frame de cámara (0.0–1.0).
Orden: Top-Left, Top-Right, Bottom-Right, Bottom-Left (sentido horario).

### Calibración interactiva (click en esquinas)

Al ejecutar por primera vez sin `crop_config.json`, o al usar `--calibrate`:

1. Se abre el feed de cámara con instrucciones
2. **Click izquierdo** en cada esquina del TV en orden: TL → TR → BR → BL
3. Cada esquina se marca con un círculo de color y su etiqueta (TL, TR, BR, BL)
4. El área fuera del polígono se oscurece automáticamente
5. Al marcar la 4ª esquina, aparece un **preview rectificado** (esquina inferior derecha)
   mostrando cómo quedaría la imagen enderezada
6. Teclas:
   - `C` — Guardar y continuar
   - `R` — Resetear todas las esquinas
   - `U` — Deshacer la última esquina
   - `Q` — Cancelar

En ejecución normal:
- `C` — Re-calibrar en vivo
- `V` — Alternar entre vista rectificada y vista raw (con overlay de esquinas)

### Pipeline de transformación

```
  ┌──── Frame cámara (640×480) ────┐
  │  •  TL━━━━━━━━━━━━━━━━━TR  •   │  4 clicks del usuario
  │   ╱                         ╲   │  → getPerspectiveTransform
  │  •  │    POSTIT            │  • │  → warpPerspective
  │   ╲                         ╱   │
  │  •  BL━━━━━━━━━━━━━━━━━BR  •   │
  └─────────────────────────────────┘
                   ↓
  ┌─── Rectificado (640×480) ──────┐
  │  ┌──────────────────────────┐  │  Imagen enderezada
  │  │                          │  │
  │  │       POSTIT             │  │  Detección OpenCV aquí
  │  │       (x=0.45, y=0.60)   │  │  → normalizado 0-1
  │  │                          │  │
  │  └──────────────────────────┘  │
  └────────────────────────────────┘
                   ↓
        Godot recibe (x=0.45, y=0.60)
        → mapea directo a la pantalla completa
```

### Ventajas sobre el recorte rectangular

| Aspecto | Rectángulo fijo | 4 esquinas + perspectiva |
|---------|----------------|--------------------------|
| Ángulo de cámara | Solo perpendicular | Cualquier ángulo |
| Esquinas de pantalla | Se pierden si angulada | Perfectamente alineadas |
| Calibración | Trackbars (4 valores) | 4 clicks visuales |
| Precisión | Aproximada | Exacta (mapeo homográfico) |

### 3. Ejecutar Godot

Presioná **F5** en Godot. `IPCManager` (autoload) empieza a leer el archivo
y emitir señales. No necesitas agregar ningún nodo en la escena.

## API de IPCManager

### Propiedades

```gdscript
var pieces: Array[Piece]      # Piezas detectadas actualmente
var connected: bool            # ¿Archivo actualizándose? (timeout 2s)
```

### Métodos

```gdscript
get_pieces() -> Array[Piece]
# Retorna todas las piezas

get_piece_count() -> int
# Retorna cantidad de piezas

get_pieces_by_color(color: String) -> Array[Piece]
# Retorna piezas de un color específico
```

### Signals

```gdscript
pieces_updated.emit(new_pieces: Array[Piece])
# Se emite cuando cambian las piezas (cada ~100ms)

connection_changed.emit(connected: bool)
# Se emite cuando el archivo deja de actualizarse (>2s)
```

### Estructura Piece

```gdscript
class Piece:
    var color: String   # "yellow", "orange", "pink", "neon_green", "celeste", "violet"
    var x: float        # [0, 1] posición horizontal normalizada
    var y: float        # [0, 1] posición vertical normalizada
```

## Protocolo

Python escribe al archivo `%TEMP%/secuencia_pieces.json`:

```json
{
  "piezas": [
    {"color": "yellow", "x": 0.45, "y": 0.60},
    {"color": "pink", "x": 0.80, "y": 0.35}
  ]
}
```

Escritura atómica: Python escribe a `secuencia_pieces.tmp`, hace `fsync()`,
y renombra a `secuencia_pieces.json`. Godot nunca lee un archivo a medias.

## Troubleshooting

### La cámara no se detecta o el script se cuelga

```bash
taskkill /F /IM python.exe 2>nul
python secuencia_detector_ipc.py 1
```

Problemas comunes:
1. **Proceso Python zombi** — el `taskkill` libera la cámara
2. **Índice incorrecto** — probá con 0, 1, 2, 3
3. **DirectShow no soporta índices** — el script usa `cv2.CAP_DSHOW` (más rápido)
4. **Cámara ocupada por otra app** — cerrá Zoom, Chrome, OBS, etc.

### Godot no recibe datos

1. Verificá que Python esté corriendo (ventana del detector abierta)
2. Verificá que el archivo exista: `%TEMP%\secuencia_pieces.json`
3. Si el archivo no se actualiza, hay un error en Python

### Error `r != len` en IPCManager

Condición de carrera entre Python escribiendo y Godot leyendo.
Ya manejado: `IPCManager` lee con `get_buffer()` para evitar el problema.

### Quiero volver a WebSocket

1. En `project.godot`, comentá o borrá la línea del autoload de `IPCManager`
2. Agregá `WebSocketManager` como nodo en tu escena principal
3. Ejecutá `python secuencia_detector_ws.py` en lugar del script IPC

## Detección vs WebSocket vs IPC

| Aspecto | WebSocket | IPC (archivo) |
|---------|-----------|---------------|
| Dependencia de red | Sí (localhost) | No |
| Funciona sin WiFi | A veces | Siempre |
| Setup | Servidor + cliente | Solo escribir/leer archivo |
| Dependencias Python | `websockets` | Ninguna extra |
| Latencia | ~1ms | ~16ms (polling frames) |
| Complejidad | Media | Baja |

## Cambios realizados (10/06/2026)

- Creación de `secuencia_detector_ipc.py` (Python IPC)
- Creación de `IPCManager.gd` (Godot IPC)
- Modificación de `project.godot` (autoload)
- Migración de `ScanlineLogic.gd`, `PiecesVisualizer.gd`, `EffectsRenderer.gd`,
  `AudioManager.gd` de `WebSocketManager` → `IPCManager`
- Agregado de `requirements_ipc.txt`
- Agregado de soporte para argumento CLI de cámara
- Agregado de backend DirectShow/MSMF para evitar cuelgues en Windows
- Lectura robusta con `get_buffer()` para evitar race conditions
- **Sistema de corrección de perspectiva por esquinas**:
  - Click en las 4 esquinas del TV para calibrar (TL→TR→BR→BL)
  - Transformación de perspectiva (`getPerspectiveTransform` + `warpPerspective`)
  - Preview en vivo del rectificado durante la calibración
  - Overlay que oscurece el área fuera del polígono
  - Vista RAW toggleable con `V` para ver el frame original con overlay
  - Persistencia en `crop_config.json` (escritura atómica)
  - Atajos: `C` guardar, `R` reset, `U` undo, `Q` cancelar
- **Variable `ani_contraste`** en `EffectsRenderer.gd` que multiplica la opacidad
  de todos los efectos (ondas, estelas, patrones, sectores, línea de barrido)

---

**SECUENCIA - Universidad Maimónides**
