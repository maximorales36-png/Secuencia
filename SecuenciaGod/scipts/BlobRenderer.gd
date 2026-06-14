extends Node2D
class_name BlobRenderer

@export var blob_radius_base: float = 30.0
@export var max_wave_radius: float = 400.0
@export var wave_duration: float = 1.5
@export var trail_duration: float = 6.0
@export var scan_line_aura: float = 60.0
@export var scan_line_halo: float = 18.0
@export var scan_line_core: float = 2.0
@export var connection_threshold: float = 3.0

var scanline_logic: ScanlineLogic
var _audio_manager: Node = null
var _waves: Array = []
var _trails: Array = []
var tracked_pieces: Dictionary = {}
var frame: int = 0
var pattern_seed: float = 0.0
var scan_progress: float = 0.0

const PIECE_TIMEOUT: float = 0.5
const TRAIL_BG_ALPHA_NIGHT: float = 0.13
const TRAIL_BG_ALPHA_LIGHT: float = 0.18

@export var bpm: float = 76.0
@export var beats_per_cycle: int = 4

var is_night: bool = true
var _viewport: Vector2 = Vector2.ZERO
var _start_usec: int = 0
var _cycle_usec: int = 0
var _last_cycle_idx: int = -1


class BlobPiece:
	var id: int
	var color: String
	var x: float
	var y: float
	var radius: float
	var phase: float
	var energy: float
	var rings: int
	var cool: int
	var last_seen: float

	func _init(p_id: int, p_color: String, p_x: float, p_y: float):
		id = p_id
		color = p_color
		x = p_x
		y = p_y
		radius = 24.0 + randf() * 20.0
		phase = randf() * TAU
		energy = 1.0
		rings = 2 + randi() % 3
		cool = 0
		last_seen = Time.get_ticks_msec() / 1000.0


func _ready() -> void:
	scanline_logic = get_tree().root.find_child("ScanlineLogic", true, false)

	_audio_manager = get_tree().root.find_child("AudioManager", true, false)
	if not _audio_manager:
		print("[BlobRenderer] ERROR: No se encontró AudioManager")

	if IPCManager:
		IPCManager.pieces_updated.connect(_on_pieces_updated)
	else:
		print("[BlobRenderer] ERROR: No se encontró IPCManager")

	_start_usec = Time.get_ticks_usec()
	_cycle_usec = int(beats_per_cycle * 60.0 * 1000000.0 / maxf(bpm, 1.0))


func _sync_family_config() -> void:
	var new_bpm := GestorFamilias.get_bpm()
	var new_bpc := GestorFamilias.get_beats_per_cycle()
	if new_bpm != bpm:
		set_bpm(new_bpm)
	if new_bpc != beats_per_cycle:
		set_beats_per_cycle(new_bpc)


func _process(delta: float) -> void:
	_sync_family_config()

	if GestorFamilias.familia_activa != "familia_2":
		return

	frame += 1
	pattern_seed += delta * 0.8

	var elapsed_usec := Time.get_ticks_usec() - _start_usec
	var cycle_idx := elapsed_usec / _cycle_usec
	scan_progress = float(elapsed_usec % _cycle_usec) / float(_cycle_usec)

	if cycle_idx != _last_cycle_idx:
		_last_cycle_idx = cycle_idx
		_on_cycle_reset()

	for key in tracked_pieces:
		var bp: BlobPiece = tracked_pieces[key]
		bp.phase += delta * 0.5
		bp.energy *= 0.88
		if bp.cool > 0:
			bp.cool -= 1

	_check_scan_hits()

	var keep_trails: Array = []
	for t in _trails:
		t.life -= 0.002
		if t.life > 0:
			keep_trails.append(t)
	_trails = keep_trails

	var keep_waves: Array = []
	for w in _waves:
		w.r += w.speed * (1.0 + w.r / w.max_r * 0.9)
		var prog: float = w.r / w.max_r
		w.life = maxf(0.0, 1.0 - pow(prog, 0.6))
		if w.life > 0 and w.r < w.max_r * 1.1:
			keep_waves.append(w)
	_waves = keep_waves

	queue_redraw()


func _draw() -> void:
	if GestorFamilias.familia_activa != "familia_2":
		return

	_viewport = get_viewport_rect().size
	if _viewport.x <= 0 or _viewport.y <= 0:
		return

	var sx: float = scan_progress * _viewport.x

	_draw_background_trail()
	_draw_waves()
	_draw_trails()
	_draw_connections()
	_draw_blobs()
	_draw_labels()
	_draw_scanline(sx)


