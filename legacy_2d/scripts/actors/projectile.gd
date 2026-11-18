extends Node2D
## Снаряды врагов:
##  arrow — стрела аруака, летит прямо; orb — шар бақсы, медленно доворачивает на героя;
##  shockwave — ударная волна Шойынқұлақа по земле, её не заблокировать — только кувырок.
## Идеально заблокированные стрела и шар летят обратно и ранят врагов.

const FX := preload("res://scripts/fx/effects.gd")

var kind := "arrow"
var dir := 1
var speed := 900.0
var dmg := 10.0
var owner_enemy: Node
var ground_y := 0.0
var vel := Vector2.ZERO
var life := 0.0
var reflected := false
var done_hero := false
var spr: Sprite2D
var trail: CPUParticles2D

const LIFE := {"arrow": 2.2, "orb": 4.5, "shockwave": 1.5}


func setup(p_kind: String, pos: Vector2, p_dir: int, p_speed: float, p_dmg: float, p_owner: Node, p_ground: float) -> void:
	kind = p_kind
	position = pos
	dir = p_dir
	speed = p_speed
	dmg = p_dmg
	owner_enemy = p_owner
	ground_y = p_ground
	vel = Vector2(dir * speed, 0)


func _ready() -> void:
	add_to_group("projectiles")
	z_index = 12
	spr = Sprite2D.new()
	add_child(spr)
	match kind:
		"arrow":
			spr.texture = preload("res://assets/fx/arrow.png")
			spr.flip_h = dir < 0
		"orb":
			spr.texture = preload("res://assets/fx/orb.png")
			spr.material = FX.additive()
			trail = _trail(Color(0.75, 0.35, 1.0, 0.8))
		"shockwave":
			spr.texture = preload("res://assets/fx/shockwave.png")
			spr.material = FX.additive()
			spr.offset = Vector2(0, -40)
			spr.flip_h = dir < 0
			spr.scale = Vector2(1.2, 1.3)


func _trail(c: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = preload("res://assets/fx/soft.png")
	p.material = FX.additive()
	p.amount = 16
	p.lifetime = 0.4
	p.gravity = Vector2.ZERO
	p.initial_velocity_max = 10.0
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.3
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, Color(c.r, c.g, c.b, 0))
	p.color_ramp = g
	p.local_coords = false
	add_child(p)
	return p


func _physics_process(delta: float) -> void:
	life += delta
	if life > LIFE.get(kind, 2.0):
		_vanish()
		return
	var hero := get_tree().get_first_node_in_group("player")
	if kind == "orb" and not reflected and hero:
		# медленно доворачивает на героя
		var to: Vector2 = (hero.global_position + Vector2(0, -130)) - global_position
		vel = vel.rotated(clampf(vel.angle_to(to), -1.8 * delta, 1.8 * delta))
	if kind == "shockwave":
		spr.scale.y = 1.3 + sin(life * 30.0) * 0.08
		if int(life * 20.0) % 2 == 0:
			FX.dust(get_parent(), Vector2(global_position.x, ground_y), 1, 0.6)
	global_position += vel * delta
	spr.rotation = vel.angle() if kind == "arrow" and dir > 0 else (vel.angle() - PI if kind == "arrow" else 0.0)
	if reflected:
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.is_alive() and absf(e.global_position.x - global_position.x) < 50.0 + e.radius * 0.3:
				e.take_hit(dmg * 2.0, int(signf(vel.x)), 300.0, false)
				FX.sparks(get_parent(), global_position, int(signf(vel.x)), 12, Color(0.5, 1.0, 0.92))
				_vanish()
				return
		return
	if hero == null or done_hero:
		return
	var hx: float = hero.global_position.x
	var hit := absf(hx - global_position.x) < (55.0 if kind == "shockwave" else 32.0)
	if kind != "shockwave":
		hit = hit and absf((hero.global_position.y - 120.0) - global_position.y) < 130.0
	if not hit:
		return
	var res: String = hero.receive_attack({"dmg": dmg, "knock": 320.0, "from_x": global_position.x - signf(vel.x) * 10.0,
		"parry": kind != "shockwave", "block": kind != "shockwave", "source": null})
	match res:
		"parried":
			reflected = true
			vel = -vel * 1.25
			if kind == "arrow":
				spr.modulate = Color(0.5, 1.0, 0.92)
			Sfx.play("parry")
		"blocked", "hit":
			FX.sparks(get_parent(), global_position, -int(signf(vel.x)), 8)
			if kind == "shockwave":
				done_hero = true
			else:
				_vanish()
		"dodged":
			done_hero = true


func _vanish() -> void:
	set_physics_process(false)
	if trail:
		trail.emitting = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(queue_free)
