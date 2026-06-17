extends Control


func _draw() -> void:
	for piece in IPCManager.pieces:
		var pos := Vector2(piece.x * size.x, piece.y * size.y)
		var col := GestorFamilias.get_color(piece.color)
		draw_circle(pos, 14.0, col)
		draw_circle(pos, 14.0, Color(1, 1, 1, 0.35), false, 2.0)
