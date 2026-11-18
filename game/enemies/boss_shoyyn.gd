extends BossBase
## Шойынқұлақ (босс биома 1): чугунный великан с бронёй (восстанавливается через 9 с после разрушения).
## smash — удар перед собой (круг), stomp — топот с ударной волной (перепрыгнуть), sweep — широкий взмах
## (tag "wide" — подкатом), roar — рёв отбрасывает героя; во 2-й фазе рёв призывает балбалов.

const SMASH_R := 2.5
const SWEEP_R := 4.4
const SWEEP_ANGLE := 220.0

var _roar_cd := 10.0


func _setup() -> void:
	pref_dist = 2.8
	attack_cd_range = Vector2(1.1, 1.8)
	armor_regen = 9.0


func _timers(delta: float) -> void:
	super._timers(delta)
	_roar_cd -= delta


func _enter_phase(n: int) -> void:
	super._enter_phase(n)
	_roar_cd = 0.0


func _try_attack(pl: Node3D, dist: float, dy: float) -> bool:
	var dir := facing
	if _roar_cd <= 0.0:
		_roar_cd = 16.0
		begin_attack("roar", 0.8, func(): _roar(), 1.0, "roar")
		tele_circle(global_position, 4.5)
		return true
	if absf(dy) > 2.0:
		return false
	if dist < SWEEP_R and _rng.randf() < 0.45:
		var origin := global_position
		begin_attack("sweep", 0.75, func(): _sweep(origin, dir), 0.9, "sweep")
		tele_cone(dir, SWEEP_R, SWEEP_ANGLE)
		return true
	if dist < 4.5 and _rng.randf() < 0.6:
		var c := global_position + dir * 2.3
		begin_attack("smash", 0.75, func(): _smash(c), 0.9, "smash")
		tele_circle(c, SMASH_R)
		return true
	if dist < 12.0:
		var c2 := global_position
		begin_attack("stomp", 0.85, func(): _stomp(c2), 1.1, "stomp")
		tele_circle(c2, 3.0)
		tele_ring(c2, 3.0, 11.0, -1.0, Color(1.0, 0.5, 0.15))
		return true
	return false


func _sweep(origin: Vector3, dir: Vector3) -> void:
	Sfx.play("swing_heavy")
	Fx3D.slash_arc(fx_parent(), origin + Vector3(0, 1.0, 0), dir, SWEEP_R, SWEEP_ANGLE, Color(1.0, 0.75, 0.5), 0.22, 1.2)
	strike_cone(origin, dir, SWEEP_R, SWEEP_ANGLE, damage, {"tags": ["wide"], "knock": 9.0})


func _smash(c: Vector3) -> void:
	Sfx.play("slam")
	Bus.shake.emit(0.9, 0.35)
	Fx3D.puff(fx_parent(), c, Color(0.7, 0.62, 0.5, 0.9), 12)
	Fx3D.burst(fx_parent(), c + Vector3(0, 0.3, 0), Color(1.0, 0.6, 0.3), 14, 6.0)
	strike_circle(c, SMASH_R, damage * 1.4, {"knock": 9.0, "knock_up": 5.0})


func _stomp(c: Vector3) -> void:
	Sfx.play("slam")
	Bus.shake.emit(1.0, 0.4)
	strike_circle(c, 3.0, damage, {"knock": 8.0})
	shockwave(c, 11.0, 9.0, damage * 0.8, Color(1.0, 0.5, 0.15))
	if phase == 2:
		get_tree().create_timer(0.45, false, true).timeout.connect(func():
			if is_instance_valid(self) and not _dead:
				shockwave(c, 11.0, 9.0, damage * 0.8, Color(1.0, 0.35, 0.15)))


func _roar() -> void:
	Sfx.play("boss_roar")
	Bus.shake.emit(0.8, 0.6)
	Fx3D.ring(fx_parent(), global_position, 4.5, Color(1.0, 0.85, 0.6), 0.5, 0.4)
	strike_circle(global_position, 4.5, 6.0, {"knock": 14.0, "knock_up": 3.0})
	if phase == 2 and alive_minions() < 2:
		for i in 2:
			var m := summon("balbal", find_floor_near(global_position, 5.0), {"spawn_delay": 0.6})
			if m:
				minions.append(m)
