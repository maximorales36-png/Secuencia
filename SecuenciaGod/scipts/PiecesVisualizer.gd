extends Node2D
## PiecesVisualizer
## Dibuja las piezas detectadas en pantalla
## Útil para debuggear la comunicación WebSocket

class_name PiecesVisualizer

@export var piece_radius: float = 40.0
@export var circle_color_default: Color = Color.WHITE
@export var text_color: Color = Color.WHITE
@export var text_size: int = 16

var websocket_manager: WebSocketManager
var pieces: Array = []
var connected: bool = false

# Mapeo de colores a colores Godot
var color_map: Dictionary = {
	"yellow": Color(1.0, 1.0, 0.0, 0.3),
	"orange": Color(1.0, 0.5, 0.0, 0.6),
	"pink": Color(1.0, 0.75, 0.8, 0.6),
	"neon_green": Color(0.0, 1.0, 0.5, 0.6),
	"celeste":Color(0.32, 0.82, 0.96, 0.7),
	"unknown": Color.GRAY,
	"white": Color(1.0, 1.0, 1.0, 0.5)
}

func _ready() -> void:
	print("[PiecesVisualizer] Inicializando...")
	
	# Buscar WebSocketManager en la escena
	websocket_manager = get_tree().root.find_child("WebSocketManager", true, false)
	
	if websocket_manager == null:
		print("[PiecesVisualizer] ERROR: No encontré WebSocketManager en la escena")
		return
	
	# Conectar signals
	websocket_manager.pieces_updated.connect(_on_pieces_updated)
	websocket_manager.connection_changed.connect(_on_connection_changed)
	
	print("[PiecesVisualizer] Listo")

func _on_pieces_updated(new_pieces: Array) -> void:
	pieces = new_pieces
	queue_redraw()

func _on_connection_changed(connected_state: bool) -> void:
	connected = connected_state
	queue_redraw()

func _draw() -> void:
	var viewport_size = get_viewport_rect().size
	
	# Dibujar fondo de info
	draw_rect(Rect2(10, 10, 350, 90), Color(0, 0, 0, 0.7))
	
	# Información de conexión
	var connection_text = "WebSocket: CONECTADO" if connected else "WebSocket: DESCONECTADO"
	var connection_color = Color.GREEN if connected else Color.RED
	draw_string(ThemeDB.fallback_font, Vector2(20, 25), connection_text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, connection_color)
	
	# Contador de piezas
	draw_string(ThemeDB.fallback_font, Vector2(20, 50), "Piezas detectadas: %d" % pieces.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, text_color)
	
	# FPS
	draw_string(ThemeDB.fallback_font, Vector2(20, 75), "FPS: %.0f" % Engine.get_frames_per_second(), HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, text_color)
	
	# Si no hay conexión, mostrar mensaje
	if not connected:
		draw_string(ThemeDB.fallback_font, Vector2(viewport_size.x / 2 - 150, viewport_size.y / 2), "Esperando conexión...", HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color.GRAY)
		return
	
	# Si no hay piezas
	if pieces.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(viewport_size.x / 2 - 150, viewport_size.y / 2), "Esperando piezas...", HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color.GRAY)
		return
	
	# Dibujar cada pieza
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
