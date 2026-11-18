class_name EnemyProjectile
extends Node3D
## Вражеский снаряд: стрела, шар Мглы, осколок. Группа "enemy_projectile".
## Летит прямо (или с самонаведением на героя), бьёт героя через take_hit(Hit), гаснет о стены (луч по слою мира).
## reflect(new_owner, dir) — отбит героем (вихрь меча, блок): летит обратно и бьёт врагов через Combat.player_hit.
##
## API:
##   EnemyProjectile.fire(parent, pos, dir, speed, damage, owner_node, kind := "arrow"|"orb"|"shard", homing := 0.0) -> EnemyProjectile
##   reflect(new_owner: Node, dir: Vector3)
##   var reflected: bool, var velocity: Vector3, var hit: Hit

const TEX := {
	"arrow": "res://assets/fx/arrow.png",
	"orb": "res://assets/fx/orb.png",
	"shard": "res://assets/fx/spark.png",
}

var velocity := Vector3.ZERO
var hit: Hit = null
var owner_node: Node = null
var kind := "arrow"
var homing := 0.0               ## рад/сек поворота к герою
var radius := 0.35
var life := 4.0
var reflected := false
var color := Color(1.0, 0.35, 0.3)
var _hit_player_once := false
var _sprite: Sprite3D
var _light: OmniLight3D


static func fire(parent: Node, pos: Vector3, dir: Vector3, speed: float, damage: float, p_owner: Node, p_kind := "arrow", p_homing := 0.0) -> EnemyProjectile:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	var p := EnemyProjectile.new()
	p.kind = p_kind
	p.homing = p_homing
	p.owner_node = p_owner
	var h := Hit.make(damage, p_owner, "normal")
	h.tags.append("projectile")
	h.knockback = dir.normalized() * 3.0
	p.hit = h
	p.color = Color(1.0, 0.35, 0.3) if p_kind == "arrow" else (Color(0.65, 0.35, 1.0) if p_kind == "orb" else Color(0.6, 0.9, 1.0))
	parent.add_child(p)
	p.global_position = pos
	var d := dir
	if d.length_squared() < 0.0001:
		d = Vector3(1, 0, 0)
	p.velocity = d.normalized() * speed
	return p


func _ready() -> void:
	add_to_group("enemy_projectile")
	_sprite = Sprite3D.new()
	var path: String = TEX.get(kind, TEX["orb"])
	if ResourceLoader.exists(path):
		_sprite.texture = load(path)
	if kind == "arrow":
		_sprite.axis = Vector3.AXIS_Y          ## стрела лежит в плоскости XZ и поворачивается по полёту
		_sprite.double_sided = true
	else:
		_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.shaded = false
	_sprite.pixel_size = 0.012 if kind == "arrow" else 0.01
	_sprite.modulate = color.lightened(0.3) * Color(1.6, 1.6, 1.6, 1.0)
	_sprite.render_priority = 3
	add_child(_sprite)
	if kind == "orb":
		_sprite.pixel_size = 0.008
		radius = 0.45
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 1.4
	_light.omni_range = 2.2
	add_child(_light)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		_die(false)
		return
	var pl := _player()
	if homing > 0.0 and not reflected and pl:
		var want := (pl.global_position + Vector3(0, 1.0, 0)) - global_position
		want.y *= 0.3
		var cur := velocity
		var spd := cur.length()
		var nv := cur.normalized().slerp(want.normalized(), clampf(homing * delta, 0.0, 1.0))
		velocity = nv * spd
	var from := global_position
	var to := from + velocity * delta
	# стены
	var q := PhysicsRayQueryParameters3D.create(from, to, Combat.LAYER_WORLD)
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if not res.is_empty():
		var col = res.get("collider")
		if reflected and col is Node and (col as Node).is_in_group("destructible") and col.has_method("take_hit"):
			Combat.player_hit(col, _reflected_hit(col))
		global_position = res["position"]
		_die(true)
		return
	global_position = to
	if kind == "arrow" and velocity.length_squared() > 0.01:
		_sprite.rotation = Vector3(0, atan2(-velocity.z, velocity.x), 0)
	if reflected:
		for e in get_tree().get_nodes_in_group("hurtable_enemy"):
			if not (e is Node3D) or not is_instance_valid(e) or e == owner_node:
				continue
			if e.has_method("is_dead") and e.is_dead():
				continue
			var ep: Vector3 = (e as Node3D).global_position
			var r: float = radius + float(e.get("hit_radius") if e.get("hit_radius") != null else 0.5)
			if Vector2(ep.x - global_position.x, ep.z - global_position.z).length() <= r and global_position.y > ep.y - 0.5 and global_position.y < ep.y + 3.0:
				Combat.player_hit(e, _reflected_hit(e))
				_die(true)
				return
	elif pl and not _hit_player_once:
		var pp := pl.global_position
		var pr: float = radius + float(pl.get("hit_radius") if pl.get("hit_radius") != null else 0.45)
		if Vector2(pp.x - global_position.x, pp.z - global_position.z).length() <= pr and global_position.y > pp.y - 0.4 and global_position.y < pp.y + 2.2:
			var inv: bool = pl.has_method("invulnerable") and pl.invulnerable()
			hit.position = global_position
			hit.direction = Vector3(velocity.x, 0, velocity.z).normalized()
			if pl.has_method("take_hit"):
				pl.take_hit(hit)
			if inv:
				_hit_player_once = true   ## рывок сквозь снаряд — летит дальше
			else:
				_die(true)


func _reflected_hit(target: Node) -> Hit:
	var h := Hit.make(hit.amount * 2.0, owner_node if is_instance_valid(owner_node) else null, "special")
	h.tags = ["projectile", "reflected"]
	h.position = global_position
	h.direction = Vector3(velocity.x, 0, velocity.z).normalized()
	h.knockback = h.direction * 5.0
	h.armor_mult = 1.5
	return h


func _player() -> Node3D:
	var p := get_tree().get_first_node_in_group("player")
	return p as Node3D


## Отбить снаряд: теперь он принадлежит герою и бьёт врагов.
func reflect(new_owner: Node, dir: Vector3) -> void:
	if reflected:
		return
	reflected = true
	owner_node = new_owner
	homing = 0.0
	life = 3.0
	var d := Vector3(dir.x, 0, dir.z)
	if d.length_squared() < 0.0001:
		d = -velocity
	velocity = d.normalized() * maxf(velocity.length() * 1.3, 14.0)
	color = Color(1.0, 0.9, 0.5)
	if _sprite:
		_sprite.modulate = Color(2.0, 1.8, 1.0)
	if _light:
		_light.light_color = color
	remove_from_group("enemy_projectile")
	add_to_group("player_projectile")


func _die(impact: bool) -> void:
	if is_queued_for_deletion():
		return
	if impact and get_parent():
		Fx3D.burst(get_parent(), global_position, color, 6, 3.0, 0.12)
	queue_free()
