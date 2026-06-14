# Cambios

## 2026-06-13 — Refactor audio Familia 1: Play_all + RTPCs por zona + bugs

### Motivación
Eliminar overlapping de eventos pink/celeste que se cortaban entre sí al dispararse por sector. Simplificar la lógica de audio usando un solo evento continuo.

### Cambios en `AudioManager.gd`

#### Play_all continuo
- **`Play_all`**: se dispara una vez en `_ready()` para Familia 1, suena hasta salir del juego. `Stop_all` en `_exit_tree()`.
- **Eliminado**: `_handle_yellow` (switch de notas), `Play_Yellow`/`Stop_yellow`, `Play_Pink`/`Play_Celeste` one-shots, `Stop_pink`/`Stop_celeste` en cycle_reset.
- `_on_sector_activated` saltea pink/celeste en Familia 1 (Play_all los cubre).

#### RTPCs por zona (pink, celeste, yellow)
- **`RTPC_V_Pink`** (0-100): 100 si la zona actual tiene piezas pink, 0 si no. Look-ahead: si la próxima zona tiene pink y faltan ≤100ms para el borde, empieza fade up.
- **`RTPC_V_Celeste`** (0-100): 100 si la zona actual tiene piezas celeste, 0 si no. Misma lógica de look-ahead.
- **`RTPC_V_Yellow`** (0-100): cambiado de crossing-based (100 en cruce, 0 en cycle_reset) a zone-based (100 si la zona actual tiene yellow). Misma lógica de look-ahead.
- Todos los RTPC_V_* usan `_ramp()` con `RTPC_RAMP_SPEED = 1000.0` (0→100 en 100ms lineales).
- `_on_cycle_reset` ya no resetea nada (los RTPCs se manejan por zona).
- `_on_crossing_detected` para yellow solo retorna (EffectsRenderer aún recibe el signal para la sombra).

#### Fix: Parse Error (líneas 118-120)
- `pink_in_zone` y `celeste_in_zone` causaban parse error en Godot por inferencia de tipo. Agregadas anotaciones explícitas `: bool`, `: Dictionary`.

#### Fix: neon_green solo se disparaba una vez por ciclo
- `_sector_colors_triggered` usaba el color como key → solo el primer sector con neon_green disparaba en todo el ciclo.
- Cambiado a key `str(sector) + "_" + color` → cada sector con neon_green dispara su evento independentemente.

### Cambios en `ScanlineLogic.gd`
- **Fix deriva entre ciclos**: `_process` ahora usa `Time.get_ticks_usec()` (tiempo absoluto) en vez de acumular `delta`. `scan_position = float(elapsed_usec % _cycle_usec) / float(_cycle_usec)`. El wrap se detecta comparando `cycle_idx`. Zero acumulación de error.
- **Fix wrap**: cambiado `scan_position = 0.0` → `scan_position -= 1.0` para preservar el resto fraccional.
- Default `beats_per_cycle` cambiado de 32 a 16 (coincide con main.tscn).

### Archivos modificados
- `SecuenciaGod/scipts/AudioManager.gd`
- `SecuenciaGod/scipts/ScanlineLogic.gd`
