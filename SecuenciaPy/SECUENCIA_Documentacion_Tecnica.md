# SECUENCIA - Documentación Técnica

## Resumen Ejecutivo

**SECUENCIA** es un secuenciador tangible interactivo desarrollado para Universidad Maimónides. Sistema que permite a usuarios posicionar piezas físicas de colores sobre una mesa proyectada. Una línea de barrido vertical se mueve de izquierda a derecha (sincronizada a 120 BPM). Cuando cruza una pieza:
- Dispara un evento de audio en Wwise
- Proyecta efectos visuales reactivos (ondas, partículas, distorsión)
- Modula parámetros de síntesis según posición Y de la pieza

**Stack tecnológico:**
- Python 3.11 + OpenCV + Websockets (detección)
- Godot 4.6 (lógica, visualización, proyección)
- Wwise (síntesis de audio, RTPCs)

---

## Arquitectura General

```
┌─────────────────────────────────────────────────────────────┐
│                    MESA FÍSICA CON PROYECTOR                │
│                    (proyecta línea de barrido + efectos)    │
└──────────────────────────┬──────────────────────────────────┘
                           │ Proyecta sobre
                           │
┌──────────────────────────┴──────────────────────────────────┐
│                      GODOT 4.6                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ WebSocketManager                                     │  │
│  │  • Conecta a ws://localhost:8765                    │  │
│  │  • Recibe piezas (color, x, y) normalizadas [0,1]  │  │
│  │  • Emite signal pieces_updated                      │  │
│  └──────────────────────────────────────────────────────┘  │
│                           │                                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ ScanlineLogic (FASE 3 - a implementar)              │  │
│  │  • Mantiene posición X de línea de barrido          │  │
│  │  • BPM = 120 fijo (luego parametrizable)            │  │
│  │  • Detecta cruces: línea.x == pieza.x               │  │
│  │  • Dispara evento Wwise + RTPC                      │  │
│  └──────────────────────────────────────────────────────┘  │
│                           │                                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ PiecesVisualizer + EffectsRenderer (FASE 3)          │  │
│  │  • Dibuja piezas como círculos de colores           │  │
│  │  • Renderiza efectos visuales (ondas, partículas)   │  │
│  │  • Envía al proyector                                │  │
│  └──────────────────────────────────────────────────────┘  │
│                           │                                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ AudioManager (FASE 4 - a implementar)               │  │
│  │  • Interfaz con Wwise SDK                           │  │
│  │  • Dispara eventos: PostEvent("Play_Yellow")        │  │
│  │  • Asigna RTPs: SetRtpc("Timbre", y_position)       │  │
│  └──────────────────────────────────────────────────────┘  │
└──────────────────────────┬──────────────────────────────────┘
                           │ OSC/eventos audio
                           │
┌──────────────────────────┴──────────────────────────────────┐
│                    WWISE (Audio Engine)                     │
│  • 4 soundbanks: Yellow, Orange, Pink, NeonGreen           │
│  • Síntesis parametrizada (timbre modulado por Y)          │
│  • Reverb/decay/volumen según posición                     │
└─────────────────────────────────────────────────────────────┘


┌──────────────────────────────────────────────────────────────┐
│                   PYTHON (Host)                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ secuencia_detector_ws.py                              │ │
│  │  • OpenCV: captura cámara 640x480                    │ │
│  │  • Detecta postits por HSV (amarillo, naranja,      │ │
│  │    rosa, verde flúor)                                 │ │
│  │  • Normaliza a [0,1] para ambos ejes               │ │
│  │  • WebSocket server en :8765                        │ │
│  │  • Envía 10 Hz: {"piezas": [{"color", "x", "y"}]}  │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

---

## Pasos Realizados (Fase 1-2)

### Fase 1: Conceptualización y Diseño

**Realizado:**
- ✅ Documento conceptual "SECUENCIA" en Canva (minimalista, 1-2 páginas)
- ✅ State of the art: TENORI-ON, Orbita, Perot Museum, Creative Visual Sequencer
- ✅ Definición de MVP: detección postits → eventos Wwise → visualización reactiva
- ✅ Decision: WebSocket (en lugar de OSC) para comunicación Python-Godot
- ✅ Presentación a Alan (director carrera) → aprobación

**Decisiones clave:**
- 4 colores de postits (yellow, orange, pink, neon_green)
- Normalización [0,1] para independencia de resolución
- BPM fijo 120 (luego variable)
- Comunicación desacoplada: Python = detección, Godot = lógica temporal

---

### Fase 2: Python + Detección OpenCV

**Realizado:**
- ✅ `secuencia_detector_ws.py`: script completo con detección + servidor WebSocket
- ✅ Detección HSV de 4 colores (calibrado para postits sobre mesa blanca)
- ✅ Morfología (MORPH_CLOSE + MORPH_OPEN) para limpiar ruido
- ✅ Normalización de coordenadas (cx/width, cy/height)
- ✅ Frecuencia 10 Hz (100ms)
- ✅ Servidor WebSocket en localhost:8765
- ✅ JSON format: `{"piezas": [{"color": "yellow", "x": 0.45, "y": 0.60}, ...]}`
- ✅ Testing real en mesa con postits → detecta bien

**Archivos:**
- `secuencia_detector_ws_FIXED.py` (arreglo: RuntimeError con set iteration)
- `requirements.txt`: opencv-python, websockets, numpy

**Limitaciones conocidas:**
- Rangos HSV pueden necesitar recalibración según iluminación real
- Tamaño mínimo 400px² (para piezas 3D impresas será menor, usar 100px²)

---

### Fase 2.5: Godot 4.6 + WebSocket Client

**Realizado:**
- ✅ `WebSocketManager.gd`: cliente WebSocket nativo (sin plugins)
- ✅ Conecta a ws://localhost:8765
- ✅ Parsea JSON + maneja desconexiones + reintentos (5 intentos máx)
- ✅ Signal `pieces_updated(Array[Piece])` cuando cambian datos
- ✅ Signal `connection_changed(bool)` para UI
- ✅ API: `get_pieces()`, `get_piece_count()`, `get_pieces_by_color(color)`
- ✅ Clase inner `Piece`: {color: String, x: float [0,1], y: float [0,1]}
- ✅ `PiecesVisualizer.gd`: dibuja círculos de colores + etiquetas + estado conexión
- ✅ Testing real → Godot recibe datos en tiempo real correctamente

**Archivos:**
- `WebSocketManager_FIXED.gd` (arreglo: get_text() en lugar de get_message())
- `PiecesVisualizer.gd` (usa WebSocketManager)

**Warnings (no-bloqueantes):**
- SHADOWED_VARIABLE_BASE_CLASS: variable `is_connected` → renombrada a `ws_connected`
- `position` como variable local en loop → usar nombres diferentes en próximas fases

---

## Pasos a Realizar (Fase 3-4)

### Fase 3: Lógica de Barrido + Visualización Reactiva

**Objetivo:** Implementar línea de barrido sincronizada + detección de cruces + efectos visuales

**Tareas:**

#### 3.1 - Script: ScanlineLogic.gd
- Clase nueva: `ScanlineLogic` extends Node
- Variables:
  ```gdscript
  var bpm: float = 120.0
  var scan_position: float = 0.0  # [0, 1]
  var scan_speed: float = 0.0  # píxeles/segundo (derivado de BPM)
  var pieces: Array[WebSocketManager.Piece] = []
  var last_triggered_pieces: Array = []  # para evitar triggers múltiples
  ```
- Métodos:
  - `_ready()`: calcular scan_speed desde BPM
  - `_process(delta)`: actualizar scan_position, detectar cruces
  - `_detect_crossings()`: comparar scan_x con cada pieza.x
  - `_emit_audio_event(piece)`: disparar evento Wwise (integración FASE 4)
  - `get_scan_position()`: retorna [0,1]
  - `set_bpm(new_bpm)`: actualizar velocidad dinámicamente

**Fórmula BPM → velocidad:**
- 1 compás a 120 BPM = 2 segundos
- Si línea barre en 1 compás: velocidad = 1.0 / 2.0 = 0.5 unidades/segundo
- `scan_speed = (bpm / 60.0) / 2.0`

**Detección de cruces:**
- Cada frame, comparar: `abs(scan_position - pieza.x) < tolerance`
- Tolerance: ~0.02 (2% del ancho)
- Guardar `last_triggered` para evitar múltiples triggers en el mismo ciclo
- Reset `last_triggered` cuando scan_position < 0.1 (nuevo ciclo)

---

#### 3.2 - Script: EffectsRenderer.gd
- Clase nueva: `EffectsRenderer` extends Node2D
- Variables:
  ```gdscript
  var scan_position: float = 0.0
  var active_effects: Array = []  # {piece, start_time, effect_type}
  var viewport_size: Vector2
  ```
- Renderizado:
  - Dibujar línea de barrido: vertical en `scan_position * viewport_width`
  - Para cada pieza activa, dibujar efecto según color:
    - **Yellow**: ondas concéntricas amarillas
    - **Orange**: explosión de partículas naranjas
    - **Pink**: distorsión rosa concéntrica
    - **NeonGreen**: radiación verde pulsante

- Métodos:
  - `_draw()`: renderizar línea + efectos
  - `trigger_effect(piece)`: crear efecto nuevo
  - `_update_effects(delta)`: animar efectos existentes (fade out)
  - `_draw_scanline()`: línea blanca vertical
  - `_draw_effect_yellow(center, intensity)`: ondas
  - `_draw_effect_orange(center, intensity)`: partículas
  - `_draw_effect_pink(center, intensity)`: distorsión
  - `_draw_effect_neon_green(center, intensity)`: radiación

**Parámetros de efectos:**
```gdscript
var effect_duration: float = 0.5  # segundos
var max_wave_radius: float = 150.0  # píxeles
var particle_count: int = 20
var distortion_amount: float = 5.0
```

---

#### 3.3 - Integración en Escena

**Estructura:**
```
Main (Node)
├── WebSocketManager (Node)
├── ScanlineLogic (Node)
│   └── Script: ScanlineLogic.gd
├── Canvas (Node2D)
│   ├── PiecesVisualizer (Node2D)
│   │   └── Script: PiecesVisualizer.gd
│   └── EffectsRenderer (Node2D)
│       └── Script: EffectsRenderer.gd
└── AudioManager (Node) [FASE 4]
    └── Script: AudioManager.gd
