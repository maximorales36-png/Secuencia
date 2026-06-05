extends Node
class_name ScanlineLogic

signal crossing_detected(piece: WebSocketManager.Piece)
signal beats_per_cycle_changed(new_beats: int)
signal sector_activated(sector_index: int, y: float, color: String)
signal cycle_reset()

@export var bpm: float = 87
@export var beats_per_cycle: int = 32
var scan_position: float = 0.0
var prev_scan_position: float = -1.0
var scan_speed: float = 0.0
var pieces: Array = []
var triggered_keys: Dictionary = {}
var websocket_manager: WebSocketManager

# Sector logic (1 sector = 4 negras = 1 compas)
const BEATS_PER_SECTOR: int = 4
var sector_count: int = 0
var sector_colors: Dictionary = {}  # sector_index -> {color_name: y, ...}
var triggered_sectors: Dictionary = {}
var prev_sector: int = -1

const CYCLE_RESET_THRESHOLD: float = 0.1


func _ready() -> void:
	_update_scan_speed()
	_update_sector_count()

	websocket_manager = get_tree().root.find_child("WebSocketManager", true, false)
	if websocket_manager:
		websocket_manager.pieces_updated.connect(_on_pieces_updated)
	else:
		print("[ScanlineLogic] ERROR: No se encontr\u00f3 WebSocketManager")


func _process(delta: float) -> void:
	prev_scan_position = scan_position
	scan_position += scan_speed * delta

	if scan_position >= 1.0:
		scan_position = 0.0
		prev_scan_position = -1.0
		prev_sector = -1
		triggered_keys.clear()
		triggered_sectors.clear()
		cycle_reset.emit()

	_detect_crossings()
	_detect_sector_crossings()


var sector_based_colors: Array = ["pink", "celeste"]


func _on_pieces_updated(new_pieces: Array) -> void:
	pieces = new_pieces
	_update_sector_colors()


func _update_sector_colors() -> void:
	sector_colors.clear()
	for piece in pieces:
		if piece.color in sector_based_colors:
			var sector = int(piece.x * sector_count)
			if not sector_colors.has(sector):
				sector_colors[sector] = {}
			var sector_data = sector_colors[sector]
			if not sector_data.has(piece.color) or piece.y > sector_data[piece.color]:
				sector_data[piece.color] = piece.y


func _detect_crossings() -> void:
	for piece in pieces:
		if piece.color in sector_based_colors:
			continue
		var key: String = str(piece.color, "_", snapped(piece.x, 0.01))
		if triggered_keys.has(key):
			continue

		if prev_scan_position < piece.x and scan_position >= piece.x:
			triggered_keys[key] = true
			print("[ScanlineLogic] CRUCE: %s en x=%.2f, y=%.2f (ciclo %.1f%%)" % [piece.color, piece.x, piece.y, scan_position * 100])
			crossing_detected.emit(piece)


func _detect_sector_crossings() -> void:
	var current_sector = int(scan_position * sector_count)
	if current_sector != prev_sector:
		prev_sector = current_sector
		if sector_colors.has(current_sector) and not triggered_sectors.has(current_sector):
			triggered_sectors[current_sector] = true
			for color in sector_colors[current_sector]:
				var y = sector_colors[current_sector][color]
				print("[ScanlineLogic] Sector %s activado: sector %d (y=%.2f, ciclo %.1f%%)" % [color, current_sector, y, scan_position * 100])
				sector_activated.emit(current_sector, y, color)


func get_scan_position() -> float:
	return scan_position


func set_bpm(new_bpm: float) -> void:
	bpm = new_bpm
	_update_scan_speed()


func set_beats_per_cycle(new_beats: int) -> void:
	beats_per_cycle = new_beats
	_update_scan_speed()
	_update_sector_count()
	beats_per_cycle_changed.emit(beats_per_cycle)


func _update_scan_speed() -> void:
	scan_speed = bpm / (60.0 * beats_per_cycle)


func _update_sector_count() -> void:
	sector_count = max(1, int(beats_per_cycle / BEATS_PER_SECTOR))


func get_sector_count() -> int:
	return sector_count


func is_sector_occupied(sector: int) -> bool:
	return sector_colors.has(sector) and not sector_colors[sector].is_empty()


func get_sector_color(sector: int) -> String:
	if sector_colors.has(sector):
		var colors = sector_colors[sector].keys()
		if not colors.is_empty():
			return colors[0]
	return ""


func get_sector_duration() -> float:
	return (BEATS_PER_SECTOR * 60.0) / bpm


func get_sector_for_position(x: float) -> int:
	return int(x * sector_count)
