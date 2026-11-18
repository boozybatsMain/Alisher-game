extends Control
## Круглая иконка щита с перезарядкой: тёмный сектор убывает по часовой, при нажатии во время перезарядки — красная вспышка.

var cd := 0.0
var cd_max := 1.0
var deny := 0.0

const R := 30.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	var full := cd <= 0.0
	draw_circle(Vector2.ZERO, R, Color(0.1, 0.055, 0.04, 0.92))
	draw_arc(Vector2.ZERO, R, 0.0, TAU, 48, Color(0.37, 0.9, 0.83) if full else Color(0.48, 0.35, 0.24), 3.5, true)
	var c := Color(0.92, 1.0, 0.98) if full else Color(0.55, 0.48, 0.42)
	draw_arc(Vector2.ZERO, R * 0.55, 0.0, TAU, 32, c, 3.5, true)
	draw_circle(Vector2.ZERO, R * 0.2, c)
	var frac := cd / maxf(0.01, cd_max)
	if not full and frac > 0.03:
		var pts := PackedVector2Array([Vector2.ZERO])
		for i in 33:
			var a := -PI / 2.0 + TAU * minf(frac, 0.985) * i / 32.0
			pts.append(Vector2(cos(a), sin(a)) * (R - 1.0))
		draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
	if deny > 0.0:
		draw_arc(Vector2.ZERO, R + 4.0, 0.0, TAU, 48, Color(1.0, 0.28, 0.2, deny), 5.0, true)
