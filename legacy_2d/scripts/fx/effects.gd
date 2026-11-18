extends RefCounted
## Разовые эффекты боя: пыль, искры, каменная крошка, молния, огненный след, дуга удара.

const PUFF := preload("res://assets/fx/puff.png")
const SOFT := preload("res://assets/fx/soft.png")
const SPARK := preload("res://assets/fx/spark.png")
const CHIP := preload("res://assets/fx/chip.png")
const SMEAR := preload("res://scripts/fx/smear.gd")
const FIRE_PATCH := preload("res://scripts/fx/fire_patch.gd")

static var _add: CanvasItemMaterial


static func additive() -> CanvasItemMaterial:
	if _add == null:
		_add = CanvasItemMaterial.new()
		_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add


static func _burst(parent: Node, pos: Vector2, amount: int, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.position = pos
	p.z_index = 20
	parent.add_child(p)
	p.emitting = true
	parent.get_tree().create_timer(life + 0.3, false).timeout.connect(p.queue_free)
	return p


static func _ramp(c0: Color, c1: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	return g


static func _curve(a: float, b: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, a))
	c.add_point(Vector2(1.0, b))
	return c


static func dust(parent: Node, pos: Vector2, amount := 6, spread := 1.0, wind := 0.0) -> void:
	var p := _burst(parent, pos + Vector2(0, -4), amount, 0.8)
	p.texture = PUFF
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(16 * spread, 3)
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.initial_velocity_min = 30.0 * spread
	p.initial_velocity_max = 110.0 * spread
	p.gravity = Vector2(-wind * 160.0, -20)
	p.damping_min = 60.0
	p.damping_max = 120.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 0.9
	p.scale_amount_curve = _curve(0.5, 1.6)
	p.color_ramp = _ramp(Color(1, 1, 1, 0.75), Color(1, 1, 1, 0))
	p.z_index = 5


static func sparks(parent: Node, pos: Vector2, dir: int, amount := 10, color := Color(1, 0.92, 0.75)) -> void:
	var p := _burst(parent, pos, amount, 0.35)
	p.texture = SPARK
	p.material = additive()
	p.direction = Vector2(dir, -0.3)
	p.spread = 50.0
	p.initial_velocity_min = 380.0
	p.initial_velocity_max = 900.0
	p.gravity = Vector2(0, 1400)
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	p.color_ramp = _ramp(color, Color(color.r, color.g, color.b, 0))


static func chips(parent: Node, pos: Vector2, amount := 6) -> void:
	var p := _burst(parent, pos, amount, 1.2)
	p.texture = CHIP
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(30, 40)
	p.direction = Vector2(0, -1)
	p.spread = 60.0
	p.initial_velocity_min = 220.0
	p.initial_velocity_max = 520.0
	p.gravity = Vector2(0, 1500)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.1
	p.color_ramp = _ramp(Color(1, 1, 1, 1), Color(1, 1, 1, 0))


static func glow_burst(parent: Node, pos: Vector2, color: Color, size := 1.0) -> void:
	var p := _burst(parent, pos, 1, 0.35)
	p.texture = SOFT
	p.material = additive()
	p.initial_velocity_max = 0.0
	p.scale_amount_min = 2.5 * size
	p.scale_amount_max = 2.5 * size
	p.scale_amount_curve = _curve(0.5, 1.4)
	p.color_ramp = _ramp(color, Color(color.r, color.g, color.b, 0))


static func lightning(parent: Node, from: Vector2, to: Vector2) -> void:
	## Ломаная молния Тенгри.
	var line := Line2D.new()
	line.width = 5.0
	line.default_color = Color(0.75, 0.9, 1.0)
	line.material = additive()
	line.z_index = 30
	var n := 9
	for i in n + 1:
		var t := float(i) / n
		var p := from.lerp(to, t)
		if i > 0 and i < n:
			p += Vector2(randf_range(-14, 14), randf_range(-22, 22))
		line.add_point(p)
	parent.add_child(line)
	var core := line.duplicate() as Line2D
	core.width = 2.0
	core.default_color = Color(1, 1, 1)
	parent.add_child(core)
	glow_burst(parent, to, Color(0.6, 0.85, 1.0, 0.9), 0.8)
	for l in [line, core]:
		var tw: Tween = l.create_tween()
		tw.tween_property(l, "modulate:a", 0.0, 0.25)
		tw.tween_callback(l.queue_free)


static func fire_patch(parent: Node, pos: Vector2, dps: float, owner_hero: Node) -> void:
	var f := FIRE_PATCH.new()
	f.position = pos
	f.dps = dps
	f.hero = owner_hero
	parent.add_child(f)


static func smear(parent: Node, pos: Vector2, face: int, radius: float, color: String) -> void:
	var s := SMEAR.new()
	s.position = pos
	s.face = face
	s.radius = radius
	s.palette = color
	parent.add_child(s)


static func float_text(parent: Node, pos: Vector2, text: String, color := Color.WHITE, size := 30) -> void:
	Fx.float_text(parent, pos, text, color, size)
