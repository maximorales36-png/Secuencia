# Cambios

## 2026-06-13 — Refactor audio Familia 1: Play_all + RTPCs por zona

### Motivación
Eliminar overlapping de eventos pink/celeste que se cortaban entre sí al dispararse por sector. Simplificar la lógica de audio usando un solo evento continuo.

### Cambios en `AudioManager.gd`
- **`Play_all`**: se dispara una vez en `_ready()` para Familia 1, suena hasta salir del juego. `Stop_all` en `_exit_tree()`.
- **Eliminado**: `_handle_yellow` (switch de notas), `Play_Yellow`/`Stop_yellow`, `Play_Pink`/`Play_Celeste` one-shots, `Stop_pink`/`Stop_celeste` en cycle_reset.
- **Nuevos RTPC**:
  - `RTPC_V_Pink` (0-100): snap por zona actual. 100 si la zona tiene piezas pink, 0 si no.
  - `RTPC_V_Celeste` (0-100): snap por zona actual. 100 si la zona tiene piezas celeste, 0 si no.
  - `RTPC_V_Yellow` (0-100): 100 al cruzar yellow (`_on_crossing_detected`), 0 en cycle_reset.
- `_on_sector_activated` saltea pink/celeste en Familia 1 (Play_all los cubre).
- `_on_cycle_reset` solo resetea `RTPC_V_Yellow` a 0.

### Cambios en `ScanlineLogic.gd`
- **Fix deriva entre ciclos**: `_process` ahora usa `Time.get_ticks_usec()` (tiempo absoluto) en vez de acumular `delta`. `scan_position = float(elapsed_usec % _cycle_usec) / float(_cycle_usec)`. El wrap se detecta comparando `cycle_idx`. Zero acumulación de error.
- Default `beats_per_cycle` cambiado de 32 a 16 (coincide con main.tscn).

### Archivos modificados
- `SecuenciaGod/scipts/AudioManager.gd`
- `SecuenciaGod/scipts/ScanlineLogic.gd`
