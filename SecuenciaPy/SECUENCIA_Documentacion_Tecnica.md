# SECUENCIA - Documentación Técnica

## Resumen Ejecutivo

**SECUENCIA** es un secuenciador tangible interactivo desarrollado para Universidad Maimónides. El sistema permite a usuarios posicionar piezas físicas de colores (post-its) sobre una mesa proyectada. Una línea de barrido vertical se mueve de izquierda a derecha sincronizada a 120 BPM. Cuando cruza una pieza:
- Dispara un evento de audio en Wwise
- Proyecta efectos visuales reactivos (ondas, partículas, distorsión)
- Modula parámetros de síntesis (timbre) según la posición Y de la pieza

**Stack tecnológico:**
- **Python 3.11** + OpenCV + WebSockets → detección visual de post-its
- **Godot 4.6** → lógica de barrido, visualización, efectos y proyección
- **Wwise 2025.1.3** → síntesis de audio, RTPCs, soundbanks

**Repositorio:** `github.com/maximorales36-png/Secuencia.git`

---

## Estado Actual del Proyecto

| Componente | Estado | Detalle |
|---|---|---|
| Detección Python + WebSocket | ✅ COMPLETO | OpenCV detecta 4 colores, servidor WS envía a 10 Hz |
| Cliente WebSocket Godot | ✅ COMPLETO | `WebSocketManager.gd` con reconexión automática |
| Scanline Logic | ✅ COMPLETO | Barrido sincronizado a BPM, detección de cruces |
| Efectos Visuales | ✅ COMPLETO | `EffectsRenderer.gd` con ondas, partículas, distorsión |
| Audio Wwise | ✅ COMPLETO | `AudioManager.gd` con Wwise SDK integrado |
| Proyecto Wwise | ✅ COMPLETO | 4 eventos, RTPC Timbre, soundbanks generados |
| Fases futuras (5-8) | ⏳ PENDIENTE | Teachable Machine, parámetros dinámicos, multiplayer |

```
► Sistema completamente funcional. MVP listo.
```

---

## Arquitectura General

```
┌─────────────────────────────────────────────────────────────┐
│                    MESA FÍSICA CON PROYECTOR                │
│                    (proyecta línea de barrido + efectos)    │
└──────────────────────────┬──────────────────────────────────┘
                           │ Proyector (salida visual)
                           │ Cámara (entrada detección)
                           ▼
┌──────────────────────────────────────────────────────────────┐
│                        PYTHON (Host)                         │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ secuencia_detector_ws.py                              │ │
│  │  • OpenCV: captura cámara 640x480                    │ │
│  │  • Detecta post-its por HSV (4 colores)              │ │
│  │  • Normaliza coordenadas a [0, 1]                    │ │
│  │  • WebSocket server en ws://localhost:8765            │ │
│  │  • Envía 10 Hz: {"piezas": [...]}                    │ │
│  └──────────────────────┬─────────────────────────────────┘ │
└─────────────────────────┼───────────────────────────────────┘
                          │ WebSocket JSON
                          ▼
┌──────────────────────────────────────────────────────────────┐
│                      GODOT 4.6                               │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ WebSocketManager.gd                                  │   │
│  │  • Cliente WebSocket nativo (WebSocketPeer)          │   │
│  │  • Conecta a ws://localhost:8765                     │   │
│  │  • Reintentos automáticos (5 intentos)               │   │
│  │  • Signal: pieces_updated(pieces), connection_changed │   │
│  └────────────────────────┬─────────────────────────────┘   │
│                           │ pieces                           │
│  ┌────────────────────────┴─────────────────────────────┐   │
│  │ ScanlineLogic.gd                                     │   │
│  │  • Barrido vertical izquierda → derecha              │   │
│  │  • Sincronizado a BPM (120)                          │   │
│  │  • Detecta cruces línea ↔ pieza                      │   │
│  │  • Signal: crossing_detected(piece)                  │   │
│  └──────────┬──────────────────────────┬────────────────┘   │
│             │ crossing_detected        │ crossing_detected   │
│  ┌──────────┴─────────────┐  ┌────────┴──────────────┐      │
│  │ EffectsRenderer.gd     │  │ AudioManager.gd       │      │
│  │  • Línea de barrido    │  │  • register_game_obj  │      │
│  │  • Ondas (yellow)      │  │  • load_bank("Main")  │      │
│  │  • Partículas (orange) │  │  • post_event("Play_")│      │
│  │  • Distorsión (pink)   │  │  • set_rtpc_value()   │      │
│  │  • Radiación (neon)    │  └────────┬──────────────┘      │
│  └────────────────────────┘           │                      │
└───────────────────────────────────────┼──────────────────────┘
                                        │ Wwise API
                                        ▼
┌──────────────────────────────────────────────────────────────┐
│                    WWISE (Audio Engine)                      │
│  • Soundbank "Main" con 4 eventos:                          │
│    - Play_Yellow, Play_Orange, Play_Pink, Play_Neon_Green   │
│  • RTPC "Timbre" [0-100] modulado por posición Y            │
│  • Síntesis parametrizada por color                          │
│  • Soundbanks generados para Windows y Linux                 │
└──────────────────────────────────────────────────────────────┘
```

