extends Node
class_name AudioManager

var scanline_logic: ScanlineLogic
var wwise_available: bool = false


func _ready() -> void:
	wwise_available = _check_wwise()
	if wwise_available:
		print("[AudioManager] Wwise disponible.")
	else:
		print("[AudioManager] Wwise no disponible. Usando modo debug (solo logs).")

	scanline_logic = get_tree().root.find_child("ScanlineLogic", true, false)
	if scanline_logic:
		scanline_logic.crossing_detected.connect(_on_crossing_detected)
	else:
		print("[AudioManager] ERROR: No se encontr\u00f3 ScanlineLogic")


func _check_wwise() -> bool:
	# Wwise se registra como autoload "Wwise" si el addon est\u00e1 instalado
	return has_node("/root/Wwise")


func _on_crossing_detected(piece: WebSocketManager.Piece) -> void:
	play_sound(piece.color, piece.y)


func play_sound(color: String, y_position: float) -> void:
	var valid_colors = ["yellow", "orange", "pink", "neon_green"]
	if not color in valid_colors:
		print("[AudioManager] Color inv\u00e1lido: %s" % color)
		return

	y_position = clampf(y_position, 0.0, 1.0)

	var event_name = "Play_" + _capitalize_color(color)
	var rtpc_value = y_position * 100.0

	if wwise_available:
		Wwise.post_event(event_name, self)
		Wwise.set_rtpc_value("Timbre", rtpc_value, self)
	else:
		print("[AudioManager] Debug: Evento=%s, Timbre=%.1f" % [event_name, rtpc_value])

	print("[AudioManager] Sound triggered: %s (y=%.2f, timbre=%.1f)" % [event_name, y_position, rtpc_value])


func _capitalize_color(color: String) -> String:
	match color:
		"neon_green":
			return "Neon_Green"
		_:
			return color.capitalize()
