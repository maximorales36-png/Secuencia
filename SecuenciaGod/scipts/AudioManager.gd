extends Node
class_name AudioManager

var scanline_logic: ScanlineLogic
var color_cooldowns: Dictionary = {}

# Yellow monophonic state
var yellow_active: bool = false
var yellow_note: int = -1
const YELLOW_SWITCH_GROUP: String = "yellow_switch"
const YELLOW_SWITCH_VALUES: Array = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]


func _ready() -> void:
	Wwise.register_game_obj(self, "AudioManager")
	Wwise.load_bank("Main")
	Wwise.add_default_listener(self)

	scanline_logic = get_tree().root.find_child("ScanlineLogic", true, false)
	if scanline_logic:
		scanline_logic.crossing_detected.connect(_on_crossing_detected)
		scanline_logic.sector_activated.connect(_on_sector_activated)
		scanline_logic.cycle_reset.connect(_on_cycle_reset)
	else:
		print("[AudioManager] ERROR: No se encontr\u00f3 ScanlineLogic")


func _on_cycle_reset() -> void:
	color_cooldowns.clear()
	if yellow_active:
		yellow_active = false
		yellow_note = -1
		Wwise.post_event("Stop_yellow", self)


func _on_crossing_detected(piece: WebSocketManager.Piece) -> void:
	if piece.color == "yellow":
		_handle_yellow(piece.y)
	else:
		play_sound(piece.color, piece.y)


func _on_sector_activated(_sector_index: int, y: float, color: String) -> void:
	play_sound(color, y)


func _handle_yellow(y: float) -> void:
	var note = clampi(int(y * 8), 0, 7)
	if note == yellow_note and yellow_active:
		return
	yellow_note = note
	Wwise.set_switch(YELLOW_SWITCH_GROUP, YELLOW_SWITCH_VALUES[note], self)
	if not yellow_active:
		yellow_active = true
		Wwise.post_event("Play_yellow", self)


func play_sound(color: String, y_position: float) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if color_cooldowns.has(color) and now < color_cooldowns[color]:
		return

	var valid_colors = ["yellow", "orange", "pink", "celeste", "neon_green"]
	if not color in valid_colors:
		print("[AudioManager] Color inv\u00e1lido: %s" % color)
		return

	y_position = clampf(y_position, 0.0, 1.0)

	var event_name = "Play_" + _capitalize_color(color)
	var rtpc_value = y_position * 100.0

	Wwise.post_event(event_name, self)
	Wwise.set_rtpc_value("Timbre", rtpc_value, self)

	color_cooldowns[color] = now + scanline_logic.get_sector_duration()


func _capitalize_color(color: String) -> String:
	match color:
		"neon_green":
			return "Neon_Green"
		_:
			return color.capitalize()
