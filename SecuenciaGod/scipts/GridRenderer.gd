extends Node2D
class_name GridRenderer

enum NoteDivision {
	REDONDA = 1,
	BLANCA = 2,
	NEGRA = 4,
	CORCHEA = 8,
	SEMICORCHEA = 16,
}

@export var note_division: NoteDivision = NoteDivision.NEGRA
@export var grid_color: Color = Color(0.81,0.0,0.04)
@export var line_width: float = 2.0
@export var dash_length: float = 6.0
@export var gap_length: float = 4.0
@export var horizontal_rows: int = 4

func _draw() -> void:
	var viewport = get_viewport_rect().size
	if viewport.x <= 0 or viewport.y <= 0:
		return

	var divs = int(note_division)

	for i in range(divs + 1):
		var x = (float(i) / divs) * viewport.x
		_draw_dashed_line(Vector2(x, 0), Vector2(x, viewport.y), grid_color, line_width, dash_length, gap_length)

	for i in range(horizontal_rows + 1):
		var y = (float(i) / horizontal_rows) * viewport.y
		#_draw_dashed_line(Vector2(0, y), Vector2(viewport.x, y), grid_color, line_width, dash_length, gap_length)


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