```

**Conexiones:**
- `WebSocketManager.pieces_updated` → `ScanlineLogic.set_pieces()`
- `ScanlineLogic.crossing_detected` → `EffectsRenderer.trigger_effect()`
- `ScanlineLogic.crossing_detected` → `AudioManager.play_sound()`
- `ScanlineLogic` → `EffectsRenderer._process()` cada frame

---

### Fase 4: Integración Wwise

**Objetivo:** Conectar eventos de barrido con síntesis de audio

**Tareas:**

#### 4.1 - AudioManager.gd (Godot ↔ Wwise)
```gdscript
class_name AudioManager

var initialized: bool = false

func _ready():
    # Cargar Wwise SDK (requiere plugin Wwise para Godot)
    # o usar fallback: llamar ejecutable externo
    pass

func play_sound(color: String, y_position: float):
    # color: "yellow", "orange", "pink", "neon_green"
    # y_position: [0, 1]
    
    # Disparar evento
    var event_name = "Play_%s" % color.capitalize()
    PostEvent(event_name)
    
    # Asignar RTPC (timbre)
    # Asumiendo RTPC "Timbre" en Wwise
    var timbre_value = y_position * 100.0  # [0, 100]
    SetRtpc("Timbre", timbre_value)

func PostEvent(event_name: String):
    # Wrapper para Wwise SDK
    pass

