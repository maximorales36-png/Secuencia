extends Control
class_name FamilyButton

@export var family_name: String = "familia_1"
@export var select_time: float = 1.0
@export var visual_ratio: float = 0.55
@export var circle_ratio: float = 0.36
@export var label_text: String = ""

signal family_selected(family_name: String)

const PIECE_HIT_TOLERANCE := 1.15

var _time: float = 0.0
var _fill_time: float = 0.0
var _piece_present: bool = false
var _is_selected: bool = false
var _flash_timer: float = 0.0
var _bouncing_balls: Array = []
var _balls_initialized: bool = false


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if _is_selected:
		_flash_timer += delta
		queue_redraw()
		return

	_time += delta
	_update_presence(delta)

	if family_name == "familia_4":
		if not _balls_initialized:
			_init_bouncing_balls()
		_update_bouncing_balls(delta)

	queue_redraw()


func _update_presence(delta: float) -> void:
	var geo := _get_circle_geometry(size)
	var center_local: Vector2 = geo.center
	var hit_radius: float = geo.radius * PIECE_HIT_TOLERANCE
	var hit_sq: float = hit_radius * hit_radius
	var center_global := get_global_position() + center_local
	var vp_size := get_viewport_rect().size

	_piece_present = false
	for piece in IPCManager.pieces:
		var sx := piece.x * vp_size.x
		var sy := piece.y * vp_size.y
		var d := Vector2(sx, sy) - center_global
		if d.length_squared() <= hit_sq:
			_piece_present = true
			break

	if _piece_present:
		_fill_time += delta
	else:
		_fill_time = 0.0

	if _fill_time >= select_time:
		_select()


func _get_circle_geometry(s: Vector2) -> Dictionary:
	var avail := s.y * (1.0 - visual_ratio)
	var radius: float = minf(s.x * circle_ratio, avail * 0.42)
	var center := Vector2(s.x * 0.5, s.y - avail * 0.5)
	return { center = center, radius = radius }


func _select() -> void:
	_is_selected = true
	family_selected.emit(family_name)


func _draw() -> void:
	var s := size
	if s.x <= 0 or s.y <= 0:
		return

	draw_rect(Rect2(Vector2.ZERO, s), Color(0.08, 0.08, 0.12, 0.85), true)

	var border_col := Color(0.35, 0.35, 0.45, 1.0)
	if _is_selected:
		var glow := 0.5 + 0.5 * sin(_flash_timer * 4.0)
		border_col = Color(0.0, 1.0, 0.5, 0.6 + 0.4 * glow)
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 1.0, 0.5, 0.08 * glow), true)

	var visual_size := Vector2(s.x, s.y * visual_ratio)
	match family_name:
		"familia_1":
			_draw_turing_pattern(visual_size)
		"familia_2":
			_draw_blob_pattern(visual_size)
		"familia_4":
			_draw_familia4_pattern(visual_size)
		_:
			_draw_abstract_pattern(visual_size)

	draw_rect(Rect2(Vector2.ZERO, s), border_col, false, 2.0)

	var display_name := label_text if not label_text.is_empty() else family_name.replace("_", " ").capitalize()
	var font := ThemeDB.fallback_font
	var font_size := 30
	draw_string(font, Vector2(0, 40), display_name, HORIZONTAL_ALIGNMENT_CENTER, s.x, font_size, Color(1, 1, 1, 0.7))

	_draw_target_circle(s, border_col)


func _draw_target_circle(s: Vector2, border_col: Color) -> void:
	var geo := _get_circle_geometry(s)
	var center: Vector2 = geo.center
	var radius: float = geo.radius
	var ring_w := 6.0

	if _is_selected:
		draw_circle(center, radius, Color(0.0, 1.0, 0.5, 0.12))
		draw_arc(center, radius, 0, TAU, 48, border_col, ring_w, true)
		return

	var outline_col := Color(0.85, 0.9, 1.0, 0.95) if _piece_present else Color(0.45, 0.45, 0.55, 0.8)
	draw_circle(center, radius, Color(1, 1, 1, 0.04))
	if _piece_present:
		draw_arc(center, radius, 0, TAU, 48, Color(0.7, 0.8, 1.0, 0.18), ring_w * 2.5, true)
	draw_arc(center, radius, 0, TAU, 48, outline_col, 2.0, true)

	if _fill_time > 0.01:
		var progress := clampf(_fill_time / select_time, 0.0, 1.0)
		draw_arc(center, radius, 0, TAU, 48, Color(1, 1, 1, 0.1), ring_w, true)
		draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + progress * TAU, 48, border_col, ring_w, true)


