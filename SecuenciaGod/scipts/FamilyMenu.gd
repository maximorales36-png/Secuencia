extends Control

var _pieces_viz: Node = null


func _ready() -> void:
	Wwise.register_game_obj(self, "FamilyMenu")
	Wwise.load_bank("Main")
	Wwise.add_default_listener(self)
	Wwise.post_event("mx_play_menu", self)


	var vp := get_viewport_rect().size
	var btn_w := vp.x * 0.18
	var btn_h := vp.y * 0.42
	var gap := vp.x * 0.03
	var total_w := 4.0 * btn_w + 3.0 * gap
	var start_x := (vp.x - total_w) * 0.5
	var y := vp.y * 0.5 - btn_h * 0.5

	for i in range(4):
		var family := "familia_%d" % (i + 1)
		var btn := FamilyButton.new()
		btn.position = Vector2(start_x + i * (btn_w + gap), y)
		btn.size = Vector2(btn_w, btn_h)
		btn.family_name = family
		btn.label_text = ["Familia 1", "Familia 2", "Familia 3", "Familia 4"][i]
		btn.family_selected.connect(_on_family_selected)
		add_child(btn)

	_pieces_viz = PiecesVisualizer.new()
	_pieces_viz.name = "PiecesVisualizer"
	_pieces_viz.piece_radius = 18.0
	add_child(_pieces_viz)


func _process(_delta: float) -> void:
	if _pieces_viz:
		_pieces_viz.queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	var title := "Selecciona una familia"
	var title_size := 28
	draw_string(font, Vector2(0, vp.y * 0.12), title, HORIZONTAL_ALIGNMENT_CENTER, vp.x, title_size, Color(1, 1, 1, 0.7))

	var subtitle := "Coloca un objeto sobre un boton y mantenlo quieto 3 segundos"
	var sub_size := 14
	draw_string(font, Vector2(0, vp.y * 0.12 + 36), subtitle, HORIZONTAL_ALIGNMENT_CENTER, vp.x, sub_size, Color(1, 1, 1, 0.4))


func _on_family_selected(family_name: String) -> void:
	GestorFamilias.familia_activa = family_name
	print("[FamilyMenu] Selected: %s" % family_name)

	Wwise.post_event("mx_stop_menu", self)

	var family_num := family_name.trim_prefix("familia_")
	var event_name := "Enter_F_%02d" % int(family_num)
	Wwise.post_event(event_name, self)

	get_tree().change_scene_to_file("res://main.tscn")