func _on_pieces_updated(new_pieces: Array) -> void:
	if GestorFamilias.familia_activa != "familia_2":
		return

	var ahora: float = Time.get_ticks_msec() / 1000.0
	var seen_keys: Dictionary = {}

	for p in new_pieces:
		var col: String = p.color
		if not GestorFamilias.is_in_family(col, "familia_2"):
			continue

		var key: String = str(col, "_", snapped(p.x, 0.015))
		seen_keys[key] = true

		if tracked_pieces.has(key):
			var bp: BlobPiece = tracked_pieces[key]
			bp.x = lerp(bp.x, p.x, 0.35)
			bp.y = lerp(bp.y, p.y, 0.35)
			bp.last_seen = ahora
		else:
			var bp := BlobPiece.new(tracked_pieces.size(), col, p.x, p.y)
			bp.last_seen = ahora
			tracked_pieces[key] = bp

	var expired: Array = []
	for key in tracked_pieces:
		if ahora - tracked_pieces[key].last_seen > PIECE_TIMEOUT:
			expired.append(key)
	for key in expired:
		tracked_pieces.erase(key)


func _on_cycle_reset() -> void:
	_trails.clear()
	_waves.clear()


const SCAN_THRESHOLD: float = 0.015

func _check_scan_hits() -> void:
	var piezas: Array = tracked_pieces.values()
	if piezas.is_empty():
		return

	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0:
		return

	for bp in piezas:
		if bp.cool > 0:
			continue

		var dist: float = abs(bp.x - scan_progress)
		if dist < SCAN_THRESHOLD:
			bp.energy = 1.0
			bp.cool = 7
			_hit_piece(bp, viewport_size)


func _hit_piece(bp: BlobPiece, viewport_size: Vector2) -> void:
	var center := Vector2(bp.x * viewport_size.x, bp.y * viewport_size.y)
	_spawn_effect_at(center, bp.color)
	if _audio_manager:
		_audio_manager.call("play_color", bp.color, bp.y)


func _spawn_effect_at(center: Vector2, color_name: String) -> void:
	var col_arr: Array = GestorFamilias.get_html_color(color_name)
	var drift_arr: Array = GestorFamilias.get_html_drift(color_name)

	var trails_count: int = 4
	var phase_base: float = randf() * TAU
	for k in range(trails_count):
		_trails.append({
			x = center.x,
			y = center.y,
			r = 30.0 + randf() * 20.0,
			col = col_arr.duplicate(),
			drift = drift_arr.duplicate(),
			phase = phase_base + float(k) * 0.4,
			life = 1.0,
		})

	var w_max_r: float = sqrt(_viewport.x * _viewport.x + _viewport.y * _viewport.y) * 0.85
	_waves.append({
		x = center.x,
		y = center.y,
		col = col_arr.duplicate(),
		drift = drift_arr.duplicate(),
		r = 0.0,
		max_r = w_max_r,
		life = 1.0,
		speed = 2.2 + randf() * 1.2,
		phase = randf() * TAU,
	})


func _find_piece(color: String, x: float, y: float) -> BlobPiece:
	var best: BlobPiece = null
	var best_dist: float = 0.05
	for key in tracked_pieces:
		var bp: BlobPiece = tracked_pieces[key]
		if bp.color != color:
			continue
		var dist: float = sqrt(pow(bp.x - x, 2.0) + pow(bp.y - y, 2.0))
		if dist < best_dist:
			best_dist = dist
			best = bp
	return best


static func lerp_col(a: Array, b: Array, t: float) -> Array:
	return [
		roundi(a[0] + (b[0] - a[0]) * t),
		roundi(a[1] + (b[1] - a[1]) * t),
		roundi(a[2] + (b[2] - a[2]) * t),
	]

static func _rgb(c: Array, a: float = 1.0) -> Color:
	return Color(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0, a)


static func _fbm(x: float, y: float, t: float) -> float:
	return (
		sin(x * 1.7 + t) * cos(y * 1.3 - t * 0.7)
		+ sin(x * 3.1 - t * 1.1) * 0.5
		+ cos(y * 2.9 + t * 0.4) * 0.25
	)


func _draw_background_trail() -> void:
	var bg_a: float = TRAIL_BG_ALPHA_NIGHT if is_night else TRAIL_BG_ALPHA_LIGHT
	var bg_col: Color
	if is_night:
		bg_col = Color(0.024, 0.024, 0.039, bg_a)
	else:
		bg_col = Color(0.91, 0.91, 0.94, bg_a)
	draw_rect(Rect2(0, 0, _viewport.x, _viewport.y), bg_col)


func _draw_trails() -> void:
	for t in _trails:
		var age: float = 1.0 - t.life
		var dc: Array = lerp_col(t.col, t.drift, 0.1 + age * 0.35)
		var alpha: float = t.life * 0.08
		var rr: float = t.r * (1.4 + age * 1.8)
		var col: Color = _rgb(dc, alpha)

		var pts: int = 14
		var poly: PackedVector2Array = []
		for j in range(pts):
			var ang: float = (float(j) / float(pts)) * TAU + t.phase + age * 0.2
			var n: float = 1.0 + sin(float(j) * 2.3 + age * 3.0 + t.phase) * 0.12
			var px: float = t.x + cos(ang) * rr * n
			var py: float = t.y + sin(ang) * rr * n * 0.86
			poly.append(Vector2(px, py))
		draw_colored_polygon(poly, col)


