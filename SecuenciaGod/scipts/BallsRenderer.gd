extends Node2D
class_name BallsRenderer

@export var ball_count: int = 7
@export var ball_radius: float = 14.0
@export var piece_hit_radius: float = 45.0
@export var ball_speed_factor: float = 0.25
@export var background_noise_spacing: float = 16.0
@export var piece_glow_radius: float = 140.0
@export var trail_length: int = 6

var balls: Array = []
var trails: Array = []
var _audio_manager: Node = null
var pattern_seed: float = 0.0
var frame: int = 0
var _viewport: Vector2 = Vector2.ZERO
var _last_hit_times: Dictionary = {}
var _pieces: Array = []

var _hit_waves: Array = []
var _hit_trails: Array = []
var _fading_pieces: Dictionary = {}  # key -> {color, x, y, alpha}


func _ready() -> void:
	_audio_manager = get_tree().root.find_child("AudioManager", true, false)
	if IPCManager:
		IPCManager.pieces_updated.connect(_on_pieces_updated)
		_pieces = IPCManager.pieces.duplicate()
	_init_balls()


func _on_pieces_updated(new_pieces: Array) -> void:
	var old_active: Dictionary = {}
	for piece in _pieces:
		var key: String = str(piece.color, "_", snapped(piece.x, 0.01), "_", snapped(piece.y, 0.01))
		old_active[key] = piece

	_pieces = new_pieces

	var new_active: Dictionary = {}
	for piece in _pieces:
		var key: String = str(piece.color, "_", snapped(piece.x, 0.01), "_", snapped(piece.y, 0.01))
		new_active[key] = piece

	for key in old_active:
		if not new_active.has(key):
			var p = old_active[key]
			_fading_pieces[key] = { color = p.color, x = p.x, y = p.y, alpha = 1.0 }

	for key in new_active:
		if _fading_pieces.has(key):
			_fading_pieces.erase(key)


func _init_balls() -> void:
	await get_tree().process_frame
	var vp := get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		vp = Vector2(1920, 1080)

	var fixed_speed := minf(vp.x, vp.y) * ball_speed_factor
	balls.clear()

	for i in range(ball_count):
		var angle := (float(i) / float(ball_count)) * TAU + randf() * 0.3
		var pos := Vector2(randf() * vp.x, randf() * vp.y)
		var vel := Vector2(cos(angle), sin(angle)) * fixed_speed
		balls.append({ pos = pos, vel = vel })
		trails.append([])


func _process(delta: float) -> void:
	if GestorFamilias.familia_activa != "familia_4":
		return

	frame += 1
	pattern_seed += delta * 0.25
	_viewport = get_viewport_rect().size
	if _viewport.x <= 0 or _viewport.y <= 0:
		return

	for i in range(balls.size()):
		_update_ball(i, delta)

	_update_hit_effects(delta)
	_update_fading_pieces(delta)

	queue_redraw()


func _update_ball(idx: int, delta: float) -> void:
	var ball = balls[idx]
	ball.pos += ball.vel * delta

	if ball.pos.x < ball_radius:
		ball.pos.x = ball_radius
		ball.vel.x = abs(ball.vel.x)
	elif ball.pos.x > _viewport.x - ball_radius:
		ball.pos.x = _viewport.x - ball_radius
		ball.vel.x = -abs(ball.vel.x)

	if ball.pos.y < ball_radius:
		ball.pos.y = ball_radius
		ball.vel.y = abs(ball.vel.y)
	elif ball.pos.y > _viewport.y - ball_radius:
		ball.pos.y = _viewport.y - ball_radius
		ball.vel.y = -abs(ball.vel.y)

	var now: float = Time.get_ticks_msec() / 1000.0
	var beat_interval: float = 60.0 / 72.0

	for piece in _pieces:
		if not GestorFamilias.is_in_family(piece.color, "familia_4"):
			continue

		var piece_pos: Vector2 = Vector2(piece.x * _viewport.x, piece.y * _viewport.y)
		var dist: float = ball.pos.distance_to(piece_pos)
		var hit_radius: float = piece_hit_radius + ball_radius

		if dist >= hit_radius:
			continue

		var last_hit: float = _last_hit_times.get(piece.color, -beat_interval)
		if now - last_hit < beat_interval * 0.5:
			continue

		_last_hit_times[piece.color] = now

		var normal: Vector2 = (ball.pos - piece_pos).normalized()
		ball.vel = ball.vel.reflect(normal)
		if ball.vel.length() < 10.0:
			ball.vel = normal * minf(_viewport.x, _viewport.y) * ball_speed_factor
		ball.pos = piece_pos + normal * (hit_radius + 2.0)

		if _audio_manager:
			_audio_manager.call("schedule_f4_hit", piece.color, piece.y)

		var center := Vector2(piece.x * _viewport.x, piece.y * _viewport.y)
		_spawn_hit_effect(center, piece.color)

	var trail = trails[idx]
	trail.append({ pos = ball.pos, time = now })
	while trail.size() > trail_length:
		trail.pop_front()


func _draw() -> void:
	if GestorFamilias.familia_activa != "familia_4":
		return

	_viewport = get_viewport_rect().size
	if _viewport.x <= 0 or _viewport.y <= 0:
		return

	_draw_background_fill()
	_draw_background_noise()
	_draw_hit_trails()
	_draw_hit_waves()
	for piece in _pieces:
		if GestorFamilias.is_in_family(piece.color, "familia_4"):
			_draw_piece(piece, 1.0)
	for key in _fading_pieces:
		var f = _fading_pieces[key]
		_draw_piece(f, f.alpha)
	for i in range(balls.size()):
		_draw_trail(i)
		_draw_ball(i)


