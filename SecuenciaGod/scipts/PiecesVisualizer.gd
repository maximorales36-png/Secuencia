extends Node2D
class_name PiecesVisualizer

@export var piece_radius: float = 40.0
@export var circle_color_default: Color = Color.WHITE
@export var text_color: Color = Color.WHITE
@export var text_size: int = 16

var ipc_manager: IPCManager
var pieces: Array = []
var connected: bool = false

# Mapeo de colores a colores Godot
var color_map: Dictionary = {
	"red": Color(1.0, 0.2, 0.2, 0.6),
	"pink": Color(1.0, 0.75, 0.8, 0.6),
	"green": Color(0.0, 1.0, 0.3, 0.6),
	"blue": Color(0.2, 0.5, 1.0, 0.7),
	"violet": Color(0.6, 0.2, 1.0, 0.6),
	"unknown": Color.GRAY,
	"white": Color(1.0, 1.0, 1.0, 0.5)
}


func _ready() -> void:
	ipc_manager = IPCManager
	if ipc_manager == null:
		return

	ipc_manager.pieces_updated.connect(_on_pieces_updated)
	ipc_manager.connection_changed.connect(_on_connection_changed)

	connected = ipc_manager.connected
	pieces = ipc_manager.pieces.duplicate()
	queue_redraw()


func _on_pieces_updated(new_pieces: Array) -> void:
	pieces = new_pieces
	queue_redraw()


func _on_connection_changed(connected_state: bool) -> void:
	connected = connected_state
	queue_redraw()


func _draw() -> void:
	var viewport_size = get_viewport_rect().size
	# Dibujar fondo de data status 

	draw_rect(Rect2(10, 10, 350, 90), Color(0, 0, 0, 0.5))

	var connection_text = "IPC: CONECTADO" if connected else "IPC: DESCONECTADO"
	var connection_color = Color.GREEN if connected else Color.RED
	draw_string(ThemeDB.fallback_font, Vector2(20, 25), connection_text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, connection_color)

	draw_string(ThemeDB.fallback_font, Vector2(20, 50), "Piezas detectadas: %d" % pieces.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, text_color)

	draw_string(ThemeDB.fallback_font, Vector2(20, 75), "FPS: %.0f" % Engine.get_frames_per_second(), HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, text_color)

	if not connected:
		draw_string(ThemeDB.fallback_font, Vector2(viewport_size.x / 2 - 150, viewport_size.y / 2), "Esperando conexion IPC...", HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color.GRAY)
		return

	if pieces.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(viewport_size.x / 2 - 150, viewport_size.y / 2), "Esperando piezas...", HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color.GRAY)
		return

	for piece in pieces:
		var screen_x = piece.x * viewport_size.x
		var screen_y = piece.y * viewport_size.y
		var pos = Vector2(screen_x, screen_y)

		var draw_color = color_map.get(piece.color, color_map["unknown"])

		draw_circle(pos, piece_radius, draw_color)
		draw_arc(pos, piece_radius + 2, 0, TAU, 32, color_map["white"], 2.0)

		var label_pos = pos + Vector2(0, piece_radius + 20)
		draw_string(ThemeDB.fallback_font, label_pos, piece.color, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, text_color)

		var coords_pos = pos + Vector2(0, piece_radius + 35)
		var coords_text = "%.2f, %.2f" % [piece.x, piece.y]
		draw_string(ThemeDB.fallback_font, coords_pos, coords_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.GRAY)
