extends Node2D
## Ветровой барьер: запирает край арены, пока идут волны. Невидим и не мешает, когда выключен.

const SHADER := preload("res://shaders/wind_wall.gdshader")

var active := false
var wall: StaticBody2D
var shape: CollisionShape2D
var rect: ColorRect
var mat: ShaderMaterial
var dust: CPUParticles2D


func _ready() -> void:
	wall = StaticBody2D.new()
	wall.collision_layer = 1
	shape = CollisionShape2D.new()
	var s := RectangleShape2D.new()
	s.size = Vector2(40, 800)
	shape.shape = s
	shape.position = Vector2(0, -300)
	shape.disabled = true
	wall.add_child(shape)
	add_child(wall)
	rect = ColorRect.new()
	rect.size = Vector2(150, 700)
	rect.position = Vector2(-75, -640)
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("intensity", 0.0)
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	dust = CPUParticles2D.new()
	dust.texture = preload("res://assets/fx/puff.png")
	dust.amount = 26
	dust.lifetime = 1.4
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(40, 8)
	dust.direction = Vector2(0, -1)
	dust.spread = 18.0
	dust.gravity = Vector2(0, -80)
	dust.initial_velocity_min = 160.0
	dust.initial_velocity_max = 320.0
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.3
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.95, 0.85, 0.55))
	g.set_color(1, Color(1, 0.95, 0.85, 0.0))
	dust.color_ramp = g
	dust.emitting = false
	add_child(dust)


func set_active(on: bool) -> void:
	active = on
	shape.set_deferred("disabled", not on)
	dust.emitting = on
	var tw := create_tween()
	tw.tween_method(func(v: float): mat.set_shader_parameter("intensity", v),
		1.0 if not on else 0.0, 1.0 if on else 0.0, 0.6)
	if on:
		Sfx.play("wind_wall")
