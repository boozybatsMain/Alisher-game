extends Node2D
## Горящий след Огненного кувырка (Дар От-Аны): пламя на земле поджигает врагов, через 2 с гаснет.

var dps := 10.0
var hero: Node
var life := 0.0
var tick := 0.0

const LIFE := 2.0


func _ready() -> void:
	z_index = 4
	var p := CPUParticles2D.new()
	p.texture = preload("res://assets/fx/soft.png")
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = m
	p.amount = 10
	p.lifetime = 0.6
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(24, 4)
	p.direction = Vector2(0, -1)
	p.spread = 15.0
	p.gravity = Vector2(0, -160)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 80.0
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.5
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.75, 0.3, 0.9))
	g.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	p.color_ramp = g
	add_child(p)


func _process(delta: float) -> void:
	life += delta
	tick -= delta
	if tick <= 0.0:
		tick = 0.25
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.is_alive() and absf(e.global_position.x - global_position.x) < 50.0:
				e.apply_burn(dps, 2.0)
	if life > LIFE:
		modulate.a -= delta * 3.0
		if modulate.a <= 0.0:
			queue_free()
