extends Node
class_name AudioManager

var scanline_logic: ScanlineLogic


func _ready() -> void:
	Wwise.register_game_obj(self, "AudioManager")
	Wwise.load_bank("Main")
	Wwise.add_default_listener(self)

	scanline_logic = get_tree().root.find_child("ScanlineLogic", true, false)
	if scanline_logic:
		scanline_logic.crossing_detected.connect(_on_crossing_detected)
	else:
		print("[AudioManager] ERROR: No se encontr\u00f3 ScanlineLogic")
	

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

	Wwise.post_event(event_name, self)
	Wwise.set_rtpc_value("Timbre", rtpc_value, self)


func _capitalize_color(color: String) -> String:
	match color:
		"neon_green":
			return "Neon_Green"
		_:
			return color.capitalize()