func _draw_waves() -> void:
	for w in _waves:
		var dc: Array = lerp_col(w.col, w.drift, (w.r / maxf(w.max_r, 1.0)) * 0.5)
		var pts: int = 24

		var alpha1: float = w.life * 0.025
		if alpha1 > 0.005:
			var col1: Color = _rgb(dc, alpha1)
			var poly1: PackedVector2Array = []
			for j in range(pts):
				var ang: float = (float(j) / float(pts)) * TAU + w.phase
				var n: float = 1.0 + sin(float(j) * 2.1 + w.r * 0.007 + w.phase) * (0.055 + w.life * 0.07)
				var px: float = w.x + cos(ang) * w.r * n
				var py: float = w.y + sin(ang) * w.r * n * 0.88
				poly1.append(Vector2(px, py))
			draw_colored_polygon(poly1, col1)

		var alpha2: float = w.life * 0.045
		if alpha2 > 0.005:
			var col2: Color = _rgb(dc, alpha2)
			var r2: float = w.r * 0.87
			var poly2: PackedVector2Array = []
			for j in range(pts):
				var ang: float = (float(j) / float(pts)) * TAU - w.phase * 0.6
				var n: float = 1.0 + sin(float(j) * 3.4 + w.r * 0.005) * 0.06
				var px: float = w.x + cos(ang) * r2 * n
				var py: float = w.y + sin(ang) * r2 * n * 0.9
				poly2.append(Vector2(px, py))
			draw_colored_polygon(poly2, col2)

		var alpha3: float = w.life * 0.03
		if alpha3 > 0.005:
			var col3: Color = _rgb(w.drift, alpha3)
			var r3: float = w.r * 0.93
			var poly3: PackedVector2Array = []
			for j in range(pts):
				var ang: float = (float(j) / float(pts)) * TAU + w.phase * 1.3
				var n: float = 1.0 + sin(float(j) * 1.8 + w.r * 0.009) * 0.07
				var px: float = w.x + cos(ang) * r3 * n
				var py: float = w.y + sin(ang) * r3 * n * 0.86
				poly3.append(Vector2(px, py))
			draw_colored_polygon(poly3, col3)


func _draw_connections() -> void:
	var blob_list: Array = tracked_pieces.values()
	for i in range(blob_list.size()):
		var a: BlobPiece = blob_list[i]
		var ax: float = a.x * _viewport.x
		var ay: float = a.y * _viewport.y
		var a_col_arr: Array = GestorFamilias.get_html_color(a.color)

		for j in range(i + 1, blob_list.size()):
			var b: BlobPiece = blob_list[j]
			var dx: float = (b.x - a.x) * _viewport.x
			var dy: float = (b.y - a.y) * _viewport.y
			var d: float = sqrt(dx * dx + dy * dy)
			var thr: float = (a.radius + b.radius) * connection_threshold

			if d < thr:
				var alpha: float = (1.0 - d / thr) * 0.1
				var col: Color = _rgb(a_col_arr, alpha * 0.6)
				draw_line(Vector2(ax, ay), Vector2(ax + dx, ay + dy), col, 0.35)


func _draw_blobs() -> void:
	for key in tracked_pieces:
		var bp: BlobPiece = tracked_pieces[key]
		var sx: float = bp.x * _viewport.x
		var sy: float = bp.y * _viewport.y
		_draw_blob(sx, sy, bp.radius, bp.color, bp.phase, bp.energy, bp.rings)


