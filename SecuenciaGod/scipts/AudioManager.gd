extends Node
class_name AudioManager

var scanline_logic: ScanlineLogic
var color_cooldowns: Dictionary = {}
var _sector_colors_triggered: Dictionary = {}

# Violet RTPC
var _violet_current: float = 100.0
var _violet_target: float = 100.0
const VIOLET_RTPC_NAME: String = "RTPC_Violet"

# Green RTPC
var _green_current: float = 100.0
var _green_target: float = 100.0
const GREEN_RTPC_NAME: String = "RTPC_N_Green"

# Pink RTPC
var _pink_current: float = 100.0
var _pink_target: float = 100.0
const PINK_RTPC_NAME: String = "RTPC_Pink"

# Presence RTPCs (Familia 1)
const PINK_V_RTPC_NAME: String = "RTPC_V_Pink"
const CELESTE_V_RTPC_NAME: String = "RTPC_V_Celeste"
const YELLOW_V_RTPC_NAME: String = "RTPC_V_Yellow"


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
		print("[AudioManager] ERROR: No se encontró ScanlineLogic")

	if GestorFamilias.familia_activa == "familia_1":
		Wwise.post_event("Play_all", self)


func _exit_tree() -> void:
	if GestorFamilias.familia_activa == "familia_1":
		Wwise.post_event("Stop_all", self)


func _process(delta: float) -> void:
	_update_violet_rtpc(delta)
	_update_green_rtpc(delta)
	_update_pink_rtpc(delta)
	_update_presence_rtpcs(delta)


## Smooths and sends the Violet RTPC value to Wwise.
func _get_highest_y_for(color: String) -> float:
	if scanline_logic == null:
		return -1.0
	var highest := 1.0
	var found := false
	for piece in scanline_logic.pieces:
		if piece.color == color and piece.y < highest:
			highest = piece.y
			found = true
	return highest if found else -1.0


func _update_violet_rtpc(delta: float) -> void:
	if scanline_logic == null:
		return
	var highest_y := _get_highest_y_for("violet")
	if highest_y >= 0.0:
		_violet_target = (1.0 - highest_y) * 100.0
	else:
		_violet_target = 100.0
	var smoothing := 1.0 - exp(-delta * 1.0)
	_violet_current = lerp(_violet_current, _violet_target, smoothing)
	Wwise.set_rtpc_value(VIOLET_RTPC_NAME, _violet_current, self)


func _update_green_rtpc(delta: float) -> void:
	if scanline_logic == null:
		return
	var highest_y := _get_highest_y_for("neon_green")
	if highest_y >= 0.0:
		_green_target = (1.0 - highest_y) * 100.0
	else:
		_green_target = 100.0
	var smoothing := 1.0 - exp(-delta * 0.5)
	_green_current = lerp(_green_current, _green_target, smoothing)
	Wwise.set_rtpc_value(GREEN_RTPC_NAME, _green_current, self)


func _update_pink_rtpc(delta: float) -> void:
	if scanline_logic == null:
		return
	var highest_y := _get_highest_y_for("pink")
	if highest_y >= 0.0:
		_pink_target = (1.0 - highest_y) * 100.0
	else:
		_pink_target = 100.0
	var smoothing := 1.0 - exp(-delta * 0.5)
	_pink_current = lerp(_pink_current, _pink_target, smoothing)
	Wwise.set_rtpc_value(PINK_RTPC_NAME, _pink_current, self)


func _update_presence_rtpcs(delta: float) -> void:
	if GestorFamilias.familia_activa != "familia_1":
		return
	if scanline_logic == null:
		return

	var current_sector: int = int(scanline_logic.scan_position * scanline_logic.sector_count)
	var sector_data: Dictionary = scanline_logic.sector_colors.get(current_sector, {})
	var pink_in_zone: bool = sector_data.has("pink")
	var celeste_in_zone: bool = sector_data.has("celeste")

	Wwise.set_rtpc_value(PINK_V_RTPC_NAME, 100.0 if pink_in_zone else 0.0, self)
	Wwise.set_rtpc_value(CELESTE_V_RTPC_NAME, 100.0 if celeste_in_zone else 0.0, self)


func _on_cycle_reset() -> void:
	color_cooldowns.clear()
	_sector_colors_triggered.clear()
	if GestorFamilias.familia_activa == "familia_1":
		Wwise.set_rtpc_value(YELLOW_V_RTPC_NAME, 0.0, self)


func _on_crossing_detected(piece: IPCManager.Piece) -> void:
	if GestorFamilias.familia_activa != "familia_1":
		_play_sound(piece.color, piece.y)
		return
	if piece.color == "yellow":
		Wwise.set_rtpc_value(YELLOW_V_RTPC_NAME, 100.0, self)
	elif piece.color == "violet":
		return
	else:
		_play_sound(piece.color, piece.y)


func _on_sector_activated(sector_index: int, y: float, color: String) -> void:
	if _sector_colors_triggered.has(color):
		return
	_sector_colors_triggered[color] = true

	if GestorFamilias.familia_activa == "familia_1" and color in ["pink", "celeste"]:
		return

	_play_sound(color, y, sector_index)


func _play_sound(color: String, y_position: float, sector_index: int = -1) -> void:
	if not GestorFamilias.is_in_active_family(color):
		print("[AudioManager] Color '%s' no está en la familia activa" % color)
		return

	var now := Time.get_ticks_msec() / 1000.0
	var cooldown_key: String = color if sector_index < 0 else str(sector_index) + "_" + color
	if color_cooldowns.has(cooldown_key) and now < color_cooldowns[cooldown_key]:
		return

	y_position = clampf(y_position, 0.0, 1.0)

	var event_name: String = GestorFamilias.get_sound(color)
	if event_name.is_empty():
		print("[AudioManager] No hay evento Wwise configurado para '%s'" % color)
		return

	Wwise.post_event(event_name, self)
	Wwise.set_rtpc_value("Timbre", y_position * 100.0, self)

	color_cooldowns[cooldown_key] = now + scanline_logic.get_sector_duration()
