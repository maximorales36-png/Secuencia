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
#   Celeste    → Espiral     (como concha de caracol)
#   Neon Green → Laberinto   (como ameba)
#   Yellow     → Manchas     (como leopardo)
#   Pink       → Pufferfish  (como pez globo: retícula hexagonal)
#
# CÓMO MODIFICAR:
#   • Colores y patrones: editar GestorFamilias.gd → FAMILIAS
#   • Duración de estelas: cambiar trail_duration (abajo)
#   • Velocidad de onda: cambiar wave_duration (abajo)
#   • Nuevo patrón: agregar función en SECCIÓN 7 y
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

## Duración de la onda expansiva (segundos) — más lenta para apreciar la expansión
@export var wave_duration: float = 1.2

## Duración de la estela persistente (segundos) — más larga, se diluye lentamente
@export var trail_duration: float = 8.0

## Radio máximo de la onda expansiva (píxeles)
@export var max_wave_radius: float = 300.0

## Radio del área cubierta por el patrón de Turing (píxeles)
@export var pattern_radius: float = 220.0

## CANTIDAD de círculos: separación entre centros (menor = más círculos, más detalle)
@export var pattern_spacing: float = 10.0

## DIÁMETRO relativo de cada círculo (0.0–1.0, respecto a la separación).
## 0.5 → los círculos apenas se tocan. 0.7 → muy solapados (Voronoi). 0.3 → puntitos sueltos.
@export var diametro_circulo: float = 0.5

## Cantidad de anillos en el tren de ondas
@export var wave_ring_count: int = 4

## Ancho de la línea de barrido (píxeles)
@export var scan_line_width: float = 5.0

## Color de la línea de barrido (alpha base, multiplicado por ani_contraste)
@export var scan_line_color: Color = Color(1.0, 0.62, 0.0, 0.69)

## Opacidad de la sombra amarilla (soga)
@export var yellow_shadow_alpha: float = 0.15

## Altura del rectángulo de sector (píxeles)
@export var rect_height: float = 80.0

## Opacidad de los rectángulos de sector
@export var sector_alpha: float = 0.15

## Contraste general de las visualizaciones (0.0 = invisible, 1.0 = máximo)
## Multiplica la opacidad de todos los efectos: ondas, estelas, sectores, etc.
@export var ani_contraste: float = 1.0


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

# --- Saturación dinámica para pink/celeste controlada por violeta ---
# Violet es un controlador global: cuando está abajo (y cerca de 1),
# la saturación de pink y celeste se reduce.
var _violet_saturation: float = 1.0

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

	# Actualizar saturación controlada por violeta
	_update_violet_saturation()

	queue_redraw()


# ============================================================================
# SECCIÓN 4: MANEJO DE SEÑALES
# ============================================================================

## Se llama cuando la línea de barrido CRUZA una pieza melódica.
## Las piezas melódicas son las que NO son sectoriales (actualmente: yellow).
## Crea una onda expansiva + estela en la posición de la pieza.
func _on_crossing_detected(piece: IPCManager.Piece) -> void:
	if not GestorFamilias.es_de_familia_activa(piece.color):
		return
	if piece.color == "violet":
		return

	var viewport = get_viewport_rect().size
	var center := Vector2(piece.x * viewport.x, piece.y * viewport.y)
	_crear_efecto(piece.color, center)

	print("[EffectsRenderer] Cruzó %s en (%.2f, %.2f)" % [piece.color, piece.x, piece.y])


