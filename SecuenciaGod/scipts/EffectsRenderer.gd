# ============================================================================
# EffectsRenderer.gd  |  v2.0  |  Motor de efectos visuales
# ============================================================================
#
# ¿QUÉ HACE?
#   Renderiza todos los efectos visuales de la secuencia:
#     • Ondas expansivas (como perturbación en el agua)
#     • Estelas persistentes (lo que deja la onda al pasar)
#     • Patrones de Turing (un patrón diferente por color)
#     • Línea de barrido (scanline)
#     • Sombra amarilla (soga/conexión de piezas yellow)
#     • Rectángulos de sector (para piezas sectoriales)
#
# ARQUITECTURA DEL EFECTO "AGUA":
#   Cuando una pieza se activa:
#     1. ONDA: anillos concéntricos que se expanden desde la pieza
#     2. ESTELA: detrás de la onda, el patrón de Turing queda visible
#     3. La estela persiste varios segundos y se desvanece lentamente
#   Esto simula una gota en el agua: el anillo se expande y deja
#   una perturbación en la superficie que tarda en calmarse.
#
# PATRONES DE TURING (Familia 1):
#   Celeste    → Espiral  (como concha de caracol)
#   Neon Green → Laberinto (como ameba)
#   Yellow     → Manchas  (como leopardo)
#   Pink       → Rayas    (como cebra)
#
# CÓMO MODIFICAR:
#   • Colores y patrones: editar GestorFamilias.gd → FAMILIAS
#   • Duración de estelas: cambiar TRAIL_DURATION (abajo)
#   • Velocidad de onda: cambiar WAVE_DURATION (abajo)
#   • Nuevo patrón: agregar función _dibujar_patron_X() y
#     agregar caso en _evaluar_patron()
#
# ============================================================================

extends Node2D
class_name EffectsRenderer


# ============================================================================
# SECCIÓN 1: PARÁMETROS EXPORTABLES
# ============================================================================
# Estos valores se pueden modificar desde el inspector de Godot.
# También se pueden cambiar directamente acá.

## Duración de la onda expansiva (segundos)
@export var wave_duration: float = 0.8

## Duración de la estela persistente (segundos)
@export var trail_duration: float = 4.0

## Radio máximo de la onda expansiva (píxeles)
@export var max_wave_radius: float = 200.0

## Radio del área cubierta por el patrón de Turing (píxeles)
@export var pattern_radius: float = 130.0

## Separación entre puntos del patrón de Turing (menor = más detalle, más lento)
@export var pattern_spacing: float = 14.0

## Cantidad de anillos en el tren de ondas
@export var wave_ring_count: int = 4

## Ancho de la línea de barrido (píxeles)
@export var scan_line_width: float = 5.0

## Color de la línea de barrido
@export var scan_line_color: Color = Color(1.0, 0.62, 0.0, 0.69)

## Opacidad de la sombra amarilla (soga)
@export var yellow_shadow_alpha: float = 0.15

## Altura del rectángulo de sector (píxeles)
@export var rect_height: float = 80.0

## Opacidad de los rectángulos de sector
@export var sector_alpha: float = 0.15


# ============================================================================
# SECCIÓN 2: VARIABLES INTERNAS
# ============================================================================

var scanline_logic: ScanlineLogic
var scan_position: float = 0.0

# --- Ondas expansivas ---
# Cada onda es un anillo que se expande desde el centro de la pieza.
# Se guardan en un array y se actualizan cada frame.
var active_waves: Array = []

# --- Estelas persistentes ---
# Cada estela es el patrón de Turing que queda visible después
# de que la onda pasa. Persiste varios segundos y se desvanece.
var active_trails: Array = []

# --- Sistema de sectores ---
var sector_pulses: Dictionary = {}
var sector_count: int = 0

# --- Semilla para animación de patrones ---
# Varía lentamente con el tiempo para que los patrones de Turing
# tengan un movimiento sutil (como agua que respira).
var pattern_seed: float = 0.0

# --- Cache de viewport ---
var last_viewport_size: Vector2 = Vector2.ZERO


# ============================================================================
# SECCIÓN 3: CICLO DE VIDA
# ============================================================================

