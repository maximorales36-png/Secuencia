# PATRONES DE TURING (Familia 1):
#   Blue       → Espiral     (como concha de caracol)
#   Green      → Laberinto   (como ameba)
#   Red        → Manchas     (como leopardo)
#   Pink       → Pufferfish  (como pez globo: retícula hexagonal)
#
# CÓMO MODIFICAR:
#   • Colores y patrones: editar GestorFamilias.gd → FAMILIAS
#   • Duración de estelas: cambiar trail_duration (abajo)
#   • Velocidad de onda: cambiar wave_duration (abajo)
#   • Nuevo patrón: agregar función en SECCIÓN 7 y
#     agregar caso en _evaluar_patron()
#
# ============================================================================
extends Node2D
class_name EffectsRenderer

# ============================================================================
# SECCIÓN 1: PARÁMETROS EXPORTABLES
# ============================================================================
@export var wave_duration: float = 1.2
@export var trail_duration: float = 8.0
@export var max_wave_radius: float = 300.0
@export var pattern_radius: float = 220.0
@export var pattern_spacing: float = 10.0
@export var circle_diameter: float = 0.5
@export var wave_ring_count: int = 4
@export var scan_line_width: float = 5.0
@export var scan_line_color: Color = Color(1.0, 0.62, 0.0, 0.69)
@export var yellow_shadow_alpha: float = 0.15
@export var rect_height: float = 80.0
@export var sector_alpha: float = 0.15
# ============================================================================
# SECCIÓN 2: VARIABLES INTERNAS
# ============================================================================
@export var contrast: float = 1.0
@export var max_trails: int = 6
@export var dynamic_spacing_weight: float = 1.5

var scanline_logic: ScanlineLogic
var scan_position: float = 0.0
var active_waves: Array = []
var active_trails: Array = []
var sector_pulses: Dictionary = {}
var sector_count: int = 0
var pattern_seed: float = 0.0
var _violet_saturation: float = 1.0
var last_viewport_size: Vector2 = Vector2.ZERO
var _dynamic_spacing: float = 10.0


# ============================================================================
# SECCIÓN 3: CICLO DE VIDA
# ============================================================================
func _ready() -> void:
	scanline_logic = get_tree().root.find_child("ScanlineLogic", true, false)
	if scanline_logic:
		scanline_logic.crossing_detected.connect(_on_crossing_detected)
		scanline_logic.sector_activated.connect(_on_sector_activated)
		sector_count = scanline_logic.get_sector_count()
	else:
		print("[EffectsRenderer] ERROR: No se encontró ScanlineLogic")


func _process(delta: float) -> void:
	if scanline_logic:
		scan_position = scanline_logic.get_scan_position()
		sector_count = scanline_logic.get_sector_count()

	var ahora: float = Time.get_ticks_msec() / 1000.0

	_update_waves(ahora)
	_update_trails(ahora)

	while active_trails.size() > max_trails:
		active_trails.pop_front()

	var trail_count: int = active_trails.size()
	_dynamic_spacing = pattern_spacing + trail_count * dynamic_spacing_weight
	_dynamic_spacing = min(_dynamic_spacing, pattern_spacing * 3.0)

	pattern_seed += delta * 0.8
	_update_violet_saturation()

	queue_redraw()


# ============================================================================
# SECCIÓN 4: MANEJO DE SEÑALES
# ============================================================================
func _on_crossing_detected(piece: IPCManager.Piece) -> void:
	if GestorFamilias.familia_activa != "familia_1":
		return
	if not GestorFamilias.is_in_active_family(piece.color):
		return
	if piece.color == "violet":
		return

	var viewport = get_viewport_rect().size
	var center := Vector2(piece.x * viewport.x, piece.y * viewport.y)
	_spawn_effect(piece.color, center)


func _on_sector_activated(sector_index: int, y: float, color: String) -> void:
	if GestorFamilias.familia_activa != "familia_1":
		return
	if not GestorFamilias.is_in_active_family(color):
		return

	var viewport = get_viewport_rect().size
	if sector_count <= 0 or viewport.x <= 0:
		return

	var sector_width: float = viewport.x / sector_count
	var center_x: float = (sector_index + 0.5) * sector_width
	var center := Vector2(center_x, y * viewport.y)

	_spawn_effect(color, center, sector_index, y)
	sector_pulses[sector_index] = Time.get_ticks_msec() / 1000.0