---

## Componentes Detallados

### 1. Python — Detección Visual (`SecuenciaPy/secuencia_detector_ws.py`)

Servidor WebSocket que captura video de cámara, detecta post-its de 4 colores y envía coordenadas normalizadas.

**Detección HSV (calibrada para post-its sobre mesa blanca):**
| Color | Hue Range | Sat Range | Val Range |
|---|---|---|---|
| Yellow | 20-35 | 100-255 | 100-255 |
| Orange | 5-18 | 100-255 | 100-255 |
| Pink | 140-170 | 50-255 | 100-255 |
| Neon Green | 40-80 | 100-255 | 100-255 |

**Pipeline:**
1. Captura frame 640×480
2. Convertir a HSV
3. Máscara por rango de color
4. Morfología (MORPH_CLOSE + MORPH_OPEN) para limpiar ruido
5. FindContours + filtro de área mínima (400px²)
6. Calcular centroide (cx, cy)
7. Normalizar a [0, 1]: `x = cx/width`, `y = cy/height`
8. Enviar JSON por WebSocket: `{"piezas": [{"color": "yellow", "x": 0.45, "y": 0.60}]}`

**Frecuencia de envío:** 10 Hz (100ms por frame)

**Dependencias:** `opencv-python`, `websockets`, `numpy`

---

### 2. Godot — WebSocket Manager (`SecuenciaGod/scipts/WebSocketManager.gd`)

Cliente WebSocket nativo de Godot 4 (sin plugins externos).

| Propiedad | Tipo | Descripción |
|---|---|---|
| `pieces` | `Array[Piece]` | Piezas detectadas actualmente |
| `ws_connected` | `bool` | Estado de conexión |
| `WEBSOCKET_URL` | `const` | `ws://localhost:8765` |
| `MAX_RETRIES` | `const` | 5 |

| Signal | Parámetros |
|---|---|
| `pieces_updated` | `new_pieces: Array[Piece]` |
| `connection_changed` | `connected: bool` |

| Método | Descripción |
|---|---|
| `get_pieces()` | Retorna todas las piezas |
| `get_piece_count()` | Cantidad de piezas |
| `get_pieces_by_color(color)` | Filtra por color |
| `send_message(msg)` | Envía comando a Python |
| `close_connection()` | Cierra WebSocket |

**Clase Piece:**
```gdscript
class Piece:
    var color: String   # "yellow", "orange", "pink", "neon_green"
    var x: float        # [0, 1]
    var y: float        # [0, 1]
```

---

### 3. Godot — Scanline Logic (`SecuenciaGod/scipts/ScanlineLogic.gd`)

Gestiona la línea de barrido vertical sincronizada a BPM y detecta cruces con piezas.

**Parámetros:**
- `BPM = 120` (fijo, futuro parametrizable)
- Barrido: izquierda (x=0) → derecha (x=1)
- 1 ciclo completo = 2 segundos (a 120 BPM)
- `scan_speed = (bpm / 60.0) / 2.0`

**Detección de cruces:**
- Por frame compara `abs(scan_x - piece.x) < TOLERANCE` (tolerance ≈ 0.02)
- Evita triggers múltiples con `last_triggered` tracking por ciclo
- Reset al reiniciar ciclo (scan_x < 0.1)

**Signal emitida:** `crossing_detected(piece: WebSocketManager.Piece)`

---

### 4. Godot — Effects Renderer (`SecuenciaGod/scipts/EffectsRenderer.gd`)

Renderiza la línea de barrido y efectos visuales reactivos en un Node2D.