func _draw_background_noise() -> void:
	var alpha := 0.025
	var spacing := background_noise_spacing
	var cx := 0.0

	while cx < _viewport.x:
		var cy := 0.0
		while cy < _viewport.y:
			var noise := _fbm(cx * 0.004, cy * 0.004, pattern_seed)
			if noise > 0.2:
				var c := Color(0.2, 0.25, 0.35, alpha * noise * 2.0)
				draw_circle(Vector2(cx, cy), 1.5, c)
			cy += spacing
		cx += spacing


func _draw_piece(piece, alpha_mult: float = 1.0) -> void:
	var center := Vector2(piece.x * _viewport.x, piece.y * _viewport.y)
	var base_color := GestorFamilias.get_color(piece.color)
	var layers := [
		{ "radius": piece_glow_radius, "alpha": 0.04, "segments": 20 },
		{ "radius": piece_glow_radius * 0.65, "alpha": 0.07, "segments": 16 },
		{ "radius": piece_glow_radius * 0.35, "alpha": 0.12, "segments": 12 },
		{ "radius": piece_glow_radius * 0.18, "alpha": 0.25, "segments": 8 },
	]

	for layer in layers:
		var pts = layer.segments
		var r = layer.radius
		var a = layer.alpha * alpha_mult
		var poly := PackedVector2Array()

		for j in range(pts + 1):
			var ang := (float(j) / float(pts)) * TAU
			var nx := cos(ang) + pattern_seed
			var ny := sin(ang) + pattern_seed * 0.7
			var noise := _fbm(nx, ny, pattern_seed * 0.5)
			var deform := 1.0 + noise * 0.12
			var px: float = center.x + cos(ang) * r * deform
			var py: float = center.y + sin(ang) * r * deform
			poly.append(Vector2(px, py))

		var c := base_color
		c.a = a
		draw_colored_polygon(poly, c)


func _draw_ball(idx: int) -> void:
	var ball = balls[idx]
	var speed: float = ball.vel.length()
	var intensity := clampf(speed / (minf(_viewport.x, _viewport.y) * ball_speed_factor), 0.3, 1.0)

	var glow_color := Color(1.0, 1.0, 1.0, 0.08 * intensity)
	draw_circle(ball.pos, ball_radius * 2.5, glow_color)

	var ball_color := Color(1.0, 1.0, 1.0, 0.85 * intensity)
	draw_circle(ball.pos, ball_radius, ball_color)

	var highlight := Color(1.0, 1.0, 1.0, 0.4 * intensity)
	draw_circle(ball.pos, ball_radius * 0.45, highlight)


func _draw_trail(idx: int) -> void:
	var trail = trails[idx]

	for i in range(trail.size()):
		var t = trail[i]
		var age := float(i) / float(trail.size())
		var alpha := (1.0 - age) * 0.06
		var r := ball_radius * (0.3 + age * 0.7)
		var c := Color(1.0, 1.0, 1.0, alpha)
		draw_circle(t.pos, r, c)


func _draw_background_fill() -> void:
	var bg := Color(0.024, 0.024, 0.039, 0.15)
	draw_rect(Rect2(Vector2.ZERO, _viewport), Color(0.02, 0.02, 0.035, 1.0))
	draw_rect(Rect2(Vector2.ZERO, _viewport), bg)


func _spawn_hit_effect(center: Vector2, color_name: String) -> void:
	var col_arr: Array = GestorFamilias.get_html_color(color_name)
	var drift_arr: Array = GestorFamilias.get_html_drift(color_name)

	var trails_count: int = 4
	var phase_base: float = randf() * TAU
	for k in range(trails_count):
		_hit_trails.append({
			x = center.x, y = center.y,
			r = 30.0 + randf() * 20.0,
			col = col_arr.duplicate(),
			drift = drift_arr.duplicate(),
			phase = phase_base + float(k) * 0.4,
			life = 1.0,
		})

	var w_max_r: float = sqrt(_viewport.x * _viewport.x + _viewport.y * _viewport.y) * 0.85
	_hit_waves.append({
		x = center.x, y = center.y,
		col = col_arr.duplicate(),
		drift = drift_arr.duplicate(),
		r = 0.0, max_r = w_max_r,
		life = 1.0, speed = 2.2 + randf() * 1.2,
		phase = randf() * TAU,
	})


func _update_hit_effects(delta: float) -> void:
	var keep_trails: Array = []
	for t in _hit_trails:
		t.life -= 0.008
		if t.life > 0:
			keep_trails.append(t)
	_hit_trails = keep_trails

	var keep_waves: Array = []
	for w in _hit_waves:
		w.r += w.speed * (1.0 + w.r / w.max_r * 0.9)
		var prog: float = w.r / w.max_r
		w.life = maxf(0.0, 1.0 - pow(prog, 0.6))
		if w.life > 0 and w.r < w.max_r * 1.1:
			keep_waves.append(w)
	_hit_waves = keep_waves


func _update_fading_pieces(delta: float) -> void:
	var keep: Dictionary = {}
	for key in _fading_pieces:
		var f = _fading_pieces[key]
		f.alpha -= delta * 3.0
		if f.alpha > 0.0:
			keep[key] = f
	_fading_pieces = keep


func _draw_hit_trails() -> void:
	for t in _hit_trails:
		var age: float = 1.0 - t.life
		var dc: Array = _lerp_col(t.col, t.drift, 0.1 + age * 0.35)
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


func _draw_hit_waves() -> void:
	for w in _hit_waves:
		var dc: Array = _lerp_col(w.col, w.drift, (w.r / maxf(w.max_r, 1.0)) * 0.5)
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


static func _lerp_col(a: Array, b: Array, t: float) -> Array:
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
