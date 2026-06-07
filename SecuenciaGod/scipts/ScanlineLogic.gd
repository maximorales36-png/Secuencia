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


var sector_based_colors: Array = ["pink", "celeste", "neon_green"]

# Piece memory / stabilization
const PIECE_TIMEOUT: float = 0.35
const STABILIZE_SNAP: float = 0.015
const SMOOTHING_FACTOR: float = 0.35
var piece_memory: Dictionary = {}


func _on_pieces_updated(new_pieces: Array) -> void:
	var now = Time.get_ticks_msec() / 1000.0

	# Update memory with new detections
	for p in new_pieces:
		var key = str(p.color, "_", snapped(p.x, STABILIZE_SNAP))
		if piece_memory.has(key):
			var mem = piece_memory[key]
			mem.x = lerp(mem.x, p.x, SMOOTHING_FACTOR)
			mem.y = lerp(mem.y, p.y, SMOOTHING_FACTOR)
			mem.last_seen = now
		else:
			piece_memory[key] = {
				color = p.color,
				x = p.x,
				y = p.y,
				last_seen = now
			}

	# Remove expired entries
	var expired := []
	for key in piece_memory:
		if now - piece_memory[key].last_seen > PIECE_TIMEOUT:
			expired.append(key)
	for key in expired:
		piece_memory.erase(key)

	# Build stabilized pieces from memory
	pieces.clear()
	for key in piece_memory:
		var mem = piece_memory[key]
		var piece = WebSocketManager.Piece.new(mem.color, mem.x, mem.y)
		pieces.append(piece)

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

		if not prev_scan_position < piece.x or not scan_position >= piece.x:
			continue

		# For yellow at same X, only use the highest piece
		if piece.color == "yellow":
			var skip := false
			for other in pieces:
				if other.color == "yellow" and other != piece:
					if snapped(other.x, 0.01) == snapped(piece.x, 0.01) and other.y < piece.y:
						skip = true
						break
			if skip:
				continue

		var key: String = str(piece.color, "_", snapped(piece.x, 0.01))
		if triggered_keys.has(key):
			continue

		triggered_keys[key] = true
		print("[ScanlineLogic] CRUCE: %s en x=%.2f, y=%.2f (ciclo %.1f%%)" % [piece.color, piece.x, piece.y, scan_position * 100])
		crossing_detected.emit(piece)


func _detect_sector_crossings() -> void:
	var current_sector = int(scan_position * sector_count)
	if current_sector != prev_sector:
		var start = prev_sector + 1
		var end = current_sector
		if current_sector < prev_sector or prev_sector < 0:
			if prev_sector >= 0:
				for s in range(prev_sector + 1, sector_count):
					_trigger_sector(s)
			start = 0
			end = current_sector
		for s in range(start, end + 1):
			_trigger_sector(s)
		prev_sector = current_sector


func _trigger_sector(sector: int) -> void:
	if sector_colors.has(sector) and not triggered_sectors.has(sector):
		triggered_sectors[sector] = true
		for color in sector_colors[sector]:
			var y = sector_colors[sector][color]
			print("[ScanlineLogic] Sector %s activado: sector %d (y=%.2f, ciclo %.1f%%)" % [color, sector, y, scan_position * 100])
			sector_activated.emit(sector, y, color)


func get_yellow_pieces() -> Array:
	var result := []
	for piece in pieces:
		if piece.color == "yellow":
			result.append({"x": piece.x, "y": piece.y})
	return result


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
