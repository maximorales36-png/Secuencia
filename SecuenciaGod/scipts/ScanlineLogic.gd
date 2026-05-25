extends Node
class_name ScanlineLogic

signal crossing_detected(piece: WebSocketManager.Piece)
signal beats_per_cycle_changed(new_beats: int)

var bpm: float = 60.0
@export var beats_per_cycle: int = 8
var scan_position: float = 0.0
var prev_scan_position: float = -1.0
var scan_speed: float = 0.0
var pieces: Array = []
var triggered_keys: Dictionary = {}
var websocket_manager: WebSocketManager

const CYCLE_RESET_THRESHOLD: float = 0.1


func _ready() -> void:
	_update_scan_speed()

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
		triggered_keys.clear()

	_detect_crossings()


func _on_pieces_updated(new_pieces: Array) -> void:
	pieces = new_pieces


func _detect_crossings() -> void:
	for piece in pieces:
		var key: String = str(piece.color, "_", snapped(piece.x, 0.01))
		if triggered_keys.has(key):
			continue

		if prev_scan_position < piece.x and scan_position >= piece.x:
			triggered_keys[key] = true
			print("[ScanlineLogic] CRUCE: %s en x=%.2f, y=%.2f (ciclo %.1f%%)" % [piece.color, piece.x, piece.y, scan_position * 100])
			crossing_detected.emit(piece)


func get_scan_position() -> float:
	return scan_position


func set_bpm(new_bpm: float) -> void:
	bpm = new_bpm
	_update_scan_speed()


func set_beats_per_cycle(new_beats: int) -> void:
	beats_per_cycle = new_beats
	_update_scan_speed()
	beats_per_cycle_changed.emit(beats_per_cycle)


func _update_scan_speed() -> void:
	scan_speed = bpm / (60.0 * beats_per_cycle)