func SetRtpc(rtpc_name: String, value: float):
    # Wrapper para Wwise SDK
    pass
```

#### 4.2 - Configuración Wwise

**Soundbanks necesarios:**
- `Secuencia_Yellow`: síntesis para pieza amarilla
- `Secuencia_Orange`: síntesis para pieza naranja
- `Secuencia_Pink`: síntesis para pieza rosa
- `Secuencia_NeonGreen`: síntesis para pieza verde

**Eventos:**
- `Play_Yellow`
- `Play_Orange`
- `Play_Pink`
- `Play_Neon_Green`

**RTPCs:**
- `Timbre`: [0, 100] modula filtro, pitch, envelope
- `Volume`: [0, 100] volumen según proximidad (future)
- `Duration`: [0, 2] duración del sonido según profundidad (future)

#### 4.3 - Integración ScanlineLogic ↔ AudioManager
```gdscript
# En ScanlineLogic._detect_crossings()
for piece in pieces:
    if piece_is_crossing():
        audio_manager.play_sound(piece.color, piece.y)
        effects_renderer.trigger_effect(piece)
```

---

## Fases Futuras (No MVP)

### Fase 5: Teachable Machine (Reconocimiento de Orientación)
- Entrenar modelo con piezas 3D en diferentes ángulos
- Detectar rotación → modular parámetro adicional (ej: reverb)
- Usar modelo exportado en Python (TensorFlow Lite)

### Fase 6: Parámetros Dinámicos
- UI slider en Godot para cambiar BPM en tiempo real
- UI para seleccionar "modo" de síntesis (sustractivo, FM, granular)
- Guardar/cargar presets

### Fase 7: Multiplayer / Networking
- Varios usuarios en la mesa simultáneamente
- Detectar conflictos (2 piezas en mismo X)
- Síntesis polifónica

### Fase 8: Instalación Museo / Galería
- Configurar proyector + cámara reales
- Calibración de proyección (homografía)
- Interfaz pública (sin teclado, botones físicos)

---

## Dependencias y Setup

### Python
```bash
pip install opencv-python websockets numpy
python secuencia_detector_ws_FIXED.py
```

### Godot 4.6
- **Plugins requeridos:** Ninguno (WebSocket es nativo)
- **Scripts a copiar:**
  - `WebSocketManager_FIXED.gd`
  - `PiecesVisualizer.gd`
  - `ScanlineLogic.gd` (FASE 3)
  - `EffectsRenderer.gd` (FASE 3)
  - `AudioManager.gd` (FASE 4)

### Wwise
- Proyecto Wwise con soundbanks configurados
- Integración SDK en Godot (plugin existente o bridge externo)

---

## Timeline Estimado

| Fase | Descripción | Duración | Estado |
|------|-------------|----------|--------|
| 1 | Conceptualización | 1 semana | ✅ COMPLETO |
| 2 | Python + Godot websocket | 1-2 semanas | ✅ COMPLETO |
| 3 | Barrido + visualización | 2-3 semanas | ⏳ EN PROGRESO |
| 4 | Wwise integration | 1-2 semanas | ⏳ PENDIENTE |
| 5+ | Extras (Teachable, UI, etc) | 2+ semanas | ⏳ FUTURO |

**MVP funcional estimado:** 4-5 semanas (Fases 1-4)

---

## Consideraciones Técnicas

### Performance
- WebSocket 10 Hz es suficiente (bajo overhead)
- Godot render a 60 FPS sin problemas (canvas2d simple)
- Python OpenCV real-time en CPU (optimizado con NumPy)

### Escalabilidad
- Máximo 20-30 piezas simultáneas (antes de lag visual)
- Para más, usar GPU acceleration en OpenCV

### Calibración
- Rangos HSV varían por iluminación → script picker incluido
- Tamaño mínimo detectado: 400px² (ajustable)
- Proyector: requiere homografía si no está perpendicular

### Robustez
- Reintentos conexión WebSocket: 5 intentos
- Timeout desconexión: automático
- Manejo de clientes múltiples (future)

---

## Archivos Entregables

**Python:**
- `secuencia_detector_ws_FIXED.py` ✅
- `requirements.txt` ✅
- `README_WEBSOCKET.md` ✅

**Godot:**
- `WebSocketManager_FIXED.gd` ✅
- `PiecesVisualizer.gd` ✅
- `ScanlineLogic.gd` (FASE 3)
- `EffectsRenderer.gd` (FASE 3)
- `AudioManager.gd` (FASE 4)

**Documentación:**
- `README_WEBSOCKET.md` ✅
- `SECUENCIA_Proyecto.pdf` (diseño Canva) ✅

---

**Última actualización:** 2026-05-22
**Responsable:** Maximiliano Morales (Maxi)
**Institución:** Universidad Maimónides