func _ready() -> void:
	scanline_logic = get_tree().root.find_child("ScanlineLogic", true, false)
	if scanline_logic:
		scanline_logic.crossing_detected.connect(_on_crossing_detected)
		scanline_logic.sector_activated.connect(_on_sector_activated)
		sector_count = scanline_logic.get_sector_count()
	else:
		print("[EffectsRenderer] ERROR: No se encontró ScanlineLogic")


func _process(delta: float) -> void:
	if scanline_logic:
		scan_position = scanline_logic.get_scan_position()
		sector_count = scanline_logic.get_sector_count()

	var ahora: float = Time.get_ticks_msec() / 1000.0

	# Actualizar listas de ondas y estelas
	_actualizar_ondas(ahora)
	_actualizar_estelas(ahora)

	# Animar la semilla para que los patrones se muevan lentamente
	pattern_seed += delta * 0.8

	queue_redraw()


# ============================================================================
# SECCIÓN 4: MANEJO DE SEÑALES
# ============================================================================

## Se llama cuando la línea de barrido CRUZA una pieza melódica.
## Las piezas melódicas son las que NO son sectoriales (actualmente: yellow).
## Crea una onda expansiva + estela en la posición de la pieza.
func _on_crossing_detected(piece: WebSocketManager.Piece) -> void:
	if not GestorFamilias.es_de_familia_activa(piece.color):
		return

	var viewport = get_viewport_rect().size
	var center := Vector2(piece.x * viewport.x, piece.y * viewport.y)
	_crear_efecto(piece.color, center)

	print("[EffectsRenderer] Cruzó %s en (%.2f, %.2f)" % [piece.color, piece.x, piece.y])


## Se llama cuando se ACTIVA UN SECTOR (compás completo).
## Las piezas sectoriales (pink, celeste, neon_green) se activan así.
## Crea una onda expansiva + estela en el centro del sector.
func _on_sector_activated(sector_index: int, y: float, color: String) -> void:
	if not GestorFamilias.es_de_familia_activa(color):
		return

	var viewport = get_viewport_rect().size
	if sector_count <= 0 or viewport.x <= 0:
		return

	var sector_width: float = viewport.x / sector_count
	var center_x: float = (sector_index + 0.5) * sector_width
	var center := Vector2(center_x, y * viewport.y)

	_crear_efecto(color, center)
	sector_pulses[sector_index] = Time.get_ticks_msec() / 1000.0

	print("[EffectsRenderer] Sector %s activado: sector %d" % [color, sector_index])


# ============================================================================
# SECCIÓN 5: CREACIÓN DE EFECTOS
# ============================================================================

## Crea una ONDA expansiva y una ESTELA persistente en la posición dada.
##
## Una "onda" es el anillo brillante que se expande (vive poco).
## Una "estela" es el patrón de Turing que queda visible (vive mucho).
##
## Ambas comparten la misma posición y color, pero tienen duraciones
## diferentes.
func _crear_efecto(color_name: String, center: Vector2) -> void:
	var ahora: float = Time.get_ticks_msec() / 1000.0

	# --- ONDA: efecto rápido que se expande ---
	active_waves.append({
		center = center,
		color_name = color_name,
		start_time = ahora,
		duration = wave_duration
	})

	# --- ESTELA: efecto lento que persiste ---
	active_trails.append({
		center = center,
		color_name = color_name,
		start_time = ahora,
		duration = trail_duration,
		intensity = 1.0,
		max_radius = pattern_radius  # permite variar radio por estela
	})


# ============================================================================
# SECCIÓN 6: ACTUALIZACIÓN DE ONDAS Y ESTELAS
# ============================================================================

## Elimina las ondas que ya expiraron.
func _actualizar_ondas(ahora: float) -> void:
	var keep: Array = []
	for wave in active_waves:
		if ahora - wave.start_time < wave.duration:
			keep.append(wave)
	active_waves = keep


## Actualiza la intensidad de las estelas y elimina las expiradas.
## La intensidad va de 1.0 (recién creada) a 0.0 (a punto de expirar).
func _actualizar_estelas(ahora: float) -> void:
	var keep: Array = []
	for trail in active_trails:
		var edad: float = ahora - trail.start_time
		if edad < trail.duration:
			trail.intensity = 1.0 - (edad / trail.duration)
			keep.append(trail)
	active_trails = keep