func _draw_turing_pattern(s: Vector2) -> void:
	var cols: Array[Color] = [
		GestorFamilias.get_color("pink"),
		GestorFamilias.get_color("blue"),
		GestorFamilias.get_color("red"),
		GestorFamilias.get_color("violet"),
		GestorFamilias.get_color("green")
	]
	var center := s * 0.5
	var r := minf(s.x, s.y) * 0.4

	for i in range(14):
		var angle := i * TAU / 14 + _time * 0.25
		var dist := r * (0.2 + 0.6 * (0.5 + 0.5 * sin(_time * 0.35 + i * 1.3)))
		var pos := center + Vector2(cos(angle), sin(angle)) * dist
		var radius := 8.0 + 14.0 * (0.5 + 0.5 * sin(_time * 0.55 + i * 2.1))
		var col: Color = cols[i % cols.size()]
		col = Color.from_hsv(col.h, col.s * 0.3, col.v, col.a)
		col.a = 0.35 + 0.5 * (0.5 + 0.5 * sin(_time * 0.6 + i * 1.7))
		draw_circle(pos, radius, col)


func _draw_blob_pattern(s: Vector2) -> void:
	var cols: Array[Color] = [
		GestorFamilias.get_color("blue"),
		GestorFamilias.get_color("red"),
		GestorFamilias.get_color("green"),
		GestorFamilias.get_color("violet")
	]
	var center := s * 0.5
	var r := minf(s.x, s.y) * 0.35

	for i in range(10):
		var angle := i * TAU / 10 + _time * 0.18
		var dist := r * (0.25 + 0.25 * sin(_time * 0.5 + i * 1.1))
		var pos := center + Vector2(cos(angle), sin(angle)) * dist
		var radius := 12.0 + 14.0 * (0.5 + 0.5 * sin(_time * 0.65 + i * 2.0))
		var col: Color = cols[i % cols.size()]
		col = Color.from_hsv(col.h, col.s * 0.3, col.v, col.a)
		col.a = 0.55 + 0.2 * sin(_time * 0.4 + i * 1.5)
		draw_circle(pos, radius, col)

	for i in range(6):
		var angle := i * TAU / 6 + _time * -0.1
		var dist := r * 0.5
		var pos := center + Vector2(cos(angle), sin(angle)) * dist
		var radius := 6.0 + 8.0 * (0.5 + 0.5 * sin(_time * 0.3 + i * 2.7))
		var col: Color = cols[(i + 2) % cols.size()]
		col = Color.from_hsv(col.h, col.s * 0.3, col.v, col.a)
		col.a = 0.3
		draw_circle(pos, radius, col)


func _draw_abstract_pattern(s: Vector2) -> void:
	var center := s * 0.5
	var r := minf(s.x, s.y) * 0.4
	var grid := 6
	var spacing := minf(s.x, s.y) / float(grid + 1)
	var start := (s - Vector2.ONE * spacing * grid) * 0.5 + Vector2.ONE * spacing * 0.5

	for gx in range(grid):
		for gy in range(grid):
			var pos := start + Vector2(gx, gy) * spacing
			var dx := float(gx) / float(grid - 1) - 0.5
			var dy := float(gy) / float(grid - 1) - 0.5
			var wave := 0.5 + 0.5 * sin(dx * 5.0 + _time * 2.0) * cos(dy * 5.0 + _time * 1.5)
			var radius := 2.0 + 5.0 * wave
			var col: Color = Color(0.3 + 0.4 * wave, 0.2 + 0.3 * (1.0 - wave), 0.5, 0.7)
			draw_circle(pos, radius, col)

	for gx in range(grid - 1):
		for gy in range(grid):
			var p1 := start + Vector2(gx, gy) * spacing
			var p2 := start + Vector2(gx + 1, gy) * spacing
			var alpha := 0.15 + 0.2 * sin(gx * 0.7 + gy * 0.5 + _time * 1.2)
			draw_line(p1, p2, Color(0.4, 0.4, 0.6, alpha), 1.0)

	for gx in range(grid):
		for gy in range(grid - 1):
			var p1 := start + Vector2(gx, gy) * spacing
			var p2 := start + Vector2(gx, gy + 1) * spacing
			var alpha := 0.15 + 0.2 * sin(gx * 0.5 + gy * 0.7 + _time * 1.0)
			draw_line(p1, p2, Color(0.4, 0.4, 0.6, alpha), 1.0)


