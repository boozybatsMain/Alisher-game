extends EnemyBase
## Ловкач Мглы: отскакивает от стен, перепрыгивает через героя (Vault) и бьёт в спину,
## прыгает сверху с телеграфом-кругом. Перекаты от стрел — из базового класса (agile).

const DROP_R := 1.9
const SLASH_R := 2.8


func _setup() -> void:
	pref_dist = 3.8
	attack_cd_range = Vector2(1.3, 2.1)


func _try_attack(pl: Node3D, dist: float, dy: float) -> bool:
	if not is_on_floor() or dist > 9.0:
		return false
	var pp := pl.global_position
	var wall_n := _near_wall()
	if wall_n != Vector3.ZERO and dist > 2.5 and _rng.randf() < 0.6:
		# отскок от стены → удар сверху
		var wall_pt := global_position - wall_n * 0.6 + Vector3(0, 2.2, 0)
		var target := pp
		begin_attack("wall_drop", 0.45, func(): _wall_drop(wall_pt, target), 0.6, "leap")
		tele_circle(target, DROP_R)
		return true
	if dist < 4.0 and absf(dy) < 1.0 and _rng.randf() < 0.5:
		# прыжок через героя и удар в спину
		var over := pp - global_position
		over.y = 0.0
		var land := pp + over.normalized() * 2.0
		if _ground_ahead_at(land):
			begin_attack("vault", 0.4, func(): _vault(land, pp), 0.55, "leap")
			tele_circle(land, 1.0, -1.0, Color(1.0, 0.45, 0.2))
			return true
	if dist < 8.0:
		var target2 := pp
		begin_attack("drop", 0.55, func(): jump_to(target2, 0.6, func(): _land_strike(target2)), 0.7, "leap")
		tele_circle(target2, DROP_R)
		return true
	return false


func _wall_drop(wall_pt: Vector3, target: Vector3) -> void:
	jump_to(wall_pt, 0.3, Callable())
	_jumping = true
	# через 0.3 с — отскок от стены вниз к цели (усиленный удар сверху)
	get_tree().create_timer(0.3, false, true).timeout.connect(func():
		if is_instance_valid(self) and not _dead and not is_stunned() and _launch_t <= 0.0 and _knock_t <= 0.0:
			Fx3D.puff(fx_parent(), global_position + Vector3(0, 0.5, 0), Color(0.8, 0.75, 0.65, 0.7), 4)
			Sfx.play("roll", -8.0)
			jump_to(target, 0.45, func(): _land_strike(target)))


func _vault(land: Vector3, over_pos: Vector3) -> void:
	var land_cb := func():
		var back := over_pos - global_position
		back.y = 0.0
		facing = back.normalized()
		chain_attack("back_slash", 0.4, func(): _slash(global_position, facing), 0.6)
		tele_cone(facing, SLASH_R, 110.0)
	jump_to(land, 0.55, land_cb)
	velocity.y += 3.0


func _slash(origin: Vector3, dir: Vector3) -> void:
	Sfx.play("swing_enemy", -3.0)
	Fx3D.slash_arc(fx_parent(), origin + Vector3(0, 0.9, 0), dir, SLASH_R, 110.0, Color(0.6, 0.85, 1.0), 0.15)
	strike_cone(origin, dir, SLASH_R, 110.0, damage, {"knock": 5.0})


func _land_strike(c: Vector3) -> void:
	Sfx.play("slam", -4.0)
	Bus.shake.emit(0.3, 0.15)
	Fx3D.ring(fx_parent(), global_position, DROP_R, Color(0.6, 0.85, 1.0), 0.25)
	strike_circle(Vector3(c.x, global_position.y, c.z), DROP_R, damage * 1.2, {"knock": 6.0})
	if not _atk.is_empty():
		_atk["phase"] = "recover"
		_atk["t"] = 0.0


func _near_wall() -> Vector3:
	var space := get_world_3d().direct_space_state
	for i in 8:
		var a := i * TAU / 8.0
		var d := Vector3(cos(a), 0, sin(a))
		var from := global_position + Vector3(0, 1.0, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + d * 3.0, Combat.LAYER_WORLD)
		var r := space.intersect_ray(q)
		if not r.is_empty():
			var n: Vector3 = r["normal"]
			if absf(n.y) < 0.3:
				return Vector3(n.x, 0, n.z).normalized()
	return Vector3.ZERO


func _ground_ahead_at(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, -2.0, 0), Combat.LAYER_WORLD)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