# ============================================================================
# SECCIÓN 5: CREACIÓN DE EFECTOS
# ============================================================================
func _spawn_effect(color_name: String, center: Vector2, sector_index: int = -1, y_pos: float = -1.0) -> void:
	var ahora: float = Time.get_ticks_msec() / 1000.0

	active_waves.append({
		center = center,
		color_name = color_name,
		start_time = ahora,
		duration = wave_duration
	})

	var trail_data: Dictionary = {
		center = center,
		color_name = color_name,
		start_time = ahora,
		duration = trail_duration,
		intensity = 1.0,
		shape_type = "circle",
		max_radius = pattern_radius
	}

	if sector_index >= 0 and y_pos >= 0.0:
		var viewport = get_viewport_rect().size
		if viewport.x > 0 and sector_count > 0:
			var s_width: float = viewport.x / sector_count
			var rect_x: float = sector_index * s_width
			var rect_w: float = s_width
			var rect_h: float = rect_height
			var rect_y: float = (y_pos * viewport.y) - rect_h / 2.0
			var sector_rect := Rect2(rect_x, rect_y, rect_w, rect_h)
			sector_rect = sector_rect.grow(s_width * 0.08)

			trail_data.shape_type = "sector"
			trail_data.sector_rect = sector_rect
			trail_data.sector_polygon = _generate_organic_polygon(sector_rect, ahora)

	active_trails.append(trail_data)


# ============================================================================
# SECCIÓN 6: ACTUALIZACIÓN DE ONDAS Y ESTELAS
# ============================================================================
func _update_waves(ahora: float) -> void:
	var keep: Array = []
	for wave in active_waves:
		if ahora - wave.start_time < wave.duration:
			keep.append(wave)
	active_waves = keep


func _update_trails(ahora: float) -> void:
	var keep: Array = []
	for trail in active_trails:
		var edad: float = ahora - trail.start_time
		if edad < trail.duration:
			trail.intensity = 1.0 - (edad / trail.duration)
			keep.append(trail)
	active_trails = keep


# ============================================================================
# SECCIÓN 6.5: SATURACIÓN CONTROLADA POR VIOLETA
# ============================================================================
func _update_violet_saturation() -> void:
	if scanline_logic == null:
		_violet_saturation = 1.0
		return
	var found := false
	var highest_y := 1.0
	for piece in scanline_logic.pieces:
		if piece.color == "violet" and piece.y < highest_y:
			highest_y = piece.y
			found = true
	if found:
		var rtpc = (1.0 - highest_y) * 100.0
		_violet_saturation = rtpc / 100.0
	else:
		_violet_saturation = 1.0


func _adjust_saturation(color: Color, nombre_color: String) -> Color:
	if nombre_color in ["pink", "blue"]:
		var c: Color = color
		c.s = c.s * _violet_saturation
		return c
	return color


# ============================================================================
# SECCIÓN 7: PATRONES DE TURING
# ============================================================================
func _eval_pattern(color_name: String, x: float, y: float, semilla: float) -> bool:
	var patron: String = GestorFamilias.get_pattern(color_name)

	match patron:
		"spots":
			return _pattern_spots(x, y, semilla)
		"stripes":
			return _pattern_stripes(x, y, semilla)
		"spiral":
			return _pattern_spiral(x, y, semilla)
		"labyrinth":
			return _pattern_labyrinth(x, y, semilla)
		"pufferfish":
			return _pattern_pufferfish(x, y, semilla)
		_:
			return false


## PATRÓN: MANCHAS (SPOTS)  →  Red
func _pattern_spots(x: float, y: float, semilla: float) -> bool:
	var f: float = 0.04
	var v1: float = sin(x * f + semilla) * cos(y * f * 1.3 + semilla * 0.7)
	var v2: float = sin((x + y) * f * 0.7 + semilla * 0.3)
	var v3: float = cos(x * f * 0.5 - y * f * 0.9 + semilla * 0.5)
	var valor: float = v1 + v2 * 0.6 + v3 * 0.4
	return valor > 0.6


