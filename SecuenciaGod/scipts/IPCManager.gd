extends Node
## IPCManager
## Lee datos de piezas desde archivo JSON compartido.

const PIECE_TIMEOUT: float = 2.0

class Piece:
	var color: String
	var x: float
	var y: float

	func _init(p_color: String, p_x: float, p_y: float):
		color = p_color
		x = p_x
		y = p_y

	func _to_string() -> String:
		return "Piece(%s, x=%.2f, y=%.2f)" % [color, x, y]

var pieces: Array[Piece] = []
var connected: bool = false
var last_update_time: float = 0.0
var ipc_path: String = ""

signal pieces_updated(new_pieces: Array[Piece])
signal connection_changed(connected: bool)

func _ready() -> void:
	var temp_dir = OS.get_environment("TEMP")
	if temp_dir.is_empty():
		temp_dir = "/tmp"
	ipc_path = temp_dir.path_join("secuencia_pieces.json")
	print("[IPCManager] Leyendo de: %s" % ipc_path)

func _process(_delta: float) -> void:
	_check_connection()
	_read_pieces()

func _check_connection() -> void:
	var now = Time.get_ticks_msec() / 1000.0
	var was_connected = connected
	connected = (now - last_update_time) < PIECE_TIMEOUT
	if connected != was_connected:
		print("[IPCManager] %s" % ("Conectado" if connected else "Desconectado (timeout)"))
		connection_changed.emit(connected)

func _read_pieces() -> void:
	if not FileAccess.file_exists(ipc_path):
		return

	var file = FileAccess.open(ipc_path, FileAccess.READ)
	if file == null:
		return

	var text = file.get_as_text().strip_edges()
	file.close()

	if text.is_empty():
		return

	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		return

	var data = json.get_data()
	if data is Dictionary and data.has("piezas"):
		var piezas_data = data["piezas"]
		if piezas_data is Array:
			pieces.clear()
			for item in piezas_data:
				if item is Dictionary:
					pieces.append(Piece.new(
						item.get("color", "unknown"),
						float(item.get("x", 0)),
						float(item.get("y", 0))
					))

			last_update_time = Time.get_ticks_msec() / 1000.0
			pieces_updated.emit(pieces)

func get_pieces() -> Array[Piece]:
	return pieces

func get_piece_count() -> int:
	return pieces.size()

func get_pieces_by_color(color: String) -> Array[Piece]:
	var result: Array[Piece] = []
	for piece in pieces:
		if piece.color == color:
			result.append(piece)
	return result
