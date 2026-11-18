extends BossBase
## Жезтырнақ (босс биома 0): когти (комбо конусами), прыжок-обрушение на героя (круг), призыв волков,
## перепрыгивает ярусы. 2-я фаза: тройной прыжок, комбо из трёх ударов, призыв чаще.

const CLAW_R := 3.6
const CLAW_ANGLE := 110.0
const LEAP_R := 2.7

var _summon_cd := 8.0


func _setup() -> void:
	pref_dist = 2.6
	attack_cd_range = Vector2(0.9, 1.6)


func _timers(delta: float) -> void:
	super._timers(delta)
	_summon_cd -= delta


func _try_attack(pl: Node3D, dist: float, dy: float) -> bool:
	if not is_on_floor():
		return false
	if _summon_cd <= 0.0 and alive_minions() < (2 if phase == 1 else 3):
		_summon_cd = 14.0 if phase == 1 else 10.0
		var spots: Array = [find_floor_near(global_position, 3.0), find_floor_near(global_position, 3.0)]
		begin_attack("summon", 0.9, func(): _summon(spots), 0.8, "summon")
		for s in spots:
			tele_circle(s, 1.0, -1.0, Color(0.6, 0.25, 1.0))
		return true
	if dist < CLAW_R + 0.4 and absf(dy) < 1.2:
		_claw(1)
		return true
	if dist < 14.0:
		_leap(3 if phase == 2 else 1)
		return true
	return false


func _claw(n: int) -> void:
	var dir := facing
	var origin := global_position
	var p := player()
	if p:
		var d := p.global_position - global_position
		d.y = 0.0
		if d.length_squared() > 0.01:
			dir = d.normalized()
	facing = dir
	var last := n >= (3 if phase == 2 else 2)
	begin_attack("claw%d" % n, 0.5 if n == 1 else 0.4, func(): _claw_strike(origin, dir, n, last), 0.7 if last else 0.05)
	tele_cone(dir, CLAW_R, CLAW_ANGLE)


func _claw_strike(origin: Vector3, dir: Vector3, n: int, last: bool) -> void:
	Sfx.play("swing_heavy", -2.0)
	velocity = dir * 6.0
	Fx3D.slash_arc(fx_parent(), origin + Vector3(0, 1.2, 0), dir, CLAW_R, CLAW_ANGLE, Color(1.0, 0.5, 0.4), 0.18, 1.2)
	strike_cone(origin, dir, CLAW_R, CLAW_ANGLE, damage, {"knock": 6.0})
	if not last:
		_claw(n + 1)


func _leap(left: int) -> void:
	var p := player()
	if p == null:
		return
	var target := p.global_position
	begin_attack("leap", 0.6 if left == 3 or phase == 1 else 0.45, func(): jump_to(target, 0.65, func(): _land(target, left - 1)), 0.8, "leap")
	tele_circle(target, LEAP_R)


func _land(c: Vector3, left: int) -> void:
	Sfx.play("slam")
	Bus.shake.emit(0.7, 0.3)
	Fx3D.ring(fx_parent(), global_position, LEAP_R, Color(1.0, 0.4, 0.3), 0.3)
	Fx3D.puff(fx_parent(), global_position, Color(0.75, 0.68, 0.55, 0.8), 10)
	strike_circle(Vector3(c.x, global_position.y, c.z), LEAP_R, damage * 1.3, {"knock": 8.0, "knock_up": 4.0})
	if left > 0:
		_leap(left)
	elif not _atk.is_empty():
		_atk["phase"] = "recover"
		_atk["t"] = 0.0


func _summon(spots: Array) -> void:
	Sfx.play("summon")
	for s in spots:
		var m := summon("wolf" if _rng.randf() < 0.7 else "spirit", s, {"spawn_delay": 0.4})
		if m:
			minions.append(m)