## PATRÓN: RAYAS (STRIPES)  →  Pink
func _pattern_stripes(x: float, y: float, semilla: float) -> bool:
	var f: float = 0.03
	var angulo: float = 0.6
	var xr: float = x * cos(angulo) - y * sin(angulo)
	var yr: float = x * sin(angulo) + y * cos(angulo)
	var v1: float = sin(xr * f + semilla)
	var v2: float = cos(yr * f * 1.5 + semilla * 0.5) * 0.4
	var valor: float = v1 + v2
	return abs(valor) > 0.15


## PATRÓN: ESPIRAL (SPIRAL)  →  Blue
func _pattern_spiral(x: float, y: float, semilla: float) -> bool:
	var r: float = sqrt(x * x + y * y)
	if r < 4.0:
		return true
	var theta: float = atan2(y, x)
	var vueltas: float = 3.0
	var f_radial: float = 0.06
	var v: float = sin(theta * vueltas + r * f_radial * 2.0 + semilla)
	return v > 0.0


## PATRÓN: LABERINTO (LABYRINTH)  →  Green
func _pattern_labyrinth(x: float, y: float, semilla: float) -> bool:
	var f: float = 0.03
	var v1: float = sin(x * f + y * f * 1.2 + semilla)
	var v2: float = sin(x * f * 0.8 - y * f * 1.5 + semilla * 0.7)
	var v3: float = sin((x + y) * f * 0.7 + semilla * 1.3)
	var v4: float = sin((x - y) * f * 1.3 + semilla * 0.2)
	var v5: float = cos(x * f * 0.5 + y * f * 0.9 + semilla * 0.9)
	var valor: float = v1 + v2 + v3 * 0.6 + v4 * 0.4 + v5 * 0.5
## PATRÓN: PUFFERFISH  →  Pink
	return valor > 0.1


## PATRÓN: PUFFERFISH  →  Pink
func _pattern_pufferfish(x: float, y: float, semilla: float) -> bool:
	var f: float = 0.07
	var y_proj: float = y * f
	var x1_proj: float = (x * 0.866 + y * 0.5) * f
	var x2_proj: float = (-x * 0.866 + y * 0.5) * f
	var v1: float = sin(y_proj + semilla * 0.5)
	var v2: float = sin(x1_proj + semilla)
	var v3: float = sin(x2_proj + semilla * 0.8)
	var v4: float = cos(y_proj * 0.7 + x1_proj * 0.7 + semilla * 1.2) * 0.5
	var valor: float = v1 + v2 + v3 + v4
	return valor > -0.3


# ============================================================================
# SECCIÓN 8: FUNCIONES AUXILIARES DE PATRONES
# ============================================================================
func _jitter(cx: float, cy: float, max_jitter: float) -> Vector2:
	var n: float = sin(cx * 127.1 + cy * 311.7) * 43758.5453
	var hx: float = n - floor(n)
	var hy: float = sin(n * 17.1 + cx * 3.7) * 0.5 + 0.5
	return Vector2((hx - 0.5) * max_jitter, (hy - 0.5) * max_jitter)


