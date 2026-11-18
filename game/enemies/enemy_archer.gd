extends EnemyBase
## Аруақ-мерген: держит дистанцию, отходит от героя, стреляет стрелами с линией-телеграфом,
## перекатывается от стрел героя (EnemyBase._scan_projectiles). Элитный — залп из 3 стрел.

const SHOT_LEN := 16.0
const ARROW_SPEED := 19.0


func _setup() -> void:
	pref_dist = 8.5
	attack_cd_range = Vector2(1.8, 2.8)


func _try_attack(pl: Node3D, dist: float, dy: float) -> bool:
	if dist < 3.0 or dist > 15.0 or absf(dy) > 4.0:
		return false
	var a := global_position + Vector3(0, 1.0, 0)
	var b := pl.global_position + Vector3(0, 1.0, 0)
	if Combat.blocked(get_world_3d(), a, b):
		return false
	var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	begin_attack("shoot", 0.6, func(): _shoot(dir), 0.5)
	tele_line(global_position, global_position + dir * SHOT_LEN, 0.45)
	if elite:
		for s in [-0.22, 0.22]:
			var d2 := dir.rotated(Vector3.UP, s)
			tele_line(global_position, global_position + d2 * SHOT_LEN, 0.35)
	return true


func _shoot(dir: Vector3) -> void:
	fire(dir, ARROW_SPEED, "arrow")
	if elite:
		for s in [-0.22, 0.22]:
			fire(dir.rotated(Vector3.UP, s), ARROW_SPEED, "arrow")


func _custom_move(delta: float, pl: Node3D) -> bool:
	var to := pl.global_position - global_position
	to.y = 0.0
	if to.length() < 4.5 and is_on_floor():
		# отступаем от героя (вбок, если позади пропасть или стена)
		var away := -to.normalized()
		var side := Vector3(-away.z, 0, away.x) * (1.0 if int(get_instance_id()) % 2 == 0 else -1.0)
		var dir := (away + side * 0.4).normalized()
		if not _ground_ahead(dir) or test_move(global_transform, dir * 0.8):
			dir = side
		_steer(dir * move_speed * speed_mult * _slow_mult(), delta)
		return true
	return false
