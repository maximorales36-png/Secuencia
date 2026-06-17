extends Control
class_name FamilyButton

@export var family_name: String = "familia_1"
@export var hold_time: float = 3.0
@export var movement_threshold: float = 5.0
@export var label_text: String = ""

signal family_selected(family_name: String)

var _time: float = 0.0
var _tracked: Dictionary = {}
var _is_selected: bool = false
var _flash_timer: float = 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if _is_selected:
		_flash_timer += delta
		queue_redraw()
		return

	_time += delta
	_check_pieces()
	queue_redraw()


func _check_pieces() -> void:
	var rect := get_global_rect()
	var now := Time.get_ticks_msec() / 1000.0
	var vp_size := get_viewport_rect().size
	var pieces := IPCManager.pieces
	var new_tracked: Dictionary = {}

	for piece in pieces:
		var sx := piece.x * vp_size.x
		var sy := piece.y * vp_size.y

		if not rect.has_point(Vector2(sx, sy)):
			continue

		var matched_key := ""
		for key in _tracked:
			if matched_key != "":
				break
			var t = _tracked[key]
			if abs(sx - t.last_x) < movement_threshold * 2 and abs(sy - t.last_y) < movement_threshold * 2:
				matched_key = key

		var tracker: Dictionary
		if matched_key != "" and _tracked.has(matched_key):
			tracker = _tracked[matched_key]
			var dx = sx - tracker.last_x
			var dy = sy - tracker.last_y
			tracker.last_x = sx
			tracker.last_y = sy
			if sqrt(dx * dx + dy * dy) > movement_threshold:
				tracker.stable_since = now
		else:
			tracker = { stable_since = now, last_x = sx, last_y = sy }

		new_tracked[matched_key if matched_key != "" else str(randi())] = tracker

	_tracked = new_tracked

	for key in _tracked:
		if now - _tracked[key].stable_since >= hold_time:
			_select()


func _select() -> void:
	_is_selected = true
	family_selected.emit(family_name)


func _get_most_stable() -> Dictionary:
	var now := Time.get_ticks_msec() / 1000.0
	var best: Dictionary = {}
	var best_time: float = 0.0
	for key in _tracked:
		var t = _tracked[key]
		var stable = now - t.stable_since
		if stable > best_time:
			best_time = stable
			best = t
	return best


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

	match family_name:
		"familia_1":
			_draw_turing_pattern(s)
		"familia_2":
			_draw_blob_pattern(s)
		_:
			_draw_abstract_pattern(s)

	draw_rect(Rect2(Vector2.ZERO, s), border_col, false, 2.0)

	var display_name := label_text if not label_text.is_empty() else family_name.replace("_", " ").capitalize()
	var font := ThemeDB.fallback_font
	var font_size := 14
	draw_string(font, Vector2(0, s.y - 10), display_name, HORIZONTAL_ALIGNMENT_CENTER, s.x, font_size, Color(1, 1, 1, 0.7))

	var stable := _get_most_stable()
	if not stable.is_empty() and not _is_selected:
		var now := Time.get_ticks_msec() / 1000.0
		var progress := clampf((now - stable.stable_since) / hold_time, 0.0, 1.0)
		if progress > 0.01:
			var bar_w := s.x * 0.5
			var bar_h := 4.0
			var bar_x := (s.x - bar_w) * 0.5
			var bar_y := s.y - 24
			draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(1, 1, 1, 0.15), true)
			draw_rect(Rect2(bar_x, bar_y, bar_w * progress, bar_h), border_col, true)


func _draw_turing_pattern(s: Vector2) -> void:
	var cols: Array[Color] = [
		GestorFamilias.get_color("pink"),
		GestorFamilias.get_color("celeste"),
		GestorFamilias.get_color("yellow"),
		GestorFamilias.get_color("violet"),
		GestorFamilias.get_color("neon_green")
	]
	var center := s * 0.5
	var r := minf(s.x, s.y) * 0.4

	for i in range(14):
		var angle := i * TAU / 14 + _time * 0.25
		var dist := r * (0.2 + 0.6 * (0.5 + 0.5 * sin(_time * 0.35 + i * 1.3)))
		var pos := center + Vector2(cos(angle), sin(angle)) * dist
		var radius := 8.0 + 14.0 * (0.5 + 0.5 * sin(_time * 0.55 + i * 2.1))
		var col: Color = cols[i % cols.size()]
		col.a = 0.35 + 0.5 * (0.5 + 0.5 * sin(_time * 0.6 + i * 1.7))
		draw_circle(pos, radius, col)


func _draw_blob_pattern(s: Vector2) -> void:
	var cols: Array[Color] = [
		GestorFamilias.get_color("celeste"),
		GestorFamilias.get_color("yellow"),
		GestorFamilias.get_color("neon_green"),
		GestorFamilias.get_color("orange"),
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
		col.a = 0.55 + 0.2 * sin(_time * 0.4 + i * 1.5)
		draw_circle(pos, radius, col)

	for i in range(6):
		var angle := i * TAU / 6 + _time * -0.1
		var dist := r * 0.5
		var pos := center + Vector2(cos(angle), sin(angle)) * dist
		var radius := 6.0 + 8.0 * (0.5 + 0.5 * sin(_time * 0.3 + i * 2.7))
		var col: Color = cols[(i + 2) % cols.size()]
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
