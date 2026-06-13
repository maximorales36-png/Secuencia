# ============================================================================
# GestorFamilias.gd  |  v1.0
# ============================================================================
# Configuración centralizada de las FAMILIAS musicales.
#
# ¿QUÉ ES UNA FAMILIA?
#   Cada FAMILIA es una obra / canción / pieza musical completa.
#   Todas las familias usan los mismos 4 colores de piezas físicas,
#   pero cada familia tiene SUS PROPIOS sonidos y visualizaciones.
#
#   Familia 1 = obra musical 1 (actual)
#   Familia 2 = obra musical 2 (Karen)
#   Familia 3 = obra musical 3 (futura)
#   Familia 4 = obra musical 4 (futura)
#   
#
# ¿CÓMO SE USA?
#   Desde cualquier script:  GestorFamilias.get_patron("celeste")
#   Devuelve el patrón de Turing que corresponde a ese color
#   en la familia actual.
#
# CÓMO AGREGAR UNA NUEVA FAMILIA:
#   1. Agregar entrada en el diccionario FAMILIAS (abajo)
#   2. Definir para cada color: qué patrón visual y qué evento Wwise
#   3. Si querés un patrón visual nuevo, agregar la función
#      de dibujo en EffectsRenderer.gd (sección "PATRONES DE TURING")
#
# ============================================================================

extends Node


# --------------------------------------------------------------------------
# COLORES DISPONIBLES
# --------------------------------------------------------------------------
# Mapeo de nombre de color → Color Godot.
# Es INDEPENDIENTE de la familia (el color físico de la pieza no cambia).

const COLORES: Dictionary = {
	"yellow":     Color(1.0, 1.0, 0.0),
	"orange":     Color(1.0, 0.5, 0.0),
	"pink":       Color(1.0, 0.75, 0.8),
	"celeste":    Color(0.32, 0.82, 0.96),
	"neon_green": Color(0.0, 1.0, 0.5),
	"violet":     Color(0.6, 0.2, 1.0),
}

# --------------------------------------------------------------------------
# DATOS VISUALES DEL HTML (Familia 2)
# --------------------------------------------------------------------------
# Colores RGB (0-255) y colores de deriva para la estética de blobs orgánicos.
# Usados por BlobRenderer.gd

const HTML_COLORS: Dictionary = {
	"celeste":    { "col": [74, 240, 212], "drift": [30, 140, 255] },
	"yellow":     { "col": [240, 215, 55], "drift": [255, 160, 30] },
	"neon_green": { "col": [90, 240, 90],  "drift": [40, 200, 120] },
	"orange":     { "col": [240, 65, 65],  "drift": [255, 130, 20] },
	"violet":     { "col": [176, 74, 240], "drift": [220, 50, 180] },
}

const HTML_ATOM_DEFS: Dictionary = {
	"celeste":    { "synth": "sine",     "freq": 528, "name": "ether",   "inst": "sine osc" },
	"yellow":     { "synth": "triangle", "freq": 396, "name": "pulse",   "inst": "tri osc" },
	"neon_green": { "synth": "sawtooth", "freq": 264, "name": "organic", "inst": "saw osc" },
	"orange":     { "synth": "sine",     "freq": 132, "name": "deep",    "inst": "sub sine" },
	"violet":     { "synth": "square",   "freq": 792, "name": "crystal", "inst": "sqr osc" },
}


# --------------------------------------------------------------------------
# FAMILIA ACTIVA
# --------------------------------------------------------------------------
# Cambiar este ID para seleccionar otra familia musical.

@export var familia_activa: String = "familia_1"


# --------------------------------------------------------------------------
# CONFIGURACIÓN DE CADA FAMILIA
# --------------------------------------------------------------------------
# Cada entrada es una familia musical.
#
# Estructura por familia:
#   "id_unico": {
#       "nombre": "Nombre visible para el público",
#       "colores": {
#           "celeste": {
#               "patron": "spiral",       # clave del patrón de Turing
#               "sonido": "Play_Celeste"   # evento de Wwise
#           },
#           ... (los 4 colores)
#       }
#   }
#
# PATRONES DE TURING DISPONIBLES:
#   "spots"      → manchas punteadas (como leopardo)
#   "stripes"    → rayas onduladas (como cebra)
#   "spiral"     → espirales (como concha de caracol)
#   "labyrinth"  → laberinto (como ameba)
#   "pufferfish" → retícula de pez globo (honeycomb + manchas)
#
# Para crear un nuevo patrón, agregar la función en EffectsRenderer.gd
# en la sección "PATRONES DE TURING" y referenciarla acá.