# ============================================================================
# SECCIÓN 7: PATRONES DE TURING
# ============================================================================
#
# ¿QUÉ SON LOS PATRONES DE TURING?
#   Alan Turing descubrió que ciertos patrones naturales (manchas de
#   leopardo, rayas de cebra, espirales de caracol) surgen de un
#   sistema de reacción-difusión. Acá simulamos estos patrones usando
#   funciones matemáticas (seno, coseno) que imitan ese comportamiento.
#
# Cada color de la familia tiene su propio patrón:
#   "spots"     → manchas punteadas
#   "stripes"   → rayas onduladas
#   "spiral"    → espirales
#   "labyrinth" → laberinto
#
# CÓMO AGREGAR UN NUEVO PATRÓN:
#   1. Crear una función _dibujar_patron_mi_patron(x, y, semilla) → bool
#   2. Agregar el case en _evaluar_patron()
#   3. Asignarlo a un color en GestorFamilias.gd
#


## Evalúa si el punto (x, y) pertenece al patrón de Turing del color indicado.
##
## Parámetros:
##   x, y: coordenadas RELATIVAS al centro de la pieza (en píxeles)
##   semilla: valor que varía con el tiempo para animar el patrón
##
## Devuelve: true si el punto debe dibujarse como parte del patrón.
func _evaluar_patron(color_name: String, x: float, y: float, semilla: float) -> bool:
	var patron: String = GestorFamilias.get_patron(color_name)

	match patron:
		"spots":
			return _patron_manchas(x, y, semilla)
		"stripes":
			return _patron_rayas(x, y, semilla)
		"spiral":
			return _patron_espiral(x, y, semilla)
		"labyrinth":
			return _patron_laberinto(x, y, semilla)
		_:
			return false


## PATRÓN: MANCHAS (SPOTS)  →  Yellow
## --------------------------------------------------------------------------
## Simula manchas de leopardo o jirafa.
## Usa una combinación de ondas senoidales 2D con un umbral.
## Cada "mancha" es una zona donde la función supera el umbral.
func _patron_manchas(x: float, y: float, semilla: float) -> bool:
	var f: float = 0.07  # frecuencia base
	var v1: float = sin(x * f + semilla) * cos(y * f * 1.3 + semilla * 0.7)
	var v2: float = sin((x + y) * f * 0.7 + semilla * 0.3)
	var v3: float = cos(x * f * 0.5 - y * f * 0.9 + semilla * 0.5)
	var valor: float = v1 + v2 * 0.6 + v3 * 0.4
	return valor > 0.25  # umbral: más alto = manchas más chicas y separadas


## PATRÓN: RAYAS (STRIPES)  →  Pink
## --------------------------------------------------------------------------
## Simula rayas de cebra o tigre.
## Usa ondas senoidales en una dirección principal con una leve modulación
## lateral para que las rayas no sean perfectamente rectas.
func _patron_rayas(x: float, y: float, semilla: float) -> bool:
	var f: float = 0.05
	var angulo: float = 0.3  # inclinación de las rayas (radianes)
	# Rotar coordenadas para que las rayas tengan un ángulo
	var xr: float = x * cos(angulo) - y * sin(angulo)
	var yr: float = x * sin(angulo) + y * cos(angulo)
	# Onda principal (rayas) + modulación suave
	var v1: float = sin(xr * f + semilla)
	var v2: float = cos(yr * f * 2.0 + semilla * 0.5) * 0.3
	var valor: float = v1 + v2
	return abs(valor) > 0.35


## PATRÓN: ESPIRAL (SPIRAL)  →  Celeste
## --------------------------------------------------------------------------
## Simula una concha de caracol o galaxia espiral.
## Usa coordenadas polares (radio + ángulo) para crear brazos espirales
## que giran desde el centro hacia afuera.
func _patron_espiral(x: float, y: float, semilla: float) -> bool:
	var r: float = sqrt(x * x + y * y)
	if r < 2.0:
		return true  # centro siempre lleno
	var theta: float = atan2(y, x)
	var vueltas: float = 6.0  # cantidad de brazos espirales
	var f_radial: float = 0.12
	var v: float = sin(theta * vueltas + r * f_radial * 3.0 + semilla)
	return v > 0.0


