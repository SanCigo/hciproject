extends Control

# ==============================================================================
# DrawCanvas — A Control that draws a gesture trail.
# The parent scene drives it via set_points() / clear().
# ==============================================================================

var _points: Array[Vector2] = []

func set_points(pts: Array[Vector2]) -> void:
	_points = pts
	queue_redraw()

func clear_points() -> void:
	_points.clear()
	queue_redraw()

func _draw() -> void:
	# Background is handled by the Panel child, so we only draw the trail here.
	if _points.size() < 2:
		return

	for i in range(1, _points.size()):
		var t := float(i) / float(_points.size())
		# Gradient: green → cyan → magenta
		var col := Color(0.2 + t * 0.8, 1.0 - t * 0.6, 0.4 + t * 0.6, 1.0)
		draw_line(_points[i - 1], _points[i], col, 3.0)

	# Start dot (green) and end dot (red)
	draw_circle(_points[0], 7.0, Color(0.2, 1.0, 0.3, 1))
	draw_circle(_points[_points.size() - 1], 7.0, Color(1.0, 0.3, 0.2, 1))