const FAMILIAS: Dictionary = {
	# ======================================================================
	# FAMILIA 1 — Obra musical actual
	# ======================================================================
	"familia_1": {
		"nombre": "Familia 1",
		"colores": {
			"celeste": {
				"patron": "spiral",
				"sonido": "Play_Celeste"
			},
			"neon_green": {
				"patron": "labyrinth",
				"sonido": "Play_Neon_Green"
			},
			"yellow": {
				"patron": "spots",
				"sonido": "Play_Yellow"
			},
			"pink": {
				"patron": "pufferfish",
				"sonido": "Play_Pink"
			},
			"violet": {
				"patron": "",
				"sonido": ""
			}
		}
	},

	# ======================================================================
	# FAMILIA 2 — Estética HTML de Karen (blobs orgánicos)
	# ======================================================================
	"familia_2": {
		"nombre": "Familia 2",
		"colores": {
			"celeste": {
				"patron": "blob",
				"sonido": "Play_Celeste_F2"
			},
			"neon_green": {
				"patron": "blob",
				"sonido": "Play_Neon_Green_F2"
			},
			"yellow": {
				"patron": "blob",
				"sonido": "Play_Yellow_F2"
			},
			"orange": {
				"patron": "blob",
				"sonido": "Play_Orange_F2"
			},
			"violet": {
				"patron": "blob",
				"sonido": "Play_Violet_F2"
			}
		}
	},
}


# ============================================================================
# FUNCIONES DE CONSULTA
# ============================================================================

## Devuelve el Color Godot para un nombre de color.
## Ej:  GestorFamilias.get_color("celeste")  →  Color(0.32, 0.82, 0.96)
func get_color(nombre_color: String) -> Color:
	return COLORES.get(nombre_color, Color.WHITE)


## Devuelve el diccionario de una familia, o {} si no existe.
func get_familia(id_familia: String = "") -> Dictionary:
	if id_familia.is_empty():
		id_familia = familia_activa
	return FAMILIAS.get(id_familia, {})


## Devuelve los colores de una familia, o {} si no existe.
func get_colores_familia(id_familia: String = "") -> Dictionary:
	if id_familia.is_empty():
		id_familia = familia_activa
	return get_familia(id_familia).get("colores", {})


## Devuelve la configuración de un color dentro de una familia.
## La configuración incluye: "patron" y "sonido".
func get_config_color(nombre_color: String, id_familia: String = "") -> Dictionary:
	if id_familia.is_empty():
		id_familia = familia_activa
	return get_colores_familia(id_familia).get(nombre_color, {})


## Devuelve el nombre del patrón de Turing para un color.
## Ej:  GestorFamilias.get_patron("celeste")  →  "spiral"
func get_patron(nombre_color: String, id_familia: String = "") -> String:
	if id_familia.is_empty():
		id_familia = familia_activa
	return get_config_color(nombre_color, id_familia).get("patron", "")


## Devuelve el nombre del evento Wwise para un color.
## Ej:  GestorFamilias.get_sonido("celeste")  →  "Play_Celeste"
func get_sonido(nombre_color: String, id_familia: String = "") -> String:
	if id_familia.is_empty():
		id_familia = familia_activa
	return get_config_color(nombre_color, id_familia).get("sonido", "")


## Devuelve true si el color pertenece a la familia activa.
func es_de_familia_activa(nombre_color: String) -> bool:
	return get_colores_familia().has(nombre_color)


## Devuelve el color RGB (0-255) del HTML para un nombre de color.
## Usado por BlobRenderer para la estética de blobs orgánicos.
func get_html_color(nombre_color: String) -> Array:
	return HTML_COLORS.get(nombre_color, {}).get("col", [255, 255, 255])


## Devuelve el color de deriva RGB (0-255) del HTML para un nombre de color.
func get_html_drift(nombre_color: String) -> Array:
	return HTML_COLORS.get(nombre_color, {}).get("drift", [255, 255, 255])


## Devuelve la definición de átomo del HTML (freq, synth, name, inst).
func get_html_atom_def(nombre_color: String) -> Dictionary:
	return HTML_ATOM_DEFS.get(nombre_color, {})


## Verifica si un color pertenece a una familia específica (no solo la activa).
func es_de_familia(nombre_color: String, id_familia: String) -> bool:
	return get_colores_familia(id_familia).has(nombre_color)
