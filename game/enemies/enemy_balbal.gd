extends EnemyBase
## Балбал-страж: медленный, бронированный каменный идол. Широкий горизонтальный удар (tag "wide" — можно
## проехать подкатом) и удар по земле с ударной волной (tag "ground" — перепрыгнуть).

const SWEEP_R := 3.3
const SWEEP_ANGLE := 200.0


func _setup() -> void:
	pref_dist = 1.9
	attack_cd_range = Vector2(1.8, 2.8)
	knock_resist = 0.6


func _try_attack(pl: Node3D, dist: float, dy: float) -> bool:
	if absf(dy) > 1.2:
		return false
	var dir := facing
	if dist < SWEEP_R + 0.3 and _rng.randf() < 0.6:
		var origin := global_position
		begin_attack("sweep", 0.7, func(): _sweep(origin, dir), 0.8)
		tele_cone(dir, SWEEP_R, SWEEP_ANGLE)
		return true
	if dist < 5.5:
		var c := global_position + dir * 1.6
		begin_attack("slam", 0.75, func(): _slam(c), 1.0)
		tele_circle(c, 1.7)
		tele_ring(c, 1.7, 6.5, -1.0, Color(1.0, 0.45, 0.15))
		return true
	return false


func _sweep(origin: Vector3, dir: Vector3) -> void:
	Sfx.play("swing_heavy", -2.0)
	Fx3D.slash_arc(fx_parent(), origin + Vector3(0, 0.8, 0), dir, SWEEP_R, SWEEP_ANGLE, Color(0.9, 0.8, 0.6), 0.2, 0.9)
	strike_cone(origin, dir, SWEEP_R, SWEEP_ANGLE, damage, {"tags": ["wide"], "knock": 7.0})


func _slam(c: Vector3) -> void:
	Sfx.play("slam")
	Bus.shake.emit(0.6, 0.25)
	Fx3D.puff(fx_parent(), c, Color(0.75, 0.68, 0.55, 0.9), 10)
	strike_circle(c, 1.7, damage * 1.2, {"knock": 6.0, "knock_up": 4.0})
	shockwave(c, 6.5, 8.0, damage * 0.6, Color(1.0, 0.55, 0.2))