func _draw_blob(x: float, y: float, r: float, color_name: String, phase: float, energy: float, rings: int) -> void:
	var col_arr: Array = GestorFamilias.get_html_color(color_name)
	var drift_arr: Array = GestorFamilias.get_html_drift(color_name)
	var bc: Array = lerp_col(col_arr, drift_arr, 0.06 + energy * 0.22)

	for ring in range(rings, -1, -1):
		var rr: float = r * (1.0 + float(ring) * 0.72)
		var base_a: float = (0.48 - float(ring) * 0.08) * (0.22 + energy * 1.15)
		if base_a <= 0.0:
			continue
		base_a = clampf(base_a, 0.0, 1.0)

		var pts: int = 12 + ring * 3
		var poly: PackedVector2Array = []
		for i in range(pts + 1):
			var ang: float = (float(i) / float(pts)) * TAU + phase * (1.0 if ring % 2 == 0 else -0.55)
			var n1: float = sin(float(i) * 2.1 + float(frame) * 0.013 + phase) * (0.13 + energy * 0.22)
			var n2: float = sin(float(i) * 4.3 - float(frame) * 0.021 + phase * 1.7) * (0.06 + energy * 0.09)
			var n3: float = _fbm(cos(ang), sin(ang), float(frame) * 0.008 + float(ring)) * (0.05 + energy * 0.07)
			var nr: float = 1.0 + n1 + n2 + n3
			var px: float = x + cos(ang) * rr * nr
			var py: float = y + sin(ang) * rr * nr * 0.84
			poly.append(Vector2(px, py))

		var c: Color = _rgb(bc, base_a)
		draw_colored_polygon(poly, c)

	var glow_a: float = clampf(0.28 + energy * 0.38, 0.0, 1.0)
	var glow_col: Color = _rgb(bc, glow_a * 0.7)
	var glow_r: float = r * 0.35
	var glow_pts: int = 8
	var glow_poly: PackedVector2Array = []
	for i in range(glow_pts + 1):
		var ang: float = (float(i) / float(glow_pts)) * TAU + phase
		var nr: float = 1.0 + sin(float(i) * 3.1 + float(frame) * 0.02) * 0.15
		var px: float = x + cos(ang) * glow_r * nr
		var py: float = y + sin(ang) * glow_r * nr
		glow_poly.append(Vector2(px, py))
	draw_colored_polygon(glow_poly, glow_col)

	if energy > 0.3:
		var t_r: float = r * 0.9
		var t_poly: PackedVector2Array = []
		for i in range(12):
			var ang: float = (float(i) / 12.0) * TAU + phase
			var n: float = 1.0 + sin(float(i) * 1.5 + float(frame) * 0.01) * 0.1
			var px: float = x + cos(ang) * t_r * n
			var py: float = y + sin(ang) * t_r * n * 0.84
			t_poly.append(Vector2(px, py))
		var t_col: Color = _rgb(bc, energy * 0.04)
		draw_colored_polygon(t_poly, t_col)


func _draw_scanline(sx: float) -> void:
	var has_pieces: bool = tracked_pieces.size() > 0
	var base_a: float = 0.025 + (0.02 if has_pieces else 0.0)

	var layers: Array = [
		[scan_line_aura, base_a * 0.3],
		[scan_line_halo, base_a * 0.6],
		[scan_line_core, base_a * 1.0],
	]

	for layer in layers:
		var w: float = layer[0]
		var a: float = layer[1]
		if a <= 0.0:
			continue
		var col: Color = Color(1.0, 1.0, 1.0, a)
		draw_rect(Rect2(sx - w, 0, w * 2.0, _viewport.y), col)


func _draw_labels() -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return

	for key in tracked_pieces:
		var bp: BlobPiece = tracked_pieces[key]
		var sx: float = bp.x * _viewport.x
		var sy: float = bp.y * _viewport.y
		var col_arr: Array = GestorFamilias.get_html_color(bp.color)
		var col: Color = _rgb(col_arr, 0.7)
		var label_y: float = sy - bp.radius - 8.0
		var label_x: float = sx

		var atom_def: Dictionary = GestorFamilias.get_html_atom_def(bp.color)
		var freq: float = atom_def.get("freq", 0.0)
		var y_norm: float = 1.0 - bp.y
		var actual_freq: float = freq * (0.4 + y_norm * 2.2)
		var inst: String = atom_def.get("inst", "")
		var x_pct: int = roundi(bp.x * 100.0)
		var y_pct: int = roundi(y_norm * 100.0)

		var line1: String = "[%s]" % inst
		var line2: String = "[%d hz]" % roundi(actual_freq)
		var line3: String = "[x:%d%% y:%d%%]" % [x_pct, y_pct]

		var font_size: int = 7
		var line_h: float = 10.0

		draw_string(font, Vector2(label_x, label_y), line1, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, col)
		draw_string(font, Vector2(label_x, label_y + line_h), line2, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, col)
		draw_string(font, Vector2(label_x, label_y + line_h * 2.0), line3, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, col)

		var conn_y: float = label_y + line_h * 2.5
		var conn_col: Color = _rgb(col_arr, 0.2)
		draw_line(Vector2(label_x, conn_y), Vector2(sx, sy - bp.radius), conn_col, 0.5)


func toggle_mode() -> void:
	is_night = not is_night


func set_night(enabled: bool) -> void:
	is_night = enabled


func set_bpm(new_bpm: float) -> void:
	bpm = new_bpm
	_cycle_usec = int(beats_per_cycle * 60.0 * 1000000.0 / maxf(bpm, 1.0))


func set_beats_per_cycle(new_beats: int) -> void:
	beats_per_cycle = new_beats
	_cycle_usec = int(beats_per_cycle * 60.0 * 1000000.0 / maxf(bpm, 1.0))
