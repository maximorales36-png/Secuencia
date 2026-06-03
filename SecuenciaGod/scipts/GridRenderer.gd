extends Node2D
class_name GridRenderer

@export var grid_color: Color = Color(0.81, 0.0, 0.04)
@export var line_width: float = 2.0
@export var dash_length: float = 6.0
@export var gap_length: float = 4.0

var scanline_logic: ScanlineLogic
var beats_per_cycle: int = 8


func _ready() -> void:
	scanline_logic = get_tree().root.find_child("ScanlineLogic", true, false)
	if scanline_logic:
		beats_per_cycle = scanline_logic.beats_per_cycle
		scanline_logic.beats_per_cycle_changed.connect(_on_beats_per_cycle_changed)


func _on_beats_per_cycle_changed(new_beats: int) -> void:
	beats_per_cycle = new_beats
	queue_redraw()


func _draw() -> void:
	var viewport = get_viewport_rect().size
	if viewport.x <= 0 or viewport.y <= 0:
		return

	var beat_value = 1.0
	var divs = int(beats_per_cycle / beat_value)

	for i in range(divs + 1):
		var x = (float(i) / divs) * viewport.x
		_draw_dashed_line(Vector2(x, 0), Vector2(x, viewport.y), grid_color, line_width, dash_length, gap_length)


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float, dash: float, gap: float) -> void:
	var direction = (to - from).normalized()
	var distance = from.distance_to(to)
	var step = dash + gap
	var pos = 0.0
	while pos < distance:
		var seg_start = from + direction * pos
		var seg_end = from + direction * min(pos + dash, distance)
		draw_line(seg_start, seg_end, color, width)
		pos += step
