extends Node2D
class_name EffectsRenderer

var scanline_logic: ScanlineLogic
var scan_position: float = 0.0

var active_effects: Array = []

@export var effect_duration: float = 0.5
@export var max_wave_radius: float = 150.0
@export var particle_count: int = 20
@export var scan_line_color: Color = Color.WHITE
@export var scan_line_width: float = 3.0


func _ready() -> void:
	scanline_logic = get_tree().root.find_child("ScanlineLogic", true, false)
	if scanline_logic:
		scanline_logic.crossing_detected.connect(_on_crossing_detected)
	else:
		print("[EffectsRenderer] ERROR: No se encontr\u00f3 ScanlineLogic")


func _process(delta: float) -> void:
	if scanline_logic:
		scan_position = scanline_logic.get_scan_position()
	_update_effects(delta)
	queue_redraw()


func _on_crossing_detected(piece: WebSocketManager.Piece) -> void:
	var viewport = get_viewport_rect().size
	active_effects.append({
		piece = piece,
		start_time = Time.get_ticks_msec() / 1000.0,
		center = Vector2(piece.x * viewport.x, piece.y * viewport.y)
	})
	print("[EffectsRenderer] Efecto disparado: %s en (%.2f, %.2f)" % [piece.color, piece.x, piece.y])


func _update_effects(delta: float) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	var keep: Array = []
	for effect in active_effects:
		if now - effect.start_time < effect_duration:
			keep.append(effect)
	active_effects = keep


func _draw() -> void:
	_draw_scanline()
	_draw_effects()


func _draw_scanline() -> void:
	var viewport = get_viewport_rect().size
	var x = scan_position * viewport.x
	draw_line(Vector2(x, 0), Vector2(x, viewport.y), scan_line_color, scan_line_width)


func _draw_effects() -> void:
	var now = Time.get_ticks_msec() / 1000.0
	for effect in active_effects:
		var elapsed = now - effect.start_time
		var intensity = 1.0 - (elapsed / effect_duration)
		var center = effect.center
		var color_name = effect.piece.color

		match color_name:
			"yellow":
				_draw_yellow_effect(center, intensity)
			"orange":
				_draw_orange_effect(center, intensity)
			"pink":
				_draw_pink_effect(center, intensity)
			"neon_green":
				_draw_neon_green_effect(center, intensity)


func _draw_yellow_effect(center: Vector2, intensity: float) -> void:
	var color = Color.YELLOW
	color.a = intensity
	var radius = max_wave_radius * (1.0 - intensity)
	draw_circle(center, radius, color)
	draw_arc(center, radius * 1.3, 0, TAU, 32, color, 2.0 * intensity)
	draw_arc(center, radius * 1.6, 0, TAU, 32, color, 1.0 * intensity)


func _draw_orange_effect(center: Vector2, intensity: float) -> void:
	var color = Color(1.0, 0.5, 0.0)
	color.a = intensity
	for i in range(particle_count):
		var angle = (i * TAU / particle_count) + (1.0 - intensity) * 3.0
		var dist = 60.0 * (1.0 - intensity)
		var pos = center + Vector2(cos(angle), sin(angle)) * dist
		var size = 4.0 * intensity
		draw_circle(pos, max(size, 1.0), color)


func _draw_pink_effect(center: Vector2, intensity: float) -> void:
	var color = Color(1.0, 0.75, 0.8)
	color.a = intensity * 0.5
	var radius = max_wave_radius * (1.0 - intensity) * 0.8
	draw_circle(center, radius, color)
	draw_arc(center, radius * 1.5, 0, TAU, 48, Color.WHITE, 1.0 * intensity)


func _draw_neon_green_effect(center: Vector2, intensity: float) -> void:
	var color = Color(0.0, 1.0, 0.5)
	color.a = intensity
	var radius = 20.0 + 80.0 * (1.0 - intensity)
	draw_circle(center, radius, color)
	var glow = Color(0.0, 1.0, 0.5)
	glow.a = intensity * 0.3
	draw_circle(center, radius * 1.5, glow)
