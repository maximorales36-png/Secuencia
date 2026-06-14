# Cambios

## 2026-06-13 — Refactor audio Familia 1 + optimización rendimiento

### Motivación
Eliminar overlapping de eventos pink/celeste que se cortaban entre sí al dispararse por sector. Simplificar la lógica de audio usando un solo evento continuo con RTPCs por pieza/zona. Mejorar fluidez del scanline.

### `AudioManager.gd`

#### Play_all continuo
- **`Play_all`**: se dispara una vez en `_ready()` para Familia 1, suena hasta salir del juego. `Stop_all` en `_exit_tree()`.
- **Eliminado**: `_handle_yellow` (switch de notas), `Play_Yellow`/`Stop_yellow`, `Play_Pink`/`Play_Celeste` one-shots, `Stop_pink`/`Stop_celeste` en cycle_reset.
- `_on_sector_activated` saltea pink/celeste en Familia 1 (Play_all los cubre).

#### RTPCs por zona (pink, celeste)
- **`RTPC_V_Pink`** (0-100): 100 si la zona actual tiene piezas pink. Look-ahead 100ms.
- **`RTPC_V_Celeste`** (0-100): 100 si la zona actual tiene piezas celeste. Look-ahead 100ms.
- Ambos con `_ramp()` lineal 100ms (`RTPC_RAMP_SPEED = 1000.0`).

#### RTPC_V_Yellow (crossing-based)
- Ahora es **crossing-based**: `_yellow_v_target = 100.0` en `_on_crossing_detected`, `_yellow_v_target = 0.0` en `cycle_reset`.
- Rampa lineal 100ms via `_update_yellow_rtpc(delta)` en `_process()`.
- Ya no está en `_update_presence_rtpcs` (se quitó el loop por zona).

#### Yellow_switch re-agregado
- Al cruzar un yellow en Familia 1, se setea `yellow_switch` según la altura: `(1 - y) * 8` → 0=I (abajo), 7=VIII (arriba).
- `Wwise.set_switch("yellow_switch", switch_names[yellow_switch], self)` en `_on_crossing_detected`.

#### RTPC_N_Green y RTPC_Pink por pieza (no continuos)
- Ya no se setean en `_process()`.
- Se setean en `_play_sound()` al postear cada evento: `(1 - y_position) * 100`.
- 4 piezas neon_green → 4 valores diferentes de `RTPC_N_Green`.
- Eliminados: `_green_current`, `_green_target`, `_pink_current`, `_pink_target`, `_update_green_rtpc()`, `_update_pink_rtpc()`.

#### Fix: RTPC_Pink no funcionaba en Familia 1
- `_on_sector_activated` retornaba early para pink en Familia 1 → `_play_sound` nunca se llamaba → `RTPC_Pink` nunca se setea.
- Se movió `Wwise.set_rtpc_value(PINK_RTPC_NAME, ...)` a `_on_sector_activated` antes del early return.

#### Fix: neon_green solo se disparaba una vez por ciclo
- `_sector_colors_triggered` usaba el color como key → solo el primer sector con neon_green disparaba.
- Cambiado a key `str(sector) + "_" + color`.

### `ScanlineLogic.gd`
- **Fix deriva entre ciclos**: `_process` usa `Time.get_ticks_usec()` (tiempo absoluto). `scan_position = float(elapsed_usec % _cycle_usec) / float(_cycle_usec)`. Wrap detectado por `cycle_idx`.
- **Fix wrap**: `scan_position -= 1.0` en vez de `= 0.0`.
- Default `beats_per_cycle` cambiado de 32 a 16.

### `EffectsRenderer.gd` — optimización rendimiento scanline
- **`max_trails = 6`**: estelas viejas se descartan si se supera el límite, evitando acumulación.
- **`_dynamic_spacing`**: el espaciado de puntos aumenta con la cantidad de estelas activas (`pattern_spacing + trail_count × dynamic_spacing_weight`, capped a ×3). Con pocas estelas = detalle completo, con muchas = menor carga.
- **`pattern_spacing` → `_dynamic_spacing`** en `_draw_circular_trail()` y `_draw_sector_trail()`.
- Nuevos exports: `max_trails`, `dynamic_spacing_weight` (ajustables desde inspector).

### Archivos modificados
- `SecuenciaGod/scipts/AudioManager.gd`
- `SecuenciaGod/scipts/ScanlineLogic.gd`
- `SecuenciaGod/scipts/EffectsRenderer.gd`
