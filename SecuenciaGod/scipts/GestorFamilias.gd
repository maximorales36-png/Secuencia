extends Node

const COLORES: Dictionary = {
	"red":        Color(1.0, 0.2, 0.2),
	"pink":       Color(1.0, 0.75, 0.8),
	"green":      Color(0.0, 1.0, 0.3),
	"blue":       Color(0.2, 0.5, 1.0),
	"violet":     Color(0.6, 0.2, 1.0),
}

const HTML_COLORS: Dictionary = {
	"blue":       { "col": [74, 240, 212], "drift": [30, 140, 255] },
	"red":        { "col": [240, 215, 55], "drift": [255, 160, 30] },
	"green":      { "col": [90, 240, 90],  "drift": [40, 200, 120] },
	"violet":     { "col": [176, 74, 240], "drift": [220, 50, 180] },
}

const HTML_ATOM_DEFS: Dictionary = {
	"blue":       { "synth": "sine",     "freq": 528, "name": "ether",   "inst": "sine osc" },
	"red":        { "synth": "triangle", "freq": 396, "name": "pulse",   "inst": "tri osc" },
	"green":      { "synth": "sawtooth", "freq": 264, "name": "organic", "inst": "saw osc" },
	"violet":     { "synth": "square",   "freq": 792, "name": "crystal", "inst": "sqr osc" },
}

@export var familia_activa: String = "familia_1"
var wwise_main_bank_loaded: bool = false

const SCAN_CONFIG: Dictionary = {
	"familia_1": { "bpm": 87.0, "beats_per_cycle": 16 },
	"familia_2": { "bpm": 76.0, "beats_per_cycle": 4 },
	"familia_4": { "bpm": 72.0, "beats_per_cycle": 4 },
}

const FAMILIAS: Dictionary = {
	"familia_1": {
		"nombre": "Familia 1",
		"colores": {
			"blue":       { "patron": "spiral",     "sonido": "Play_Blue" },
			"green":      { "patron": "labyrinth",  "sonido": "Play_Green" },
			"red":        { "patron": "spots",      "sonido": "Play_Red" },
			"pink":       { "patron": "pufferfish", "sonido": "Play_Pink" },
			"violet":     { "patron": "",           "sonido": "" }
		}
	},
	"familia_2": {
		"nombre": "Familia 2",
		"colores": {
			"blue":       { "patron": "blob", "sonido": "Play_Blue_F2" },
			"green":      { "patron": "blob", "sonido": "Play_Green_F2" },
			"red":        { "patron": "blob", "sonido": "Play_Red_F2" },
			"violet":     { "patron": "blob", "sonido": "Play_Violet_F2" }
		}
	},
	"familia_4": {
		"nombre": "Familia 4",
		"colores": {
			"pink":       { "patron": "balls", "sonido": "Play_F4_Pink" },
			"red":        { "patron": "balls", "sonido": "Play_F4_Red" },
			"green":      { "patron": "balls", "sonido": "Play_F4_Green" },
			"blue":       { "patron": "balls", "sonido": "Play_F4_Blue" },
			"violet":     { "patron": "balls", "sonido": "Play_F4_Violet" }
		}
	},
}


func get_bpm(family: String = "") -> float:
	var f = family if not family.is_empty() else familia_activa
	return SCAN_CONFIG.get(f, {}).get("bpm", 87.0)


func get_beats_per_cycle(family: String = "") -> int:
	var f = family if not family.is_empty() else familia_activa
	return SCAN_CONFIG.get(f, {}).get("beats_per_cycle", 16)


func _get_family_id(id_familia: String = "") -> String:
	return id_familia if not id_familia.is_empty() else familia_activa


func get_color(nombre_color: String) -> Color:
	return COLORES.get(nombre_color, Color.WHITE)


func get_family(id_familia: String = "") -> Dictionary:
	return FAMILIAS.get(_get_family_id(id_familia), {})


func get_family_colors(id_familia: String = "") -> Dictionary:
	return get_family(id_familia).get("colores", {})


func get_color_config(nombre_color: String, id_familia: String = "") -> Dictionary:
	return get_family_colors(id_familia).get(nombre_color, {})


func get_pattern(nombre_color: String, id_familia: String = "") -> String:
	return get_color_config(nombre_color, id_familia).get("patron", "")


func get_sound(nombre_color: String, id_familia: String = "") -> String:
	return get_color_config(nombre_color, id_familia).get("sonido", "")


func is_in_active_family(nombre_color: String) -> bool:
	return get_family_colors().has(nombre_color)


func is_in_family(nombre_color: String, id_familia: String) -> bool:
	return get_family_colors(id_familia).has(nombre_color)


func get_html_color(nombre_color: String) -> Array:
	return HTML_COLORS.get(nombre_color, {}).get("col", [255, 255, 255])


func get_html_drift(nombre_color: String) -> Array:
	return HTML_COLORS.get(nombre_color, {}).get("drift", [255, 255, 255])


func get_html_atom_def(nombre_color: String) -> Dictionary:
	return HTML_ATOM_DEFS.get(nombre_color, {})