## PATRÓN: LABERINTO (LABYRINTH)  →  Neon Green
## --------------------------------------------------------------------------
## Simula un patrón de ameba o laberinto.
## Usa la suma de múltiples ondas senoidales en diferentes direcciones,
## creando un patrón complejo e interconectado.
func _patron_laberinto(x: float, y: float, semilla: float) -> bool:
	var f: float = 0.04
	var v1: float = sin(x * f + y * f * 1.2 + semilla)
	var v2: float = sin(x * f * 0.8 - y * f * 1.5 + semilla * 0.7)
	var v3: float = sin((x + y) * f * 0.5 + semilla * 1.3)
	var v4: float = sin((x - y) * f * 1.1 + semilla * 0.2)
	var valor: float = v1 + v2 + v3 * 0.5 + v4 * 0.3
	return valor > 0.45


# ============================================================================
# SECCIÓN 8: DIBUJADO (_draw)
# ============================================================================
# El orden de dibujado define qué capa queda arriba/abajo:
#   1. ESTELAS (lo más al fondo)
#   2. Rectángulos de sector
#   3. Sombra amarilla (soga)
#   4. ONDAS expansivas
#   5. Línea de barrido (lo más arriba)

func _draw() -> void:
	# Capa 1 — Fondo: estelas persistentes
	_dibujar_estelas()

	# Capa 2 — Rectángulos de sector
	_draw_sector_rectangles()

	# Capa 3 — Sombra amarilla (soga)
	_draw_yellow_shadow()

	# Capa 4 — Ondas expansivas
	_dibujar_ondas()

	# Capa 5 — Línea de barrido
	_draw_scanline()

	# Guardar tamaño del viewport para usarlo entre frames
	last_viewport_size = get_viewport_rect().size


# --------------------------------------------------------------------------
# 8.1: DIBUJAR ESTELAS
# --------------------------------------------------------------------------
# Dibuja los patrones de Turing persistentes en las posiciones donde
# pasaron las ondas. Cada estela se dibuja con su intensidad actual
# (va de 1.0 a 0.0 a medida que envejece).
#
# El patrón se muestrea en una grilla dentro del radio de la estela.
# Cada punto de la grilla que supera el umbral del patrón se dibuja
# como un pequeño cuadrado.

func _dibujar_estelas() -> void:
	if active_trails.is_empty():
		return

	var viewport := get_viewport_rect().size
	if viewport.x <= 0 or viewport.y <= 0:
		return

	for trail in active_trails:
		var color_name: String = trail.color_name
		var centro: Vector2 = trail.center
		var radio: float = trail.max_radius * trail.intensity
		var intensidad: float = trail.intensity

		# Obtener el color base del patrón
		var color_patron: Color = GestorFamilias.get_color(color_name)

		# Ajustar opacidad según intensidad de la estela
		color_patron.a = intensidad * 0.6

		if color_patron.a < 0.02:
			continue

		# Recorrer la grilla dentro del radio de la estela
		var inicio_x: float = centro.x - radio
		var fin_x: float = centro.x + radio
		var inicio_y: float = centro.y - radio
		var fin_y: float = centro.y + radio

		var px: float = inicio_x
		while px < fin_x:
			var py: float = inicio_y
			while py < fin_y:
				var dx: float = px - centro.x
				var dy: float = py - centro.y
				var dist: float = sqrt(dx * dx + dy * dy)

				# Solo dentro del círculo
				if dist > radio:
					py += pattern_spacing
					continue

				# Desvanecer hacia los bordes (efecto agua)
				var fade_borde: float = 1.0 - (dist / radio)
				var alpha_punto: float = intensidad * fade_borde

				if alpha_punto < 0.05:
					py += pattern_spacing
					continue

				# Evaluar el patrón de Turing en este punto
				if _evaluar_patron(color_name, dx, dy, pattern_seed + dist * 0.1):
					var c: Color = color_patron
					c.a = alpha_punto * 0.7

					# Dibujar un cuadrado pequeño en la posición del patrón
					var cell: float = pattern_spacing * 0.45
					draw_rect(Rect2(px - cell * 0.5, py - cell * 0.5, cell, cell), c)

				py += pattern_spacing
			px += pattern_spacing


# --------------------------------------------------------------------------
# 8.2: DIBUJAR ONDAS EXPANSIVAS
# --------------------------------------------------------------------------
# Dibuja un tren de anillos concéntricos que se expanden desde el centro
# de cada pieza activada.
#
# Cada onda tiene:
#   - Un anillo exterior brillante (frente de onda)
#   - Varios anillos interiores más suaves (estela de la onda)
# Esto simula el comportamiento de una perturbación en el agua.

