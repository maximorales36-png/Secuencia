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
| Detección Python + WebSocket | ✅ COMPLETO | OpenCV detecta 6 colores, servidor WS envía a 10 Hz |
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

## Changelog

### 2026-06-11 — RTPCs N_Green y Pink + calibración interactiva HSV

**`AudioManager.gd`:**
- `RTPC_N_Green` y `RTPC_Pink` ahora se setean suavemente en `_process()`.
- Siguen el mismo patrón que `RTPC_Violet`: escanean la pieza más alta de su color y calculan `(1.0 - highest_y) * 100.0`.
- Smoothing a mitad de velocidad que violeta (`1.0 - exp(-delta * 0.5)` vs `* 1.0`).
- Cuando no hay piezas del color, el RTPC vuelve suavemente a 100 (safe state).

**`secuencia_detector_ipc.py`:**
- Nueva función `calibrate_colors()`: ventana OpenCV con 6 trackbars (H/S/V low/high), selector de color por teclas 1-6, máscara superpuesta en vivo, mini máscara BN, contornos dibujados.
- `save_color_config()` / `load_color_config()`: guardado atómico de rangos HSV a `color_config.json` (mismo patrón que crop).
- Nuevo flag CLI `--calibrate-colors`.
- Tecla `B` en runtime para ingresar a calibración de colores.
- La calibración se hace sobre la imagen warpeada (post-perspectiva), donde corre la detección real.

**`configuracion.txt`:**
- Nuevo archivo instructivo con pasos detallados para calibración de esquinas y colores, consejos prácticos y comandos rápidos.

### 2026-06-04 — Zonas de sector para piezas pink
- **`ScanlineLogic.gd`**: `BEATS_PER_SECTOR` cambiado de `16` a `4`.
- Con `beats_per_cycle = 16` ahora hay **4 zonas** de 4 negras cada una:
  - Zona 1: líneas 1-5 (posición 0.0-0.25)
  - Zona 2: líneas 5-9 (posición 0.25-0.5)
  - Zona 3: líneas 9-13 (posición 0.5-0.75)
  - Zona 4: líneas 13-17 (posición 0.75-1.0)
- El rectángulo pink solo cubre el ancho del sector donde está la pieza (1/4 de pantalla).
- El evento WWise `Play_pink` se dispara al cruzar los bordes de sector: líneas 1, 5, 9, 13.

### 2026-06-05a — neon_green como color sectorial + estabilización de detección
- **`ScanlineLogic.gd`**: `"neon_green"` agregado a `sector_based_colors`. Ahora usa detección sectorial (rectángulo) en vez de cruce por pieza.
- **`EffectsRenderer.gd`**: caso `"neon_green"` en `_draw_sector_rectangles()` con `Color(0.0, 1.0, 0.5)`. Saltado en `_on_crossing_detected()`.
- **Sistema de memoria / estabilización de piezas** (`ScanlineLogic.gd`):
  - `piece_memory` con timeout de 0.35s — si la cámara deja de ver una pieza momentáneamente, se retiene en memoria.
  - `STABILIZE_SNAP = 0.015` — piezas que oscilan ±0.015 en X se agrupan como la misma.
  - `SMOOTHING_FACTOR = 0.35` — posición suavizada con `lerp()` para evitar saltos bruscos.
- **Sector catch-up** (`ScanlineLogic.gd`):
  - `_detect_sector_crossings()` ahora maneja saltos de múltiples sectores (frame drops).
  - `_catch_up_sectors()` corre cada frame como safety net: si un sector ya fue alcanzado por la scanline pero nunca disparó, lo dispara en el próximo frame.

### 2026-06-05b — Sistema de familias: color "celeste" + cooldown por color
- **Nuevo color "celeste"**: misma lógica sectorial que "pink".
  - `ScanlineLogic.gd`: refactor completo del sistema de sectores para ser genérico.
    - `pink_sectors` → `sector_colors` (diccionario `sector → {color: y, ...}` permite múltiples colores por sector).
    - Lista `sector_based_colors = ["pink", "celeste"]` — agregar un color aquí lo trata como color sectorial.
    - Señal `sector_activated` ahora incluye `color: String` como tercer parámetro.
    - Nueva señal `cycle_reset()` se emite cuando la scanline vuelve a 0.
    - Nuevo método `get_sector_duration()` basado en BPM.
  - `EffectsRenderer.gd`:
    - `_draw_pink_rectangles()` → `_draw_sector_rectangles()`: itera sobre todos los colores del sector y dibuja el rectángulo con el color correspondiente.
    - `_on_crossing_detected()` salta todos los colores en `sector_based_colors`.
    - Nueva función `_draw_celeste_effect()` (misma geometría que pink, color celeste).
  - `AudioManager.gd`:
    - `"celeste"` agregado a `valid_colors`.
    - `_on_sector_activated()` recibe el color desde la señal.
