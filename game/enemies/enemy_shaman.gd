extends EnemyBase
## Бақсы Мглы: держится поодаль, выпускает самонаводящиеся шары Мглы, телепортируется, если герой
## подошёл близко, и призывает обезумевших духов (не больше 3 своих одновременно).

const MAX_MINIONS := 3

var _summon_cd := 4.0
var _tp_cd := 0.0
var _minions: Array = []


func _setup() -> void:
	pref_dist = 7.0
	attack_cd_range = Vector2(2.2, 3.2)


func _timers(delta: float) -> void:
	super._timers(delta)
	_summon_cd -= delta
	_tp_cd -= delta


func _try_attack(pl: Node3D, dist: float, _dy: float) -> bool:
	if dist < 3.2 and _tp_cd <= 0.0:
		_tp_cd = 4.0
		var dest := find_floor_near(pl.global_position, 8.0)
		begin_attack("teleport", 0.45, func(): mist_teleport(dest), 0.4, "teleport")
		tele_circle(dest, 1.0, -1.0, Color(0.6, 0.25, 1.0))
		return true
	_minions = _minions.filter(func(m): return is_instance_valid(m) and not m.is_dead())
	if _summon_cd <= 0.0 and _minions.size() < MAX_MINIONS:
		_summon_cd = 11.0
		var spots: Array = []
		for i in (2 if not elite else 3):
			spots.append(find_floor_near(global_position, 2.5))
		begin_attack("summon", 0.9, func(): _summon(spots), 0.6)
		for s in spots:
			tele_circle(s, 0.9, -1.0, Color(0.6, 0.25, 1.0))
		return true
	if dist < 13.0:
		var dir := pl.global_position - global_position
		dir.y = 0.0
		dir = dir.normalized()
		begin_attack("orbs", 0.65, func(): _orbs(dir), 0.6)
		tele_circle(global_position, 1.2, -1.0, Color(0.7, 0.25, 1.0))
		return true
	return false


func _orbs(dir: Vector3) -> void:
	var n := 3 if not elite else 5
	for i in n:
		var a := (float(i) - (n - 1) * 0.5) * 0.35
		fire(dir.rotated(Vector3.UP, a), 6.5, "orb", 1.4, damage * 0.8)
	Fx3D.flash_light(fx_parent(), global_position + Vector3(0, 1.4, 0), Color(0.6, 0.3, 1.0), 3.0, 4.0, 0.25)


func _summon(spots: Array) -> void:
	Sfx.play("summon")
	for s in spots:
		var m := summon("spirit", s, {"spawn_delay": 0.3, "hp_mult": float(mods.get("hp_mult", 1.0)) * 0.6})
		if m:
			_minions.append(m)
