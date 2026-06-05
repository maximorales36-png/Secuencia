extends Node
class_name ScanlineLogic

signal crossing_detected(piece: WebSocketManager.Piece)
signal beats_per_cycle_changed(new_beats: int)
signal sector_activated(sector_index: int, y: float)

@export var bpm: float = 60.0
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
var pink_sectors: Dictionary = {}
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

	_detect_crossings()
	_detect_sector_crossings()


func _on_pieces_updated(new_pieces: Array) -> void:
	pieces = new_pieces
	_update_pink_sectors()


func _update_pink_sectors() -> void:
	pink_sectors.clear()
	for piece in pieces:
		if piece.color == "pink":
			var sector = int(piece.x * sector_count)
			if not pink_sectors.has(sector) or piece.y > pink_sectors[sector]:
				pink_sectors[sector] = piece.y


func _detect_crossings() -> void:
	for piece in pieces:
		if piece.color == "pink":
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
		if pink_sectors.has(current_sector) and not triggered_sectors.has(current_sector):
			triggered_sectors[current_sector] = true
			var y = pink_sectors[current_sector]
			print("[ScanlineLogic] SECTOR ROSA activado: sector %d (y=%.2f, ciclo %.1f%%)" % [current_sector, y, scan_position * 100])
			sector_activated.emit(current_sector, y)


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


func is_sector_pink(sector: int) -> bool:
	return pink_sectors.has(sector)


func get_sector_for_position(x: float) -> int:
	return int(x * sector_count)