**Efectos por color:**
| Color | Efecto |
|---|---|
| Yellow | Ondas concéntricas amarillas |
| Orange | Explosión de partículas naranjas |
| Pink | Distorsión rosa concéntrica |
| Neon Green | Radiación verde pulsante |

**Parámetros:**
- `effect_duration = 0.5s`
- `max_wave_radius = 150px`
- `particle_count = 20`

**Conectado a:** `ScanlineLogic.crossing_detected`

---

### 5. Godot — Audio Manager (`SecuenciaGod/scipts/AudioManager.gd`)

Interfaz entre Godot y Wwise SDK para reproducción de audio.

**Inicialización en `_ready()`:**
```gdscript
Wwise.register_game_obj(self, "AudioManager")
Wwise.load_bank("Main")
Wwise.add_default_listener(self)
```

**Flujo de reproducción:**
1. Recibe `crossing_detected(piece)` desde `ScanlineLogic`
2. Mapea color a evento: `Play_Yellow`, `Play_Orange`, `Play_Pink`, `Play_Neon_Green`
3. Calcula RTPC: `Timbre = y * 100.0` (0-100)
4. Ejecuta: `Wwise.post_event(event_name, self)`
5. Modula: `Wwise.set_rtpc_value("Timbre", rtpc_value, self)`

**Validaciones:**
- Solo colores válidos: yellow, orange, pink, neon_green
- `y_position` clampeda a [0, 1]
- Manejo especial para `neon_green` → `Neon_Green`

---

### 6. Wwise — Proyecto de Audio (`SecuenciaWwi/SecuenciaV2.wproj`)

**Soundbanks generados:**
- Windows: `SecuenciaWwi/GeneratedSoundBanks/Windows/`
- Linux: `SecuenciaWwi/GeneratedSoundBanks/Linux/`

**Estructura:**
```
SoundBank: Main
├── Play_Yellow     → Síntesis amarilla
├── Play_Orange     → Síntesis naranja
├── Play_Pink       → Síntesis rosa
└── Play_Neon_Green → Síntesis verde

RTPC: Timbre [0-100]
├── Modula filtro, pitch y envelope
└── Controlado por posición Y de la pieza
```

**Integración Godot:**
- Plugin Wwise Godot (autoload "Wwise")
- DLL nativa: `SecuenciaGod/addons/Wwise/native/lib/win64/editor/profile/~libwwise.windows.editor.profile.dll`
- Soundbanks copiados a: `SecuenciaGod/Wwise/Soundbanks/`

---

## Estructura del Repositorio

```
SecuenciaFull/
├── SecuenciaPy/                          # Python - detección visual
│   ├── secuencia_detector_ws.py          # Servidor WebSocket + OpenCV
│   ├── requirements.txt                  # Dependencias Python
│   ├── README_WEBSOCKET.md               # Guía de conexión WS
│   ├── SECUENCIA_Documentacion_Tecnica.md # Este documento
│   └── venv/                             # Entorno virtual Python
│
├── SecuenciaGod/                         # Godot 4.6 - lógica y visualización
│   ├── project.godot                     # Proyecto Godot
│   ├── main.tscn                         # Escena principal
│   ├── scipts/                           # Scripts GDScript
│   │   ├── WebSocketManager.gd           # Cliente WebSocket
│   │   ├── PiecesVisualizer.gd           # Visualización de piezas
│   │   ├── ScanlineLogic.gd              # Lógica de barrido
│   │   ├── EffectsRenderer.gd            # Efectos visuales
│   │   └── AudioManager.gd              # Audio Wwise
│   ├── addons/Wwise/                     # Plugin Wwise Godot
│   ├── Wwise/Soundbanks/                 # Soundbanks generados
│   └── .godot/                           # Cache Godot
│
└── SecuenciaWwi/                         # Proyecto Wwise
    ├── SecuenciaV2.wproj                 # Proyecto Wwise
    ├── Events/                           # Eventos Wwise
    ├── Containers/                       # Contenedores de sonido
    ├── GeneratedSoundBanks/              # Soundbanks compilados
    │   ├── Windows/
    │   └── Linux/
    ├── Originals/SFX/                    # Archivos de audio fuente
    ├── SoundBanks/                       # Config soundbanks
    └── ...
```

---

## Cómo Ejecutar

### 1. Iniciar Python (detección)
```bash
cd SecuenciaPy
python secuencia_detector_ws.py
```
Esperar: `[WebSocket] Servidor escuchando en ws://localhost:8765`

