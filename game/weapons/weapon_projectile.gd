class_name WeaponProjectile
extends Node3D
## Снаряд героя: стрела, брошенное копьё, щит-рикошет, духовная стрела, волна клинка.
## Движется пошагово, бьёт цели вдоль отрезка шага (Combat.along_line), упирается в стены (луч по слою мира).
## Режимы: прямой полёт, самонаведение (homing), возврат к узлу (return_to), застревание (stuck).

signal finished(proj: WeaponProjectile, reason: String)   ## "wall" / "range" / "pierce" / "returned" / "time"
signal target_hit(proj: WeaponProjectile, target: Node)

var dir := Vector3.FORWARD
var speed := 24.0
var max_dist := 18.0
var traveled := 0.0
var radius := 0.35
var hit_proto: Hit = null
var knock_force := 0.0            ## отбрасывание вдоль полёта, м/с
var pierce := 0                   ## сколько целей можно пробить после первой (-1 — бесконечно)
var homing := 0.0                 ## скорость поворота к цели, рад/с (0 — без наведения)
var home_target: Node3D = null
var return_to: Node3D = null      ## если задан — летит к этому узлу и завершает полёт рядом с ним
var stop_on_wall := true
var stick := false                ## при остановке не удаляться (воткнутое копьё)
var stuck := false
var lifetime := 6.0
var deal: Callable                ## (target, hit) — если не задан, Combat.player_hit
var hit_set := {}
var spin := 0.0                   ## вращение модели вокруг Y (щит), рад/с
var visual: Node3D = null
var hit_mult_per_target := 0.0    ## +x к урону за каждую уже пробитую цель (Аспект Наурызбая)
var _hits_done := 0
var _alive := 0.0


func _ready() -> void:
	add_to_group("player_projectile")   # враги (EnemyBase) уворачиваются перекатом от снарядов героя
	set_physics_process(true)


func launch(p_pos: Vector3, p_dir: Vector3, p_speed: float, p_hit: Hit) -> void:
	global_position = p_pos
	dir = Vector3(p_dir.x, 0, p_dir.z).normalized()
	if dir.length() < 0.1:
		dir = Vector3.FORWARD
	speed = p_speed
	hit_proto = p_hit
	_face()


func set_visual(v: Node3D) -> void:
	visual = v
	add_child(v)


func _face() -> void:
	if dir.length() > 0.01 and visual and not stuck:
		var b := Basis.looking_at(dir, Vector3.UP)
		visual.global_basis = b


func _physics_process(delta: float) -> void:
	if stuck:
		return
	_alive += delta
	if _alive > lifetime:
		_finish("time")
		return
	# наведение / возврат
	if return_to != null:
		if not is_instance_valid(return_to):
			_finish("returned")
			return
		var to := return_to.global_position + Vector3(0, 0.9, 0) - global_position
		to.y = 0.0
		if to.length() < 0.9:
			_finish("returned")
			return
		dir = to.normalized()
	elif homing > 0.0:
		if home_target == null or not is_instance_valid(home_target) or (home_target.has_method("is_dead") and home_target.is_dead()):
			home_target = Combat.nearest(get_tree(), global_position, 14.0, "hurtable_enemy", hit_set.keys())
		if home_target:
			var want := home_target.global_position - global_position
			want.y = 0.0
			if want.length() > 0.05:
				var cur := atan2(dir.x, dir.z)
				var tgt := atan2(want.x, want.z)
				var diff := wrapf(tgt - cur, -PI, PI)
				cur += clampf(diff, -homing * delta, homing * delta)
				dir = Vector3(sin(cur), 0, cos(cur))
	var step := speed * delta
	var a := global_position
	var b := a + dir * step
	# стена
	if stop_on_wall and return_to == null and is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(a, b + dir * 0.1, Combat.LAYER_WORLD)
		var res := get_world_3d().direct_space_state.intersect_ray(q)
		if not res.is_empty():
			var hp: Vector3 = res["position"]
			_hit_segment(a, hp)
			global_position = hp - dir * 0.15
			_finish("wall")
			return
	if _hit_segment(a, b):
		return
	global_position = b
	traveled += step
	if visual and spin != 0.0:
		visual.rotate_y(spin * delta)
	else:
		_face()
	if return_to == null and traveled >= max_dist:
		_finish("range")


## Возвращает true, если снаряд израсходован.
func _hit_segment(a: Vector3, b: Vector3) -> bool:
	if hit_proto == null:
		return false
	var targets := Combat.along_line(get_tree(), a, b, radius)
	targets.sort_custom(func(x, y): return a.distance_squared_to(x.global_position) < a.distance_squared_to(y.global_position))
	for t in targets:
		if hit_set.has(t) or not is_instance_valid(t):
			continue
		if t.has_method("is_dead") and t.is_dead():
			continue
		hit_set[t] = true
		var h := hit_proto.duplicate_hit()
		h.position = (t as Node3D).global_position
		h.direction = dir
		if knock_force > 0.0:
			h.knockback = dir * knock_force + Vector3(0, h.knockback.y, 0)
		if hit_mult_per_target > 0.0:
			h.amount *= 1.0 + hit_mult_per_target * float(_hits_done)
		_hits_done += 1
		if deal.is_valid():
			deal.call(t, h)
		else:
			Combat.player_hit(t, h)
		target_hit.emit(self, t)
		if not is_inside_tree() or stuck:
			return true
		if return_to == null and pierce >= 0:
			if pierce == 0:
				_finish("pierce")
				return true
			pierce -= 1
	return false


func _finish(reason: String) -> void:
	if stick and reason in ["wall", "range"]:
		stuck = true
		finished.emit(self, reason)
		return
	finished.emit(self, reason)
	queue_free()


## Снять с «застревания» и отправить к узлу (возврат копья).
func recall(to: Node3D, p_speed := 30.0) -> void:
	stuck = false
	stick = false
	return_to = to
	speed = p_speed
	hit_set.clear()
	_alive = 0.0
	lifetime = 4.0
