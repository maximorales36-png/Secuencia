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
#   Familia 2 = obra musical 2 (futura)
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
}


# --------------------------------------------------------------------------
# FAMILIA ACTIVA
# --------------------------------------------------------------------------
# Cambiar este ID para seleccionar otra familia musical.

const FAMILIA_ACTIVA: String = "familia_1"


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
			}
		}
	},

	# ======================================================================
	# PLANTILLA PARA FUTURAS FAMILIAS
	# ======================================================================
	# Copiar y pegar, luego cambiar valores.
	# Los colores disponibles son: celeste, neon_green, yellow, pink.
	#
	# "familia_2": {
	#     "nombre": "Familia 2",
	#     "colores": {
	#         "celeste":    { "patron": "nuevo_patron", "sonido": "Play_Celeste_F2" },
	#         "neon_green": { "patron": "nuevo_patron", "sonido": "Play_Neon_Green_F2" },
	#         "yellow":     { "patron": "nuevo_patron", "sonido": "Play_Yellow_F2" },
	#         "pink":       { "patron": "nuevo_patron", "sonido": "Play_Pink_F2" }
	#     }
	# },
}


# ============================================================================
# FUNCIONES DE CONSULTA
# ============================================================================

## Devuelve el Color Godot para un nombre de color.
## Ej:  GestorFamilias.get_color("celeste")  →  Color(0.32, 0.82, 0.96)
static func get_color(nombre_color: String) -> Color:
	return COLORES.get(nombre_color, Color.WHITE)


## Devuelve el diccionario de una familia, o {} si no existe.
static func get_familia(id_familia: String = FAMILIA_ACTIVA) -> Dictionary:
	return FAMILIAS.get(id_familia, {})


## Devuelve los colores de una familia, o {} si no existe.
static func get_colores_familia(id_familia: String = FAMILIA_ACTIVA) -> Dictionary:
	return get_familia(id_familia).get("colores", {})


## Devuelve la configuración de un color dentro de una familia.
## La configuración incluye: "patron" y "sonido".
static func get_config_color(nombre_color: String, id_familia: String = FAMILIA_ACTIVA) -> Dictionary:
	return get_colores_familia(id_familia).get(nombre_color, {})


## Devuelve el nombre del patrón de Turing para un color.
## Ej:  GestorFamilias.get_patron("celeste")  →  "spiral"
static func get_patron(nombre_color: String, id_familia: String = FAMILIA_ACTIVA) -> String:
	return get_config_color(nombre_color, id_familia).get("patron", "")


## Devuelve el nombre del evento Wwise para un color.
## Ej:  GestorFamilias.get_sonido("celeste")  →  "Play_Celeste"
static func get_sonido(nombre_color: String, id_familia: String = FAMILIA_ACTIVA) -> String:
	return get_config_color(nombre_color, id_familia).get("sonido", "")


## Devuelve true si el color pertenece a la familia activa.
static func es_de_familia_activa(nombre_color: String) -> bool:
	return get_colores_familia().has(nombre_color)
