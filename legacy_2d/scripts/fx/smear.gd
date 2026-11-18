extends Node2D
## Широкая дуга удара врага (огненная у балбала и Шойынқұлақа, кровавая у Жезтырнак):
## прочерчивается за 0.07 с и гаснет — видно, докуда достаёт удар.

var face := 1
var radius := 300.0
var palette := "fire"
var life := 0.0

const LIFE := 0.24
const COLORS := {
	"fire": [Color(1.0, 0.47, 0.16, 0.5), Color(1.0, 0.86, 0.62, 0.85)],
	"blood": [Color(0.95, 0.15, 0.2, 0.5), Color(1.0, 0.7, 0.6, 0.85)],
}


func _ready() -> void:
	z_index = 15
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m


func _process(delta: float) -> void:
	life += delta
	if life >= LIFE:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k := life / LIFE
	var sweep := minf(1.0, life / 0.07)
	var a0 := -PI / 2 - 0.5
	var a1 := 0.55
	var cols: Array = COLORS.get(palette, COLORS["fire"])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(face, 1))
	for i in 2:
		var c: Color = cols[i]
		c.a *= 1.0 - k
		var w := (46.0 if i == 0 else 18.0) * (1.0 - 0.5 * k) * radius / 300.0
		draw_arc(Vector2.ZERO, radius - i * 8.0, a0, a0 + (a1 - a0) * sweep, 40, c, w, true)
