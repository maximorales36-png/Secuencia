extends Node
## WebSocketManager
## Conecta a servidor WebSocket de Python
## Recibe datos de piezas detectadas y las almacena

class_name WebSocketManager

# Parámetros WebSocket
const WEBSOCKET_HOST = "localhost"
const WEBSOCKET_PORT = 8765
const WEBSOCKET_URL = "ws://localhost:8765"

# Estructura de pieza detectada
class Piece:
	var color: String
	var x: float  # [0, 1]
	var y: float  # [0, 1]
	
	func _init(p_color: String, p_x: float, p_y: float):
		color = p_color
		x = p_x
		y = p_y
	
	func _to_string() -> String:
		return "Piece(%s, x=%.2f, y=%.2f)" % [color, x, y]

# Variables
var pieces: Array[Piece] = []
var websocket_client: WebSocketPeer
var ws_connected: bool = false
var connection_attempts: int = 0
const MAX_CONNECTION_ATTEMPTS = 5

signal pieces_updated(new_pieces: Array[Piece])
signal connection_changed(connected: bool)

func _ready() -> void:
	print("[WebSocketManager] Inicializando...")
	_connect_websocket()

func _process(_delta: float) -> void:
	if websocket_client == null:
		return
	# Procesar mensajes WebSocket
	websocket_client.poll()
	
	var state = websocket_client.get_ready_state()
	
	match state:
		WebSocketPeer.STATE_OPEN:
			if not ws_connected:
				ws_connected = true
				connection_attempts = 0
				print("[WebSocketManager] Conectado a servidor")
				connection_changed.emit(true)
			
			# Procesar mensajes recibidos
			while websocket_client.get_available_packet_count() > 0:
				var data = websocket_client.get_packet().get_string_from_utf8()
				if data is String:
					_handle_message(data)
		
		WebSocketPeer.STATE_CLOSED:
			if ws_connected:
				ws_connected = false
				print("[WebSocketManager] Desconectado del servidor")
				connection_changed.emit(false)
				# Intentar reconectar
				await get_tree().create_timer(2.0).timeout
				_connect_websocket()

func _connect_websocket() -> void:
	if connection_attempts >= MAX_CONNECTION_ATTEMPTS:
		print("[WebSocketManager] ERROR: No se pudo conectar después de %d intentos" % MAX_CONNECTION_ATTEMPTS)
		return
	
	connection_attempts += 1
	print("[WebSocketManager] Intentando conectar a %s (intento %d/%d)..." % [WEBSOCKET_URL, connection_attempts, MAX_CONNECTION_ATTEMPTS])
	
	websocket_client = WebSocketPeer.new()
	var error = websocket_client.connect_to_url(WEBSOCKET_URL)
	
	if error != OK:
		print("[WebSocketManager] Error al conectar: %s" % error)

func _handle_message(message: String) -> void:
	# Parsear JSON
	var json = JSON.new()
	var parse_error = json.parse(message)
	
	if parse_error != OK:
		print("[WebSocketManager] Error parseando JSON: %s" % message)
		return
	
	var data = json.get_data()
	
	if data is Dictionary and data.has("piezas"):
		var piezas_data = data["piezas"]
		
		if piezas_data is Array:
			pieces.clear()
			for item in piezas_data:
				if item is Dictionary:
					var color = item.get("color", "unknown")
					var x = float(item.get("x", 0))
					var y = float(item.get("y", 0))
					pieces.append(Piece.new(color, x, y))
			
			pieces_updated.emit(pieces)
		else:
			print("[WebSocketManager] 'piezas' no es un array: %s" % str(piezas_data))
	else:
		print("[WebSocketManager] Formato inesperado: %s" % str(data))

func send_message(message: String) -> void:
	"""Envía un mensaje al servidor WebSocket."""
	if ws_connected:
		websocket_client.send_text(message)
	else:
		print("[WebSocketManager] No conectado. Mensaje no enviado: %s" % message)

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

func close_connection() -> void:
	if websocket_client:
		websocket_client.close()
		ws_connected = false
