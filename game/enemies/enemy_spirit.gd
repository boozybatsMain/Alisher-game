extends EnemyBase
## Обезумевший дух: летает над землёй (через пропасти), кружит вокруг героя и бросается тараном по линии.

const RAM_LEN := 9.0
const RAM_SPEED := 17.0


func _setup() -> void:
	pref_dist = 4.5
	attack_cd_range = Vector2(2.0, 3.2)


func _activate() -> void:
	super._activate()
	velocity.y = 2.0


func _try_attack(pl: Node3D, dist: float, _dy: float) -> bool:
	if dist > 8.0 or dist < 1.5:
		return false
	var dir := pl.global_position - global_position
	dir.y = 0.0
	dir = dir.normalized()
	var a := Vector3(global_position.x, pl.global_position.y, global_position.z)
	var ty := pl.global_position.y
	begin_attack("ram", 0.6, func(): _ram(dir, ty), 0.7)
	tele_line(a, a + dir * RAM_LEN, 1.2)
	return true


func _ram(dir: Vector3, target_y: float) -> void:
	var d := dir
	d.y = clampf((target_y + 0.6 - global_position.y) / RAM_LEN, -0.3, 0.3)
	dash(d, RAM_SPEED, RAM_LEN / RAM_SPEED, damage, {"knock": 6.0, "max_dy": 3.0})
	Fx3D.burst(fx_parent(), global_position + Vector3(0, 1.0, 0), Color(0.6, 0.85, 1.0), 8, 3.0)


func _custom_move(delta: float, pl: Node3D) -> bool:
	# кружение: угол фланга медленно вращается — дух «плавает» вокруг героя
	_flank = wrapf(_flank + delta * 0.6, 0.0, TAU)
	var bob := sin(Time.get_ticks_msec() * 0.003 + float(get_instance_id() % 100)) * 0.4
	var pp := pl.global_position
	var goal := pp + Vector3(cos(_flank), 0, sin(_flank)) * pref_dist
	var d := goal - global_position
	d.y = 0.0
	var v := d.normalized() * move_speed * speed_mult * _slow_mult() if d.length() > 0.3 else Vector3.ZERO
	v += _separation() * 2.0
	_steer(v, delta, 10.0)
	var ty := pp.y + 1.3 + bob
	velocity.y = move_toward(velocity.y, clampf((ty - global_position.y) * 2.5, -5.0, 5.0), 10.0 * delta)
	return true