func _dibujar_ondas() -> void:
	if active_waves.is_empty():
		return

	var ahora: float = Time.get_ticks_msec() / 1000.0

	for wave in active_waves:
		var edad: float = ahora - wave.start_time
		var progreso: float = edad / wave.duration  # 0 → 1
		var color_name: String = wave.color_name
		var centro: Vector2 = wave.center

		# Radio actual de expansión
		var radio_actual: float = progreso * max_wave_radius

		# Intensidad general de la onda (disminuye con el tiempo)
		var intensidad: float = 1.0 - progreso

		# Color de la onda
		var color_onda: Color = GestorFamilias.get_color(color_name)

		# --- Tren de anillos concéntricos ---
		for j in range(wave_ring_count):
			var radio_anillo: float = radio_actual * (1.0 - j * 0.12)

			if radio_anillo < 2.0:
				continue

			# Cada anillo es más tenue y fino hacia adentro
			var alpha_anillo: float = intensidad * (1.0 - j * 0.25)
			var grosor_anillo: float = (4.0 - j * 1.0) * intensidad

			if alpha_anillo < 0.02 or grosor_anillo < 0.5:
				continue

			var c: Color = color_onda
			c.a = alpha_anillo

			# Resolución del arco: menos puntos para anillos interiores
			var segmentos: int = max(16, 64 - j * 12)

			draw_arc(centro, radio_anillo, 0, TAU, segmentos, c, grosor_anillo)


# --------------------------------------------------------------------------
# 8.3: RECTÁNGULOS DE SECTOR (igual que en v1)
# --------------------------------------------------------------------------

func _draw_sector_rectangles() -> void:
	if scanline_logic == null:
		return
	var viewport = get_viewport_rect().size
	if viewport.x <= 0 or viewport.y <= 0:
		return
	var s_count = scanline_logic.get_sector_count()
	if s_count <= 0:
		return
	var sector_width = viewport.x / s_count

	for i in range(s_count):
		var sector_data = scanline_logic.sector_colors.get(i)
		if sector_data == null:
			continue

		for color in sector_data:
			var y = sector_data[color]

			var rect_color: Color = GestorFamilias.get_color(color)
			rect_color.a = sector_alpha

			var rect_x = i * sector_width
			var rect_w = sector_width
			var rect_h = rect_height
			var center_y = y * viewport.y
			var rect_y = center_y - rect_h / 2.0
			draw_rect(Rect2(rect_x, rect_y, rect_w, rect_h), rect_color)


# --------------------------------------------------------------------------
# 8.4: SOMBRA AMARILLA (soga)  — igual que en v1
# --------------------------------------------------------------------------

func _draw_yellow_shadow() -> void:
	if scanline_logic == null:
		return
	var yellows = scanline_logic.get_yellow_pieces()
	if yellows.is_empty():
		return
	var viewport = get_viewport_rect().size
	if viewport.x <= 0 or viewport.y <= 0:
		return

	yellows.sort_custom(func(a, b): return a.x < b.x)
	var h = rect_height
	var color = Color(1.0, 1.0, 0.0, yellow_shadow_alpha)
	var w = viewport.x
	var first = yellows[0]
	var last = yellows[yellows.size() - 1]

	var points = PackedVector2Array()
	# Borde superior: borde izquierdo → cada pieza → borde derecho
	points.append(Vector2(0, first.y * viewport.y - h / 2.0))
	for yp in yellows:
		points.append(Vector2(yp.x * w, yp.y * viewport.y - h / 2.0))
	points.append(Vector2(w, last.y * viewport.y - h / 2.0))
	# Borde inferior: borde derecho → cada pieza (inverso) → borde izquierdo
	points.append(Vector2(w, last.y * viewport.y + h / 2.0))
	for i in range(yellows.size() - 1, -1, -1):
		var yp = yellows[i]
		points.append(Vector2(yp.x * w, yp.y * viewport.y + h / 2.0))
	points.append(Vector2(0, first.y * viewport.y + h / 2.0))

	draw_colored_polygon(points, color)


# --------------------------------------------------------------------------
# 8.5: LÍNEA DE BARRIDO  — igual que en v1
# --------------------------------------------------------------------------

func _draw_scanline() -> void:
	var viewport = get_viewport_rect().size
	var x = scan_position * viewport.x
	draw_line(Vector2(x, 0), Vector2(x, viewport.y), scan_line_color, scan_line_width)