## Se llama cuando se ACTIVA UN SECTOR (compás completo).
## Las piezas sectoriales (pink, celeste, neon_green) se activan así.
## Crea una onda expansiva + estela ORGÁNICA con forma de sector.
func _on_sector_activated(sector_index: int, y: float, color: String) -> void:
	if not GestorFamilias.es_de_familia_activa(color):
		return

	var viewport = get_viewport_rect().size
	if sector_count <= 0 or viewport.x <= 0:
		return

	var sector_width: float = viewport.x / sector_count
	var center_x: float = (sector_index + 0.5) * sector_width
	var center := Vector2(center_x, y * viewport.y)

	# Pasar sector_index para que cree estela con forma orgánica sectorial
	_crear_efecto(color, center, sector_index, y)
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
## Para piezas sectoriales (sector_index >= 0), la estela usa un
## polígono orgánico con forma de la región (procariota).
## Para piezas melódicas (sector_index < 0), la estela es circular.
func _crear_efecto(color_name: String, center: Vector2, sector_index: int = -1, y_pos: float = -1.0) -> void:
	var ahora: float = Time.get_ticks_msec() / 1000.0

	# --- ONDA: efecto rápido que se expande ---
	active_waves.append({
		center = center,
		color_name = color_name,
		start_time = ahora,
		duration = wave_duration
	})

	# --- ESTELA: efecto lento que persiste ---
	var trail_data: Dictionary = {
		center = center,
		color_name = color_name,
		start_time = ahora,
		duration = trail_duration,
		intensity = 1.0,
		shape_type = "circle",      # por defecto: circular
		max_radius = pattern_radius
	}

	# Si tiene sector_index, es una estela sectorial con forma orgánica
	if sector_index >= 0 and y_pos >= 0.0:
		var viewport = get_viewport_rect().size
		if viewport.x > 0 and sector_count > 0:
			var s_width: float = viewport.x / sector_count
			var rect_x: float = sector_index * s_width
			var rect_w: float = s_width
			var rect_h: float = rect_height
			var rect_y: float = (y_pos * viewport.y) - rect_h / 2.0
			var sector_rect := Rect2(rect_x, rect_y, rect_w, rect_h)

			# Expandir ligeramente el rect para que el polígono
			# se sienta más orgánico y menos contenido
			sector_rect = sector_rect.grow(s_width * 0.08)

			trail_data.shape_type = "sector"
			trail_data.sector_rect = sector_rect
			trail_data.sector_polygon = _generar_poligono_organico(sector_rect, ahora)

	active_trails.append(trail_data)


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
# SECCIÓN 6.5: SATURACIÓN CONTROLADA POR VIOLETA
# ============================================================================
# Violeta es un controlador global. Cuando está cerca del borde inferior
# (y → 1.0, RTPC → 0), la saturación de pink y celeste se reduce.
# Cuando no hay violeta, la saturación vuelve al 100%.

func _update_violet_saturation() -> void:
	if scanline_logic == null:
		_violet_saturation = 1.0
		return
	var found := false
	var highest_y := 1.0
	for piece in scanline_logic.pieces:
		if piece.color == "violet" and piece.y < highest_y:
			highest_y = piece.y
			found = true
	if found:
		var rtpc = (1.0 - highest_y) * 100.0
		_violet_saturation = 0.0 + 1.0 * (rtpc / 100.0)
	else:
		_violet_saturation = 1.0


## Reduce la saturación del color si es pink o celeste,
## según la posición del violeta.
func _ajustar_saturacion(color: Color, nombre_color: String) -> Color:
	if nombre_color in ["pink", "celeste"]:
		var c: Color = color
		c.s = c.s * _violet_saturation
		return c
	return color


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
		"pufferfish":
			return _patron_pufferfish(x, y, semilla)
		_:
			return false


## PATRÓN: MANCHAS (SPOTS)  →  Yellow
## --------------------------------------------------------------------------
## Grandes manchas redondeadas aisladas (como dálmata o jirafa).
## Usa baja frecuencia + umbral alto para crear manchas separadas,
## bien definidas y de gran tamaño.
func _patron_manchas(x: float, y: float, semilla: float) -> bool:
	var f: float = 0.04       # frecuencia baja → manchas grandes
	var v1: float = sin(x * f + semilla) * cos(y * f * 1.3 + semilla * 0.7)
	var v2: float = sin((x + y) * f * 0.7 + semilla * 0.3)
	var v3: float = cos(x * f * 0.5 - y * f * 0.9 + semilla * 0.5)
	var valor: float = v1 + v2 * 0.6 + v3 * 0.4
	return valor > 0.6        # umbral alto → manchas separadas y definidas


## PATRÓN: RAYAS (STRIPES)  →  Pink
## --------------------------------------------------------------------------
## Rayas gruesas y diagonales con ondulación suave (como cebra).
## Las rayas cruzan el área en un ángulo pronunciado y tienen
## un grosor uniforme gracias al umbral simétrico (abs).
func _patron_rayas(x: float, y: float, semilla: float) -> bool:
	var f: float = 0.03       # frecuencia baja → rayas anchas
	var angulo: float = 0.6   # inclinación diagonal (radianes)
	var xr: float = x * cos(angulo) - y * sin(angulo)
	var yr: float = x * sin(angulo) + y * cos(angulo)
	# Onda principal (genera las rayas) + modulación suave lateral
	var v1: float = sin(xr * f + semilla)
	var v2: float = cos(yr * f * 1.5 + semilla * 0.5) * 0.4
	var valor: float = v1 + v2
	return abs(valor) > 0.15  # umbral bajo → rayas gruesas y llenas


