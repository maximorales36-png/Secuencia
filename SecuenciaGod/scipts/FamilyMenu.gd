extends Control


func _ready() -> void:
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

	var vis := PiecesVisualizer.new()
	vis.name = "PiecesVisualizer"
	add_child(vis)


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
	get_tree().change_scene_to_file("res://main.tscn")
