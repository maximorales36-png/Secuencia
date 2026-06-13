# ============================================================================
# AudioManager.gd  |  v1.1
# ============================================================================
# Gestiona los eventos de audio via Wwise.
#
# AHORA USA GestorFamilias:
#   • El nombre del evento Wwise se obtiene de GestorFamilias.get_sonido()
#   • Cuando se cambie de familia, los sonidos cambian automáticamente
#
# CÓMO AGREGAR UNA NUEVA FAMILIA:
#   Solo hace falta agregar los eventos Wwise correspondientes y
#   configurarlos en GestorFamilias.gd → FAMILIAS
#
# ============================================================================

extends Node
class_name AudioManager

var scanline_logic: ScanlineLogic
var color_cooldowns: Dictionary = {}

# Estado del yellow monofónico
var yellow_active: bool = false
var yellow_note: int = -1
const YELLOW_SWITCH_GROUP: String = "yellow_switch"
const YELLOW_SWITCH_VALUES: Array = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]

# Violet RTPC (global controller)
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


func _process(delta: float) -> void:
	_update_violet_rtpc(delta)
	_update_green_rtpc(delta)
	_update_pink_rtpc(delta)


## Smooths and sends the Violet RTPC value to Wwise.
## When no violet piece is detected, target = 100 (default / safe state).
## Uses exponential smoothing with ~3s time constant.
func _update_violet_rtpc(delta: float) -> void:
	if scanline_logic == null:
		return

	var found := false
	var highest_y := 1.0
	for piece in scanline_logic.pieces:
		if piece.color == "violet" and piece.y < highest_y:
			highest_y = piece.y
			found = true

	if found:
		_violet_target = (1.0 - highest_y) * 100.0
	else:
		_violet_target = 100.0

	var smoothing := 1.0 - exp(-delta * 1.0)
	_violet_current = lerp(_violet_current, _violet_target, smoothing)

	Wwise.set_rtpc_value(VIOLET_RTPC_NAME, _violet_current, self)


## Smooths and sends the Green RTPC value to Wwise (half speed of violet).
func _update_green_rtpc(delta: float) -> void:
	if scanline_logic == null:
		return
	var found := false
	var highest_y := 1.0
	for piece in scanline_logic.pieces:
		if piece.color == "neon_green" and piece.y < highest_y:
			highest_y = piece.y
			found = true
	if found:
		_green_target = (1.0 - highest_y) * 100.0
	else:
		_green_target = 100.0
	var smoothing := 1.0 - exp(-delta * 0.5)
	_green_current = lerp(_green_current, _green_target, smoothing)
	Wwise.set_rtpc_value(GREEN_RTPC_NAME, _green_current, self)


## Smooths and sends the Pink RTPC value to Wwise (half speed of violet).
func _update_pink_rtpc(delta: float) -> void:
	if scanline_logic == null:
		return
	var found := false
	var highest_y := 1.0
	for piece in scanline_logic.pieces:
		if piece.color == "pink" and piece.y < highest_y:
			highest_y = piece.y
			found = true
	if found:
		_pink_target = (1.0 - highest_y) * 100.0
	else:
		_pink_target = 100.0
	var smoothing := 1.0 - exp(-delta * 0.5)
	_pink_current = lerp(_pink_current, _pink_target, smoothing)
	Wwise.set_rtpc_value(PINK_RTPC_NAME, _pink_current, self)


func _on_cycle_reset() -> void:
	color_cooldowns.clear()
	if yellow_active:
		yellow_active = false
		yellow_note = -1
		Wwise.post_event("Stop_yellow", self)


func _on_crossing_detected(piece: IPCManager.Piece) -> void:
	if GestorFamilias.familia_activa != "familia_1":
		_reproducir_sonido(piece.color, piece.y)
		return
	if piece.color == "yellow":
		_handle_yellow(piece.y)
	elif piece.color == "violet":
		return
	else:
		_reproducir_sonido(piece.color, piece.y)


func _on_sector_activated(sector_index: int, y: float, color: String) -> void:
	_reproducir_sonido(color, y, sector_index)


## Manejo especial del yellow (monofónico, con switches de nota)
func _handle_yellow(y: float) -> void:
	var note := clampi(7 - int(y * 8), 0, 7)
	if note == yellow_note and yellow_active:
		return
	yellow_note = note
	Wwise.set_switch(YELLOW_SWITCH_GROUP, YELLOW_SWITCH_VALUES[note], self)
	if not yellow_active:
		yellow_active = true
		# El nombre del evento se obtiene del GestorFamilias
		var evento: String = GestorFamilias.get_sonido("yellow")
		if not evento.is_empty():
			Wwise.post_event(evento, self)


## Reproduce el sonido de un color en la posición Y dada.
## Obtiene el nombre del evento Wwise desde GestorFamilias.
## sector_index permite crear un cooldown único por sector+color
## para que piezas del mismo color en sectores diferentes no se bloqueen.
func _reproducir_sonido(color: String, y_position: float, sector_index: int = -1) -> void:
	# Verificar que el color pertenezca a la familia activa
	if not GestorFamilias.es_de_familia_activa(color):
		print("[AudioManager] Color '%s' no está en la familia activa" % color)
		return

	# Cooldown por sector+color (evita que un color bloquee a todos)
	var ahora := Time.get_ticks_msec() / 1000.0
	var cooldown_key: String = color if sector_index < 0 else str(sector_index) + "_" + color
	if color_cooldowns.has(cooldown_key) and ahora < color_cooldowns[cooldown_key]:
		return

	y_position = clampf(y_position, 0.0, 1.0)

	# Obtener el nombre del evento Wwise desde la configuración de familia
	var event_name: String = GestorFamilias.get_sonido(color)
	if event_name.is_empty():
		print("[AudioManager] No hay evento Wwise configurado para '%s'" % color)
		return

	var rtpc_value := y_position * 100.0

	Wwise.post_event(event_name, self)
	Wwise.set_rtpc_value("Timbre", rtpc_value, self)

	# Cooldown = duración de un sector
	color_cooldowns[cooldown_key] = ahora + scanline_logic.get_sector_duration()