## PATRÓN: ESPIRAL (SPIRAL)  →  Celeste
## --------------------------------------------------------------------------
## Brazos espirales anchos que giran desde el centro (como galaxia).
## Usa pocos brazos (3) con una frecuencia radial baja para que
## las espirales sean amplias y abiertas.
func _patron_espiral(x: float, y: float, semilla: float) -> bool:
	var r: float = sqrt(x * x + y * y)
	if r < 4.0:
		return true           # centro siempre lleno
	var theta: float = atan2(y, x)
	var vueltas: float = 3.0  # pocos brazos → más gruesos
	var f_radial: float = 0.06
	var v: float = sin(theta * vueltas + r * f_radial * 2.0 + semilla)
	return v > 0.0


## PATRÓN: LABERINTO (LABYRINTH)  →  Neon Green
## --------------------------------------------------------------------------
## Patrón denso e interconectado (como ameba o redes neuronales).
## Usa múltiples ondas en distintas direcciones para crear un
## entramado complejo sin zonas vacías grandes.
func _patron_laberinto(x: float, y: float, semilla: float) -> bool:
	var f: float = 0.03       # frecuencia baja → formas grandes
	var v1: float = sin(x * f + y * f * 1.2 + semilla)
	var v2: float = sin(x * f * 0.8 - y * f * 1.5 + semilla * 0.7)
	var v3: float = sin((x + y) * f * 0.7 + semilla * 1.3)
	var v4: float = sin((x - y) * f * 1.3 + semilla * 0.2)
	var v5: float = cos(x * f * 0.5 + y * f * 0.9 + semilla * 0.9)
	var valor: float = v1 + v2 + v3 * 0.6 + v4 * 0.4 + v5 * 0.5
	return valor > 0.1        # umbral bajo → patrón denso y conectado


## PATRÓN: PUFFERFISH  →  Pink
## --------------------------------------------------------------------------
## Patrón reticulado inspirado en el pez globo (Tetraodontidae).
## Crea una red poligonal interconectada (tipo panal) con manchas
## redondeadas en las intersecciones, similar al patrón dorsal del
## pez globo Valentini o Fugu.
##
## Técnica: tres ondas senoidales en direcciones a 60° para generar
## interferencia hexagonal, combinadas con un coseno que añade
## pequeñas islas-redondeadas en los nodos de la red.
func _patron_pufferfish(x: float, y: float, semilla: float) -> bool:
	var f: float = 0.07
	# Tres direcciones a 60° para crear retícula hexagonal
	var y_proj: float = y * f
	var x1_proj: float = (x * 0.866 + y * 0.5) * f
	var x2_proj: float = (-x * 0.866 + y * 0.5) * f
	var v1: float = sin(y_proj + semilla * 0.5)
	var v2: float = sin(x1_proj + semilla)
	var v3: float = sin(x2_proj + semilla * 0.8)
	# Islas adicionales en nodos de la red
	var v4: float = cos(y_proj * 0.7 + x1_proj * 0.7 + semilla * 1.2) * 0.5
	var valor: float = v1 + v2 + v3 + v4
	return valor > -0.3      # umbral bajo para red interconectada


# ============================================================================
# SECCIÓN 8: FUNCIONES AUXILIARES DE PATRONES
# ============================================================================

## Genera un desplazamiento pseudoaleatorio para crear el efecto Voronoi.
## Toma las coordenadas de la celda (cx, cy) y devuelve un Vector2
## con un offset determinista entre -max y +max.
##
## Esto hace que los puntos de la grilla se desplacen dando la
## sensación de un diagrama de Thiessen (Voronoi) orgánico.
func _jitter(cx: float, cy: float, max_jitter: float) -> Vector2:
	var n: float = sin(cx * 127.1 + cy * 311.7) * 43758.5453
	var hx: float = n - floor(n)
	var hy: float = sin(n * 17.1 + cx * 3.7) * 0.5 + 0.5
	return Vector2((hx - 0.5) * max_jitter, (hy - 0.5) * max_jitter)