### 2. Iniciar Godot
Abrir `SecuenciaGod/project.godot` y presionar **F5** (Play).

### 3. Flujo esperado en consola de Godot
```
WwiseGodot: Sound engine initialized successfully.
[WebSocketManager] Inicializando...
[WebSocketManager] Intentando conectar a ws://localhost:8765...
[PiecesVisualizer] Inicializando...
[WebSocketManager] Conectado a servidor
[ScanlineLogic] CRUCE: yellow en x=0.44, y=0.55 (ciclo 43.6%)
[AudioManager] Sound triggered: Play_Yellow (y=0.55, timbre=55.0)
[EffectsRenderer] Efecto disparado: yellow en (0.44, 0.55)
```

---

## Timeline del Proyecto

| Fase | Descripción | Duración | Estado |
|------|-------------|----------|--------|
| 1 | Conceptualización y diseño | 1 semana | ✅ COMPLETO |
| 2 | Python + WebSocket + Godot client | 1-2 semanas | ✅ COMPLETO |
| 3 | Barrido + visualización + efectos | 2-3 semanas | ✅ COMPLETO |
| 4 | Integración Wwise | 1-2 semanas | ✅ COMPLETO |
| 5 | Teachable Machine (orientación) | — | ⏳ FUTURO |
| 6 | Parámetros dinámicos (UI BPM, modos) | — | ⏳ FUTURO |
| 7 | Multiplayer / networking | — | ⏳ FUTURO |
| 8 | Instalación museo (calibración, homografía) | — | ⏳ FUTURO |

**MVP funcional:** ✅ COMPLETO (Fases 1-4)

---

## Decisiones Técnicas

| Decisión | Opción Elegida | Alternativa |
|---|---|---|
| Comunicación Python↔Godot | WebSocket | OSC, pipes, shared memory |
| Frecuencia detección | 10 Hz (100ms) | 30 Hz, 5 Hz |
| Sistema de audio | Wwise SDK Godot plugin | OSC a Wwise externo, FMOD |
| Normalización | Coordenadas [0, 1] | Píxeles absolutos |
| BPM | 120 fijo | Variable por UI |
| Efectos visuales | Node2D `_draw()` | GPUParticles, shaders |

---

## Próximos Pasos (Post-MVP)

### Fase 5: Teachable Machine
- Entrenar modelo con piezas 3D impresas
- Detectar rotación → modular parámetro adicional (reverb, filtro)
- TensorFlow Lite en Python

### Fase 6: Parámetros Dinámicos
- Slider BPM en tiempo real
- Selector de modo de síntesis (sustractivo, FM, granular)
- Guardar/cargar presets

### Fase 7: Multiplayer
- Múltiples usuarios simultáneos
- Síntesis polifónica

### Fase 8: Instalación
- Calibración proyector-cámara (homografía)
- Interfaz pública touchless

---

## Consideraciones Técnicas

### Performance
- WebSocket 10 Hz: ~2KB/s de datos — overhead mínimo
- Godot render 60 FPS sin problemas (canvas2d)
- OpenCV en CPU tiempo real con 640×480

### Robustez
- Reconexión automática WebSocket (5 intentos)
- Validación de colores en AudioManager
- Clampeo de valores RTPC

### Calibración
- Rangos HSV dependientes de iluminación ambiental
- Área mínima de detección: 400px² (ajustable)
- Para proyector no perpendicular: requiere homografía

---

## Archivos Clave

| Archivo | Ruta | Rol |
|---|---|---|
| `secuencia_detector_ws.py` | `SecuenciaPy/` | Detección + servidor WS |
| `WebSocketManager.gd` | `SecuenciaGod/scipts/` | Cliente WebSocket |
| `ScanlineLogic.gd` | `SecuenciaGod/scipts/` | Lógica barrido + cruces |
| `EffectsRenderer.gd` | `SecuenciaGod/scipts/` | Efectos visuales |
| `AudioManager.gd` | `SecuenciaGod/scipts/` | Audio Wwise |
| `SecuenciaV2.wproj` | `SecuenciaWwi/` | Proyecto Wwise |
| `main.tscn` | `SecuenciaGod/` | Escena principal Godot |

---

**Última actualización:** 2026-05-23
**Responsable:** Maximiliano Morales (Maxi)
**Institución:** Universidad Maimónides
**Commit:** `54695d5` — feat: Wwise integration working