- **Cooldown por color**: mismo color no puede sonar dos veces superpuesto; colores diferentes sí.
  - `AudioManager.gd`: nuevo sistema `color_cooldowns`. Cada vez que suena un color, se bloquea por `sector_duration` segundos (~2.76s a 87 BPM).
  - En `cycle_reset()` se limpian todos los cooldowns.
- **Arquitectura extensible**: para agregar una nueva familia sectorial en el futuro, solo hay que:
  1. Agregar el color a `sector_based_colors` en `ScanlineLogic.gd`.
  2. Agregar su color de rectángulo en `_draw_sector_rectangles()` en `EffectsRenderer.gd`.
  3. Agregar su evento Wwise a `valid_colors` en `AudioManager.gd`.

---

### 2026-06-05c — Yellow como instrumento melódico monofónico + sombra conectiva
- **Nuevo comportamiento yellow** (`AudioManager.gd`):
  - Yellow ya no usa `play_sound()` genérico. Manejo especial en `_on_crossing_detected()` → `_handle_yellow()`.
  - **Monofónico**: solo un yellow puede sonar a la vez. Al cruzar el primer yellow se postea `Play_yellow`. Los cruces siguientes solo actualizan el switch sin re-disparar.
  - **Switch de 8 notas** (`yellow_switch`): Y dividido en 8 secciones. Y=1 (abajo) → I, Y=0 (arriba) → VIII.
  - `_on_cycle_reset()` postea `Stop_yellow` si estaba activo.
- **Prioridad en misma X** (`ScanlineLogic.gd`): si dos yellows están en la misma coordenada X, solo se emite crossing para el más alto (menor Y).
- **Nueva función `get_yellow_pieces()`** (`ScanlineLogic.gd`): expone posición de todas las piezas amarillas para el renderer.
- **Sombra amarilla conectiva** (`EffectsRenderer.gd`):
  - Reemplaza el efecto por-pieza de yellow (ahora saltado en `_on_crossing_detected`).
  - **1 pieza**: banda amarilla translúcida que cubre de x=0 a x=viewport.width centrada en la Y de la pieza.
  - **Múltiples piezas**: polígono en forma de cinta ("soga") que conecta todas las piezas amarillas, manteniendo el ancho `rect_height`.
  - Nuevo export: `yellow_shadow_alpha = 0.15`.

---

### 2026-06-13 — Refactor audio Familia 1: Play_all + RTPCs por zona + fix deriva scanline

**`AudioManager.gd`:**
- `Play_all` se dispara una vez en `_ready()` para Familia 1, suena hasta salir del juego. `Stop_all` en `_exit_tree()`.
- Eliminado: `_handle_yellow` (switch de notas), `Play_Yellow`/`Stop_yellow`, `Play_Pink`/`Play_Celeste` one-shots, `Stop_pink`/`Stop_celeste` en cycle_reset.
- Nuevos RTPC:
  - `RTPC_V_Pink` (0-100): snap por zona actual. 100 si la zona tiene piezas pink, 0 si no.
  - `RTPC_V_Celeste` (0-100): snap por zona actual. 100 si la zona tiene piezas celeste, 0 si no.
  - `RTPC_V_Yellow` (0-100): 100 al cruzar yellow (`_on_crossing_detected`), 0 en cycle_reset.
- `_on_sector_activated` saltea pink/celeste en Familia 1 (Play_all los cubre).
- `_on_cycle_reset` solo resetea `RTPC_V_Yellow` a 0.

**`ScanlineLogic.gd`:**
- Fix deriva entre ciclos: `_process` ahora usa `Time.get_ticks_usec()` (tiempo absoluto) en vez de acumular `delta`. `scan_position = float(elapsed_usec % _cycle_usec) / float(_cycle_usec)`. El wrap se detecta comparando `cycle_idx`. Zero acumulación de error.
- Default `beats_per_cycle` cambiado de 32 a 16 (coincide con main.tscn).

---

**Última actualización:** 2026-06-13
**Responsable:** Maximiliano Morales (Maxi)
**Institución:** Universidad Maimónides
**Commit:** `54695d5` — feat: Wwise integration working