func _init_bouncing_balls() -> void:
	_balls_initialized = true
	var s := Vector2(size.x, size.y * visual_ratio)
	var colors: Array[Color] = [
		Color(0.3, 0.7, 1.0, 0.9),
		Color(0.6, 0.8, 1.0, 0.9),
		Color(0.1, 0.4, 0.7, 0.9),
		Color(0.5, 0.9, 1.0, 0.9),
		Color(0.2, 0.6, 0.9, 0.9),
	]
	for i in range(5):
		_bouncing_balls.append({
			x = randf() * s.x,
			y = randf() * s.y,
			vx = (randf() - 0.5) * 120.0,
			vy = (randf() - 0.5) * 120.0,
			radius = 3.0 + randi() % 4,
			color = colors[i],
		})


func _update_bouncing_balls(delta: float) -> void:
	var s := Vector2(size.x, size.y * visual_ratio)
	if s.x <= 0 or s.y <= 0:
		return
	for ball in _bouncing_balls:
		ball.x += ball.vx * delta
		ball.y += ball.vy * delta
		if ball.x < ball.radius:
			ball.x = ball.radius
			ball.vx = abs(ball.vx)
		elif ball.x > s.x - ball.radius:
			ball.x = s.x - ball.radius
			ball.vx = -abs(ball.vx)
		if ball.y < ball.radius:
			ball.y = ball.radius
			ball.vy = abs(ball.vy)
		elif ball.y > s.y - ball.radius:
			ball.y = s.y - ball.radius
			ball.vy = -abs(ball.vy)


func _draw_familia4_pattern(s: Vector2) -> void:
	var center := s * 0.5
	var r := minf(s.x, s.y) * 0.4

	for i in range(8):
		var angle := i * TAU / 8 + _time * 0.12
		var dist := r * (0.2 + 0.5 * (0.5 + 0.5 * sin(_time * 0.35 + i * 0.9)))
		var pos := center + Vector2(cos(angle), sin(angle)) * dist
		var noise_r := 14.0 + 12.0 * (0.5 + 0.5 * sin(_time * 0.5 + i * 1.5))
		var deform := 0.85 + 0.15 * sin(_time * 0.7 + i * 2.3)

		var col: Color = Color(0.15 + 0.08 * i, 0.4 + 0.06 * i, 0.7 + 0.04 * i, 0.25)
		draw_circle(pos, noise_r * deform * 1.5, col)
		col.a = 0.4
		draw_circle(pos, noise_r * deform * 0.9, col)
		col.a = 0.65
		draw_circle(pos, noise_r * deform * 0.45, col)

	for i in range(4):
		var angle := i * TAU / 4 + _time * -0.08
		var dist := r * 0.55
		var pos := center + Vector2(cos(angle), sin(angle)) * dist
		var pulse := 8.0 + 6.0 * (0.5 + 0.5 * sin(_time * 0.3 + i * 2.7))
		var col: Color = Color(0.4, 0.7, 1.0, 0.2)
		draw_circle(pos, pulse * 1.8, col)
		col.a = 0.35
		draw_circle(pos, pulse, col)

	for ball in _bouncing_balls:
		var pos := Vector2(ball.x, ball.y)
		var col: Color = ball.color
		var glow: Color = col
		glow.a = 0.25
		draw_circle(pos, ball.radius * 3.0, glow)
		draw_circle(pos, ball.radius, col)