## Genera un polígono cerrado con bordes orgánicos (tipo procariota).
## Toma un rectángulo base y lo deforma con jitter en cada vértice,
## creando una forma celular irregular.
##
## Útil para darle a los sectores una apariencia de célula viva
## en lugar de un rectángulo geométrico perfecto.
func _generar_poligono_organico(rect: Rect2, semilla: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var pts_per_side: int = 10  # vértices por lado (más = más detalle)

	for i in range(4 * pts_per_side):
		var side: int = i / pts_per_side
		var t: float = float(i % pts_per_side) / float(pts_per_side)

		# Posición base en el perímetro del rectángulo
		var base: Vector2
		match side:
			0: base = Vector2(rect.position.x + t * rect.size.x, rect.position.y)
			1: base = Vector2(rect.position.x + rect.size.x, rect.position.y + t * rect.size.y)
			2: base = Vector2(rect.position.x + (1.0 - t) * rect.size.x, rect.position.y + rect.size.y)
			3: base = Vector2(rect.position.x, rect.position.y + (1.0 - t) * rect.size.y)

		# Jitter perpendicular al borde para deformar orgánicamente
		var jitter_amount: float = 8.0 + sin(semilla + i * 0.3) * 5.0
		var j: Vector2 = _jitter(base.x * 0.05 + semilla, base.y * 0.05 + i, jitter_amount)
		points.append(base + j)

	return points


# ============================================================================
# SECCIÓN 9: DIBUJADO (_draw)
# ============================================================================
# El orden de dibujado define qué capa queda arriba/abajo:
#   1. ESTELAS con aspecto Voronoi (lo más al fondo)
#   2. Rectángulos de sector
#   3. Sombra amarilla (soga)
#   4. ONDAS expansivas
#   5. Línea de barrido (lo más arriba)

func _draw() -> void:
	# Capa 1 — Fondo: estelas persistentes con forma orgánica
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
# 9.1: DIBUJAR ESTELAS — con aspecto orgánico tipo Voronoi
# --------------------------------------------------------------------------
# Dibuja los patrones de Turing persistentes en las posiciones donde
# pasaron las ondas.
#
# TÉCNICA VISUAL:
#   En lugar de una grilla de cuadrados rígidos, usamos PUNTOS DE SEMILLA
#   con desplazamiento pseudoaleatorio (jitter). Cada punto activo se
#   dibuja como un CÍRCULO que se solapa con sus vecinos, generando
#   un aspecto celular orgánico similar a:
#     • Diagramas de Voronoi (Thiessen)
#     • Tejido biológico visto al microscopio
#     • Panal de abejas irregular
#
# CÓMO MODIFICAR EL ASPECTO:
#   • pattern_spacing → separación entre semillas (menor = más detalle)
#   • Ajustar el radio de los círculos en la fórmula de abajo
#   • El jitter_amount controla cuánto se dispersan las semillas

func _dibujar_estelas() -> void:
	if active_trails.is_empty():
		return

	var viewport := get_viewport_rect().size
	if viewport.x <= 0 or viewport.y <= 0:
		return

	for trail in active_trails:
		match trail.shape_type:
			"circle":
				_dibujar_estela_circular(trail)
			"sector":
				_dibujar_estela_sector(trail)


## Dibuja una estela circular (para piezas melódicas como yellow).
## Usa un área circular alrededor del centro, con fade uniforme.
func _dibujar_estela_circular(trail: Dictionary) -> void:
	var color_name: String = trail.color_name
	var centro: Vector2 = trail.center
	var radio: float = trail.max_radius * trail.intensity
	var intensidad: float = trail.intensity

	var color_patron: Color = _ajustar_saturacion(GestorFamilias.get_color(color_name), color_name)
	color_patron.a = intensidad * 0.9 * ani_contraste
	if color_patron.a < 0.02:
		return

	var jitter_amount: float = pattern_spacing * 0.45
	var inicio_x: float = centro.x - radio
	var fin_x: float = centro.x + radio
	var inicio_y: float = centro.y - radio
	var fin_y: float = centro.y + radio

	var cx: float = inicio_x
	while cx < fin_x:
		var cy: float = inicio_y
		while cy < fin_y:
			var j: Vector2 = _jitter(cx, cy, jitter_amount)
			var sx: float = cx + j.x
			var sy: float = cy + j.y

			var dx: float = sx - centro.x
			var dy: float = sy - centro.y
			var dist: float = sqrt(dx * dx + dy * dy)

			if dist > radio:
				cy += pattern_spacing
				continue

			# FADE UNIFORME: no se desvanece hacia los bordes,
			# toda el área se desvanece al mismo ritmo.
			var alpha_punto: float = intensidad * ani_contraste

			if alpha_punto < 0.05:
				cy += pattern_spacing
				continue

			if _evaluar_patron(color_name, dx, dy, pattern_seed + dist * 0.1):
				var c: Color = color_patron
				c.a = alpha_punto

				var radio_celula: float = pattern_spacing * diametro_circulo
				draw_circle(Vector2(sx, sy), radio_celula, c)

			cy += pattern_spacing
		cx += pattern_spacing


## Dibuja una estela sectorial con forma orgánica (para piezas sectoriales
## como pink, celeste, neon_green).
##
## En lugar de un círculo, el patrón se dibuja dentro de un polígono
## orgánico que imita la forma de una célula (procariota), creado
## a partir del rectángulo del sector con bordes deformados.
##
## El fade es uniforme en toda la superficie: la estela se desvanece
## completa en lugar de hacerlo desde los bordes hacia el centro.
func _dibujar_estela_sector(trail: Dictionary) -> void:
	var color_name: String = trail.color_name
	var intensidad: float = trail.intensity
	var polygon: PackedVector2Array = trail.get("sector_polygon", PackedVector2Array())
	var sector_rect: Rect2 = trail.get("sector_rect", Rect2())

	if polygon.is_empty() or sector_rect.size.x <= 0 or sector_rect.size.y <= 0:
		return

	var color_patron: Color = _ajustar_saturacion(GestorFamilias.get_color(color_name), color_name)
	color_patron.a = intensidad * 0.9 * ani_contraste
	if color_patron.a < 0.02:
		return

	var jitter_amount: float = pattern_spacing * 0.45

	# Recorrer la grilla dentro del rectángulo del sector
	var cx: float = sector_rect.position.x
	while cx < sector_rect.position.x + sector_rect.size.x:
		var cy: float = sector_rect.position.y
		while cy < sector_rect.position.y + sector_rect.size.y:
			var j: Vector2 = _jitter(cx, cy, jitter_amount)
			var sx: float = cx + j.x
			var sy: float = cy + j.y

			# Verificar si el punto está dentro del polígono orgánico
			if not Geometry2D.is_point_in_polygon(Vector2(sx, sy), polygon):
				cy += pattern_spacing
				continue

			var dx: float = sx - trail.center.x
			var dy: float = sy - trail.center.y
			var dist: float = sqrt(dx * dx + dy * dy)

			# FADE UNIFORME: toda la superficie se desvanece igual
			var alpha_punto: float = intensidad * ani_contraste

			if alpha_punto < 0.05:
				cy += pattern_spacing
				continue

			if _evaluar_patron(color_name, dx, dy, pattern_seed + dist * 0.1):
				var c: Color = color_patron
				c.a = alpha_punto

				var radio_celula: float = pattern_spacing * diametro_circulo
				draw_circle(Vector2(sx, sy), radio_celula, c)

			cy += pattern_spacing
		cx += pattern_spacing


# --------------------------------------------------------------------------
# 9.2: DIBUJAR ONDAS EXPANSIVAS
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
		var color_onda: Color = _ajustar_saturacion(GestorFamilias.get_color(color_name), color_name)

		# --- Tren de anillos concéntricos ---
		for j in range(wave_ring_count):
			var radio_anillo: float = radio_actual * (1.0 - j * 0.12)

			if radio_anillo < 2.0:
				continue

			# Cada anillo es más tenue y fino hacia adentro
			var alpha_anillo: float = intensidad * (1.0 - j * 0.25) * ani_contraste
			var grosor_anillo: float = (4.0 - j * 1.0) * intensidad

			if alpha_anillo < 0.02 or grosor_anillo < 0.5:
				continue

			var c: Color = color_onda
			c.a = alpha_anillo

			# Resolución del arco: menos puntos para anillos interiores
			var segmentos: int = max(16, 64 - j * 12)

			draw_arc(centro, radio_anillo, 0, TAU, segmentos, c, grosor_anillo)


# --------------------------------------------------------------------------
# 9.3: RECTÁNGULOS DE SECTOR (igual que en v1)
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

			var rect_color: Color = _ajustar_saturacion(GestorFamilias.get_color(color), color)
			rect_color.a = sector_alpha * ani_contraste

			var rect_x = i * sector_width
			var rect_w = sector_width
			var rect_h = rect_height
			var center_y = y * viewport.y
			var rect_y = center_y - rect_h / 2.0
			draw_rect(Rect2(rect_x, rect_y, rect_w, rect_h), rect_color)


# --------------------------------------------------------------------------
# 9.4: SOMBRA AMARILLA (soga)  — igual que en v1
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
	var color = Color(1.0, 1.0, 0.0, yellow_shadow_alpha * ani_contraste)
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
# 9.5: LÍNEA DE BARRIDO  — igual que en v1
# --------------------------------------------------------------------------

func _draw_scanline() -> void:
	var viewport = get_viewport_rect().size
	var x = scan_position * viewport.x
	var c: Color = scan_line_color
	c.a = scan_line_color.a * ani_contraste
	draw_line(Vector2(x, 0), Vector2(x, viewport.y), c, scan_line_width)