func _generate_organic_polygon(rect: Rect2, semilla: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var pts_per_side: int = 10

	for i in range(4 * pts_per_side):
		var side: int = int(float(i) / pts_per_side)
		var t: float = float(i % pts_per_side) / float(pts_per_side)

		var base: Vector2
		match side:
			0: base = Vector2(rect.position.x + t * rect.size.x, rect.position.y)
			1: base = Vector2(rect.position.x + rect.size.x, rect.position.y + t * rect.size.y)
			2: base = Vector2(rect.position.x + (1.0 - t) * rect.size.x, rect.position.y + rect.size.y)
			3: base = Vector2(rect.position.x, rect.position.y + (1.0 - t) * rect.size.y)

		var jitter_amount: float = 8.0 + sin(semilla + i * 0.3) * 5.0
		var j: Vector2 = _jitter(base.x * 0.05 + semilla, base.y * 0.05 + i, jitter_amount)
		points.append(base + j)

	return points


# ============================================================================
# SECCIÓN 9: DIBUJADO (_draw)
# ============================================================================
func _draw() -> void:
	_draw_trails()
	_draw_sector_rectangles()
	_draw_red_shadow()
	_draw_waves()
	_draw_scanline()

	last_viewport_size = get_viewport_rect().size


# --------------------------------------------------------------------------
# 9.1: DIBUJAR ESTELAS — con aspecto orgánico tipo Voronoi
# --------------------------------------------------------------------------
func _draw_trails() -> void:
	if active_trails.is_empty():
		return

	var viewport := get_viewport_rect().size
	if viewport.x <= 0 or viewport.y <= 0:
		return

	for trail in active_trails:
		match trail.shape_type:
			"circle":
				_draw_circular_trail(trail)
			"sector":
				_draw_sector_trail(trail)


func _draw_circular_trail(trail: Dictionary) -> void:
	var color_name: String = trail.color_name
	var centro: Vector2 = trail.center
	var radio: float = trail.max_radius * trail.intensity
	var intensidad: float = trail.intensity

	var color_patron: Color = _adjust_saturation(GestorFamilias.get_color(color_name), color_name)
	color_patron.a = intensidad * 0.9 * contrast
	if color_patron.a < 0.02:
		return

	var spacing: float = _dynamic_spacing
	var jitter_amount: float = spacing * 0.45
	var inicio_x: float = centro.x - radio
	var fin_x: float = centro.x + radio
	var inicio_y: float = centro.y - radio
	var fin_y: float = centro.y + radio

	var cx: float = inicio_x
	while cx < fin_x:
		var cy: float = inicio_y
		while cy < fin_y:
			var j: Vector2 = _jitter(cx, cy, jitter_amount)
			var sx: float = cx + j.x
			var sy: float = cy + j.y

			var dx: float = sx - centro.x
			var dy: float = sy - centro.y
			var dist: float = sqrt(dx * dx + dy * dy)

			if dist > radio:
				cy += spacing
				continue

			var alpha_punto: float = intensidad * contrast

			if alpha_punto < 0.05:
				cy += spacing
				continue

			if _eval_pattern(color_name, dx, dy, pattern_seed + dist * 0.1):
				var c: Color = color_patron
				c.a = alpha_punto
				var radio_celula: float = spacing * circle_diameter
				draw_circle(Vector2(sx, sy), radio_celula, c)

			cy += spacing
		cx += spacing


func _draw_sector_trail(trail: Dictionary) -> void:
	var color_name: String = trail.color_name
	var intensidad: float = trail.intensity
	var polygon: PackedVector2Array = trail.get("sector_polygon", PackedVector2Array())
	var sector_rect: Rect2 = trail.get("sector_rect", Rect2())

	if polygon.is_empty() or sector_rect.size.x <= 0 or sector_rect.size.y <= 0:
		return

	var color_patron: Color = _adjust_saturation(GestorFamilias.get_color(color_name), color_name)
	color_patron.a = intensidad * 0.9 * contrast
	if color_patron.a < 0.02:
		return

	var spacing: float = _dynamic_spacing
	var jitter_amount: float = spacing * 0.45

	var cx: float = sector_rect.position.x
	while cx < sector_rect.position.x + sector_rect.size.x:
		var cy: float = sector_rect.position.y
		while cy < sector_rect.position.y + sector_rect.size.y:
			var j: Vector2 = _jitter(cx, cy, jitter_amount)
			var sx: float = cx + j.x
			var sy: float = cy + j.y

			if not Geometry2D.is_point_in_polygon(Vector2(sx, sy), polygon):
				cy += spacing
				continue

			var dx: float = sx - trail.center.x
			var dy: float = sy - trail.center.y
			var dist: float = sqrt(dx * dx + dy * dy)

			var alpha_punto: float = intensidad * contrast

			if alpha_punto < 0.05:
				cy += spacing
				continue

			if _eval_pattern(color_name, dx, dy, pattern_seed + dist * 0.1):
				var c: Color = color_patron
				c.a = alpha_punto
				var radio_celula: float = spacing * circle_diameter
				draw_circle(Vector2(sx, sy), radio_celula, c)

			cy += spacing
		cx += spacing


# --------------------------------------------------------------------------
# 9.2: DIBUJAR ONDAS EXPANSIVAS
# --------------------------------------------------------------------------
func _draw_waves() -> void:
	if active_waves.is_empty():
		return

	var ahora: float = Time.get_ticks_msec() / 1000.0

	for wave in active_waves:
		var edad: float = ahora - wave.start_time
		var progreso: float = edad / wave.duration
		var color_name: String = wave.color_name
		var centro: Vector2 = wave.center

		var radio_actual: float = progreso * max_wave_radius
		var intensidad: float = 1.0 - progreso
		var color_onda: Color = _adjust_saturation(GestorFamilias.get_color(color_name), color_name)

		for j in range(wave_ring_count):
			var radio_anillo: float = radio_actual * (1.0 - j * 0.12)

			if radio_anillo < 2.0:
				continue

			var alpha_anillo: float = intensidad * (1.0 - j * 0.25) * contrast
			var grosor_anillo: float = (4.0 - j * 1.0) * intensidad

			if alpha_anillo < 0.02 or grosor_anillo < 0.5:
				continue

			var c: Color = color_onda
			c.a = alpha_anillo

			var segmentos: int = max(16, 64 - j * 12)
			draw_arc(centro, radio_anillo, 0, TAU, segmentos, c, grosor_anillo)


# --------------------------------------------------------------------------
# 9.3: RECTÁNGULOS DE SECTOR (igual que en v1)
# --------------------------------------------------------------------------
func _draw_sector_rectangles() -> void:
	if scanline_logic == null:
		return
	var viewport = get_viewport_rect().size
	if viewport.x <= 0 or viewport.y <= 0:
		return
	var s_count = scanline_logic.get_sector_count()
	if s_count <= 0:
		return
	var sector_width = viewport.x / s_count

	for i in range(s_count):
		var sector_data = scanline_logic.sector_colors.get(i)
		if sector_data == null:
			continue

		for color in sector_data:
			var y = sector_data[color]

			var rect_color: Color = _adjust_saturation(GestorFamilias.get_color(color), color)
			rect_color.a = sector_alpha * contrast

			var rect_x = i * sector_width
			var rect_w = sector_width
			var rect_h = rect_height
			var center_y = y * viewport.y
			var rect_y = center_y - rect_h / 2.0
			draw_rect(Rect2(rect_x, rect_y, rect_w, rect_h), rect_color)


# --------------------------------------------------------------------------
# 9.4: SOMBRA ROJA (soga)  — igual que en v1
# --------------------------------------------------------------------------
func _draw_red_shadow() -> void:
	if scanline_logic == null:
		return
	var reds = scanline_logic.get_red_pieces()
	if reds.is_empty():
		return
	var viewport = get_viewport_rect().size
	if viewport.x <= 0 or viewport.y <= 0:
		return

	reds.sort_custom(func(a, b): return a.x < b.x)
	var h = rect_height
	var color = Color(1.0, 0.2, 0.2, yellow_shadow_alpha * contrast)
	var w = viewport.x
	var first = reds[0]
	var last = reds[reds.size() - 1]

	var points = PackedVector2Array()
	points.append(Vector2(0, first.y * viewport.y - h / 2.0))
	for yp in reds:
		points.append(Vector2(yp.x * w, yp.y * viewport.y - h / 2.0))
	points.append(Vector2(w, last.y * viewport.y - h / 2.0))
	points.append(Vector2(w, last.y * viewport.y + h / 2.0))
	for i in range(reds.size() - 1, -1, -1):
		var yp = reds[i]
		points.append(Vector2(yp.x * w, yp.y * viewport.y + h / 2.0))
	points.append(Vector2(0, first.y * viewport.y + h / 2.0))

	draw_colored_polygon(points, color)


# --------------------------------------------------------------------------
# 9.5: LÍNEA DE BARRIDO  — igual que en v1
# --------------------------------------------------------------------------
func _draw_scanline() -> void:
	var viewport = get_viewport_rect().size
	var x = scan_position * viewport.x
	var c: Color = scan_line_color
	c.a = scan_line_color.a * contrast
	draw_line(Vector2(x, 0), Vector2(x, viewport.y), c, scan_line_width)
