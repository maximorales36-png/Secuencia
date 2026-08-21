# Plan de cambios — Menú de familias

## Objetivo
Rediseñar la interacción del menú (`main_menu.tscn`) para mejorar la detección de piezas:
botones más altos con visuales arriba y un círculo de detección abajo; selección por
presencia (~1s) sin exigir pieza quieta, conservando el anillo de progreso como feedback.

## Cambios en `scipts/MenuButton.gd`

### Estado y exports
- Eliminar: `hold_time`, `movement_threshold`, `_tracked`, `_get_most_stable()`.
- Agregar exports:
  - `select_time: float = 1.0` (tiempo que tarda en llenarse el anillo)
  - `visual_ratio: float = 0.55` (fracción superior del botón para las visuales)
  - `circle_ratio: float = 0.36` (radio del círculo relativo al ancho del botón)
- Agregar estado interno: `_fill_time: float`, `_piece_present: bool`.
- Constante `PIECE_HIT_TOLERANCE := 1.15` (tolerancia del hit-test del círculo).

### Lógica de detección (reemplaza `_check_pieces()`)
- Geometría del círculo: centrado en la zona inferior del botón
  (`center.y = s.y - avail * 0.5`, `avail = s.y * (1 - visual_ratio)`;
  radio = `min(s.x * circle_ratio, avail * 0.42)`).
- Hit-test por distancia (no rect): una pieza cuenta como presente si
  `distancia(pieza, centro_global_circulo) <= radio * tolerancia`.
- Mientras haya al menos una pieza dentro: `_fill_time += delta`.
- Si la pieza sale: `_fill_time = 0` (reinicio de golpe).
- Al llegar a `select_time`: `_select()` → cambio de escena inmediato.
- El movimiento dentro del círculo se ignora por completo (solo presencia).

### Redibujo (`_draw()`)
- Fondo, borde y flash verde de selección: sin cambios.
- Patrones (`_draw_turing_pattern`, `_draw_blob_pattern`,
  `_draw_familia4_pattern`, `_draw_abstract_pattern`): recibir
  `Vector2(s.x, s.y * visual_ratio)` para ocupar solo la parte superior.
- Etiqueta de texto movida al borde superior del botón.
- Círculo de detección abajo:
  - Reposo: relleno oscuro leve + contorno gris sutil.
  - Con pieza dentro: contorno se ilumina.
  - Progreso: pista circular tenue + arco que se llena desde `-PI/2`
    según `_fill_time / select_time` (el propio círculo es el anillo).
  - Seleccionado: participa del flash verde existente.

## Cambios en `scipts/FamilyMenu.gd`
- `btn_h` de `vp.y * 0.42` → `vp.y * 0.62` (línea 17). El centrado vertical actual sigue funcionando.

## Sin cambios
- Wwise (`mx_play_menu`, `Enter_F_%02d`), flujo hacia `main.tscn`,
  `PiecesVisualizer`, `KeyboardTester.gd` (sigue simulando selección igual).
- `FamilyButton.new()` en FamilyMenu sigue válido (class_name no cambia).

## Verificación
1. Sin binario de Godot disponible en PATH: revisión manual cuidadosa del GDScript
   (tipado, nombres, referencias).
2. Prueba manual sugerida: escribir JSON de prueba en
   `%TEMP%\secuencia_pieces.json` simulando una pieza dentro/fuera del círculo;
   verificar llenado en ~1s, reinicio al retirar la pieza y transición a `main.tscn`.
3. Ajustes finos vía los tres nuevos exports si las proporciones no convencen.
