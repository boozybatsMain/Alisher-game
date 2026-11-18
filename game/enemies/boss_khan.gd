extends BossBase
## Первый хан рода — Тень бессмертия (финальный босс, биом 2). Спрайт батыра, тёмный и крупный.
## Фаза 1: комбо из трёх ударов (конусы), рывок-выпад по линии, круги Мглы вокруг героя.
## Фаза 2 (≤50% HP): волны Мглы по земле, залп самонаводящихся шаров, призыв стражей-балбалов,
##   телепорт за спину перед комбо. Броня восстанавливается через 10 с. Все атаки с телеграфом.

const MIST := Color(0.65, 0.2, 1.0)
const SLASH_R := 3.8
const SLASH_ANGLE := 120.0

var _special_cd := 4.0
var _summon_cd := 6.0
var _mist_aura: OmniLight3D


func _setup() -> void:
	pref_dist = 3.0
	attack_cd_range = Vector2(0.9, 1.5)
	armor_regen = 10.0
	_mist_aura = OmniLight3D.new()
	_mist_aura.light_color = MIST
	_mist_aura.light_energy = 1.2
	_mist_aura.omni_range = 5.0
	_mist_aura.position.y = 1.6
	add_child(_mist_aura)


func _timers(delta: float) -> void:
	super._timers(delta)
	_special_cd -= delta
	_summon_cd -= delta


func _enter_phase(n: int) -> void:
	super._enter_phase(n)
	_base_tint = Color(0.3, 0.16, 0.42)
	_mist_aura.light_energy = 2.6
	_special_cd = 0.0


func _try_attack(pl: Node3D, dist: float, dy: float) -> bool:
	var pp := pl.global_position
	if phase == 2 and _summon_cd <= 0.0 and alive_minions() < 2:
		_summon_cd = 18.0
		var spots: Array = [find_floor_near(global_position, 4.0), find_floor_near(global_position, 4.0)]
		begin_attack("guards", 1.0, func(): _guards(spots), 0.8, "block")
		for s in spots:
			tele_circle(s, 1.2, -1.0, MIST)
		return true
	if _special_cd <= 0.0:
		_special_cd = _rng.randf_range(5.0, 7.0) * (0.75 if phase == 2 else 1.0)
		var r := _rng.randf()
		if phase == 2 and r < 0.35:
			_mist_waves()
		elif phase == 2 and r < 0.65:
			_orb_volley()
		else:
			_mist_circles(pp)
		return true
	if absf(dy) > 2.0:
		return false
	if dist < SLASH_R + 0.4:
		_combo(1)
		return true
	if dist < 11.0:
		if phase == 2 and _rng.randf() < 0.4:
			# телепорт за спину и комбо
			var pf: Vector3 = pl.get_facing() if pl.has_method("get_facing") else Vector3.FORWARD
			var behind := find_floor_near(pp - pf * 2.2, 0.01)
			begin_attack("blink", 0.45, func():
				mist_teleport(behind)
				_combo(1), 0.1, "roll")
			tele_circle(behind, 1.0, -1.0, MIST)
			return true
		_lunge(pp)
		return true
	return false


func _combo(n: int) -> void:
	var p := player()
	var dir := facing
	if p:
		var d := p.global_position - global_position
		d.y = 0.0
		if d.length_squared() > 0.01:
			dir = d.normalized()
	facing = dir
	var origin := global_position
	var anims := ["attack", "attack2", "attack3"]
	var last := n >= 3
	begin_attack("combo%d" % n, [0.55, 0.4, 0.5][n - 1], func(): _slash(origin, dir, n, last), 0.8 if last else 0.05, anims[n - 1])
	tele_cone(dir, SLASH_R, SLASH_ANGLE if n < 3 else 200.0)


func _slash(origin: Vector3, dir: Vector3, n: int, last: bool) -> void:
	Sfx.play("swing_heavy", -1.0)
	velocity = dir * 7.0
	var ang := SLASH_ANGLE if n < 3 else 200.0
	Fx3D.slash_arc(fx_parent(), origin + Vector3(0, 1.3, 0), dir, SLASH_R, ang, Color(0.75, 0.35, 1.0), 0.18, 1.4)
	strike_cone(origin, dir, SLASH_R, ang, damage * (1.0 if n < 3 else 1.3), {"knock": 6.0 if n < 3 else 10.0, "tags": ["wide"] if n == 3 else []})
	if not last:
		_combo(n + 1)


func _lunge(pp: Vector3) -> void:
	var dir := pp - global_position
	dir.y = 0.0
	dir = dir.normalized()
	var ln := minf(global_position.distance_to(pp) + 3.0, 12.0)
	begin_attack("lunge", 0.6, func(): dash(dir, 22.0, ln / 22.0, damage * 1.2, {"knock": 9.0}), 0.7, "dash")
	tele_line(global_position, global_position + dir * ln, 1.6)


func _mist_circles(pp: Vector3) -> void:
	var spots: Array = [pp]
	var n := 4 if phase == 1 else 7
	for i in n:
		var a := _rng.randf() * TAU
		spots.append(pp + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(2.0, 6.0))
	begin_attack("mist_circles", 0.95, func(): _mist_burst(spots), 0.6, "block")
	for s in spots:
		tele_circle(s, 1.8, -1.0, MIST)


func _mist_burst(spots: Array) -> void:
	Sfx.play("thunder", -4.0)
	var hit_once := false
	for s in spots:
		var g := _ground_at(s)
		Fx3D.burst(fx_parent(), g + Vector3(0, 0.4, 0), MIST, 10, 5.0)
		Fx3D.flash_light(fx_parent(), g + Vector3(0, 1.0, 0), MIST, 3.0, 3.5, 0.2)
		if not hit_once and strike_circle(g, 1.8, damage, {"knock": 5.0, "kind": "special", "color": MIST}):
			hit_once = true


func _mist_waves() -> void:
	var c := global_position
	begin_attack("mist_waves", 0.9, func(): _waves(c), 1.2, "block")
	tele_circle(c, 2.5, -1.0, MIST)
	tele_ring(c, 2.5, 13.0, -1.0, MIST)


func _waves(c: Vector3) -> void:
	Sfx.play("wind_wall")
	Bus.shake.emit(0.7, 0.4)
	strike_circle(c, 2.5, damage, {"knock": 9.0})
	for i in 3:
		get_tree().create_timer(0.5 * i, false, true).timeout.connect(func():
			if is_instance_valid(self) and not _dead:
				shockwave(c, 13.0, 8.0, damage * 0.7, MIST))


func _orb_volley() -> void:
	begin_attack("orbs", 0.75, func(): _orbs(), 0.6, "block")
	tele_circle(global_position, 2.0, -1.0, MIST)


func _orbs() -> void:
	Sfx.play("shoot_orb")
	for i in 8:
		var a := i * TAU / 8.0
		fire(Vector3(cos(a), 0, sin(a)), 7.0, "orb", 0.9, damage * 0.6)


func _guards(spots: Array) -> void:
	Sfx.play("summon")
	for s in spots:
		var m := summon("balbal", s, {"spawn_delay": 0.5, "element": "erlik"})
		if m:
			minions.append(m)
