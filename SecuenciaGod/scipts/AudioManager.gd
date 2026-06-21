extends Node
class_name AudioManager

var scanline_logic: ScanlineLogic
var color_cooldowns: Dictionary = {}
var _sector_colors_triggered: Dictionary = {}

# Violet RTPC
var _violet_current: float = 100.0
var _violet_target: float = 100.0
const VIOLET_RTPC_NAME: String = "RTPC_Violet"

const GREEN_RTPC_NAME: String = "RTPC_N_Green"
const PINK_RTPC_NAME: String = "RTPC_Pink"

# Presence RTPCs (Familia 1)
const PINK_V_RTPC_NAME: String = "RTPC_V_Pink"
const CELESTE_V_RTPC_NAME: String = "RTPC_V_Celeste"
const YELLOW_V_RTPC_NAME: String = "RTPC_V_Yellow"

const RTPC_RAMP_SPEED: float = 1000.0  # 0→100 en 100ms
var _pink_v_value: float = 0.0
var _celeste_v_value: float = 0.0
var _yellow_v_value: float = 0.0
var _yellow_v_target: float = 0.0

# F4 RTPCs
const F4_PINK_RTPC: String = "RTPC_F4_Pink"
const F4_YELLOW_RTPC: String = "RTPC_F4_Yellow"
const F4_N_GREEN_RTPC: String = "RTPC_F4_N_Green"
const F4_CELESTE_RTPC: String = "RTPC_F4_Celeste"


# F4 beat clock & queue
var _f4_hit_queue: Array = []
var _f4_next_beat_time: float = 0.0
var _f4_beat_interval: float = 60.0 / 72.0
var _f4_initialized: bool = false


func _ready() -> void:
	Wwise.register_game_obj(self, "AudioManager")
	if not GestorFamilias.wwise_main_bank_loaded:
		Wwise.load_bank("Main")
		GestorFamilias.wwise_main_bank_loaded = true
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
	if GestorFamilias.familia_activa == "familia_4":
		_process_f4(delta)
		return
	_update_violet_rtpc(delta)
	_update_presence_rtpcs(delta)
	_update_yellow_rtpc(delta)


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


func _ramp(current: float, target: float, delta: float) -> float:
	if current < target:
		return min(current + RTPC_RAMP_SPEED * delta, target)
	else:
		return max(current - RTPC_RAMP_SPEED * delta, target)


func _update_yellow_rtpc(delta: float) -> void:
	if GestorFamilias.familia_activa != "familia_1":
		return
	_yellow_v_value = _ramp(_yellow_v_value, _yellow_v_target, delta)
	Wwise.set_rtpc_value(YELLOW_V_RTPC_NAME, _yellow_v_value, self)


func _update_presence_rtpcs(delta: float) -> void:
	if GestorFamilias.familia_activa != "familia_1":
		return
	if scanline_logic == null or scanline_logic.scan_speed == 0.0:
		return

	var sector_count: int = scanline_logic.sector_count
	var current_sector: int = int(scanline_logic.scan_position * sector_count)
	var sector_width: float = 1.0 / sector_count
	var pos_in_sector: float = fmod(scanline_logic.scan_position, sector_width)
	var dist_to_boundary: float = sector_width - pos_in_sector
	var time_to_boundary: float = dist_to_boundary / scanline_logic.scan_speed
	var next_sector: int = (current_sector + 1) % sector_count

	var current_data: Dictionary = scanline_logic.sector_colors.get(current_sector, {})
	var next_data: Dictionary = scanline_logic.sector_colors.get(next_sector, {})

	var pink_target: float = 100.0 if (current_data.has("pink") or (next_data.has("pink") and time_to_boundary <= 0.1)) else 0.0
	_pink_v_value = _ramp(_pink_v_value, pink_target, delta)
	Wwise.set_rtpc_value(PINK_V_RTPC_NAME, _pink_v_value, self)

	var celeste_target: float = 100.0 if (current_data.has("celeste") or (next_data.has("celeste") and time_to_boundary <= 0.1)) else 0.0
	_celeste_v_value = _ramp(_celeste_v_value, celeste_target, delta)
	Wwise.set_rtpc_value(CELESTE_V_RTPC_NAME, _celeste_v_value, self)


func _on_cycle_reset() -> void:
	color_cooldowns.clear()
	_sector_colors_triggered.clear()
	_yellow_v_target = 0.0


func _on_crossing_detected(piece: IPCManager.Piece) -> void:
	if GestorFamilias.familia_activa != "familia_1":
		return
	if piece.color == "yellow":
		_yellow_v_target = 100.0
		var yellow_switch: int = clampi(int((1.0 - piece.y) * 8.0), 0, 7)
		var switch_names: Array[String] = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]
		Wwise.set_switch("yellow_switch", switch_names[yellow_switch], self)
		return
	elif piece.color == "violet":
		return
	else:
		_play_sound(piece.color, piece.y)


func _on_sector_activated(sector_index: int, y: float, color: String) -> void:
	if GestorFamilias.familia_activa != "familia_1":
		return
	var key = str(sector_index) + "_" + color
	if _sector_colors_triggered.has(key):
		return
	_sector_colors_triggered[key] = true

	if color == "pink":
		Wwise.set_rtpc_value(PINK_RTPC_NAME, (1.0 - y) * 100.0, self)

	if GestorFamilias.familia_activa == "familia_1" and color in ["pink", "celeste"]:
		return

	_play_sound(color, y, sector_index)


func play_color(color: String, y: float) -> void:
	_play_sound(color, y)


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

	if color == "neon_green":
		Wwise.set_rtpc_value(GREEN_RTPC_NAME, (1.0 - y_position) * 100.0, self)

	color_cooldowns[cooldown_key] = now + scanline_logic.get_sector_duration()


func schedule_f4_hit(color: String, y: float) -> void:
	if GestorFamilias.familia_activa != "familia_4":
		return
	if not GestorFamilias.is_in_active_family(color):
		return

	if not _f4_initialized:
		var now := Time.get_ticks_msec() / 1000.0
		var current_beat := int(now / _f4_beat_interval)
		_f4_next_beat_time = (current_beat + 1) * _f4_beat_interval
		_f4_initialized = true

	_f4_hit_queue.append({ color = color, y = y })


func _process_f4(_delta: float) -> void:
	if not _f4_initialized:
		return

	var now := Time.get_ticks_msec() / 1000.0

	while _f4_next_beat_time <= now:
		var current_hits := _f4_hit_queue.duplicate()
		_f4_hit_queue.clear()
		for hit in current_hits:
			_play_f4_sound(hit.color, hit.y)
		_f4_next_beat_time += _f4_beat_interval


func _play_f4_sound(color: String, y: float) -> void:
	var event_name: String = GestorFamilias.get_sound(color)
	if event_name.is_empty():
		return

	y = clampf(y, 0.0, 1.0)
	var rtpc_value := (1.0 - y) * 100.0

	Wwise.post_event(event_name, self)

	match color:
		"pink":
			Wwise.set_rtpc_value(F4_PINK_RTPC, rtpc_value, self)
		"yellow":
			Wwise.set_rtpc_value(F4_YELLOW_RTPC, rtpc_value, self)
		"neon_green":
			Wwise.set_rtpc_value(F4_N_GREEN_RTPC, rtpc_value, self)
		"celeste":
			Wwise.set_rtpc_value(F4_CELESTE_RTPC, rtpc_value, self)
