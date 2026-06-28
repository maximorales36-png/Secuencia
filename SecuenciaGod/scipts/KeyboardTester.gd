extends Node
var test_mode: bool = false
var last_color_index: int = 0
var color_keys: Array[String] = ["red", "blue", "pink", "green", "violet"]
func _ready() -> void:
	print("[KeyboardTester] Listo. F12 para activar/desactivar modo test.")
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("return_to_menu"):
		print("[KeyboardTester] Volviendo al menu principal...")
		get_tree().change_scene_to_file("res://main_menu.tscn")
	if Input.is_action_just_pressed("toggle_test_mode"):
		test_mode = not test_mode
		print("[KeyboardTester] Modo test: %s" % ("ON" if test_mode else "OFF"))
	if not test_mode:
		return
	if Input.is_action_just_pressed("family_1"):
		_select_family("familia_1")
	elif Input.is_action_just_pressed("family_2"):
		_select_family("familia_2")
	elif Input.is_action_just_pressed("family_3"):
		_select_family("familia_3")
	elif Input.is_action_just_pressed("family_4"):
		_select_family("familia_4")
	elif Input.is_action_just_pressed("add_red"):
		_add_piece("red")
	elif Input.is_action_just_pressed("add_blue"):
		_add_piece("blue")
	elif Input.is_action_just_pressed("add_pink"):
		_add_piece("pink")
	elif Input.is_action_just_pressed("add_green"):
		_add_piece("green")
	elif Input.is_action_just_pressed("add_violet"):
		_add_piece("violet")
	elif Input.is_action_just_pressed("move_up"):
		_move_last_piece(0.0, -0.02)
	elif Input.is_action_just_pressed("move_down"):
		_move_last_piece(0.0, 0.02)
	elif Input.is_action_just_pressed("move_left"):
		_move_last_piece(-0.02, 0.0)
	elif Input.is_action_just_pressed("move_right"):
		_move_last_piece(0.02, 0.0)
func _select_family(family: String) -> void:
	var menu = get_tree().root.find_child("FamilyMenu", true, false)
	if menu and menu.has_method("_on_family_selected"):
		print("[KeyboardTester] Seleccionando familia: %s" % family)
		menu._on_family_selected(family)
func _add_piece(color: String) -> void:
	var rng = RandomNumberGenerator.new()
	var x = rng.randf_range(0.05, 0.95)
	var y = rng.randf_range(0.05, 0.95)
	var piece = IPCManager.Piece.new(color, x, y)
	IPCManager.pieces.append(piece)
	IPCManager.last_update_time = Time.get_ticks_msec() / 1000.0
	IPCManager.pieces_updated.emit(IPCManager.pieces)
	print("[KeyboardTester] Pieza añadida: %s en (%.2f, %.2f)" % [color, x, y])
func _move_last_piece(dx: float, dy: float) -> void:
	if IPCManager.pieces.is_empty():
		return
	var last = IPCManager.pieces[-1]
	last.x = clampf(last.x + dx, 0.0, 1.0)
	last.y = clampf(last.y + dy, 0.0, 1.0)
	IPCManager.last_update_time = Time.get_ticks_msec() / 1000.0
	IPCManager.pieces_updated.emit(IPCManager.pieces)
	print("[KeyboardTester] Última pieza movida a (%.2f, %.2f)" % [last.x, last.y])
