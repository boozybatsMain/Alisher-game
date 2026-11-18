extends WeaponBase
## Меч Батыра: серия из 3 рубящих (3-й тяжёлый); особая — вихрь 360° (отбивает снаряды) или выпад в движении.
## Аспекты: 0 — базовый; 1 — Алпамыс (3-й удар пускает волну клинка); 2 — Қобыланды (удерживаемый вихрь);
## 3 — Ер Тарғын (после идеального уклонения — мгновенный контрудар 360° с оглушением).

const COMBO_DMG := [12.0, 14.0, 24.0]
const ARCS := [[1.3, -1.3], [-1.3, 1.3], [1.7, -1.7]]

var _hold_whirl := false
var _hold_t := 0.0
var _hold_tick := 0.0
var _counter_cd := 0.0


func _init() -> void:
	id = "sword"
	base_damage = 14.0
	combo_window = 0.55


func _ready() -> void:
	super._ready()
	if not Bus.perfect_dodge.is_connected(_on_perfect_dodge):
		Bus.perfect_dodge.connect(_on_perfect_dodge)


## Аспект Ер Тарғына: идеальное уклонение — контрудар вокруг героя (×2 урона по атаковавшему, оглушение).
func _on_perfect_dodge(attacker: Node) -> void:
	if aspect != 3 or player == null or not is_inside_tree() or _counter_cd > 0.0:
		return
	_counter_cd = 0.4
	var c := origin()
	var h := make_hit(26.0, "special")
	h.tags.append("targyn_counter")
	h.heavy = true
	h.armor_mult = 2.0
	h.stun = 0.8
	strike_radius(c, 3.0, h, 7.0)
	if attacker is Node3D and is_instance_valid(attacker) and not (attacker.has_method("is_dead") and attacker.is_dead()):
		if (attacker as Node3D).global_position.distance_to(c) > 3.0:
			var hh := h.duplicate_hit()
			hh.position = (attacker as Node3D).global_position
			deal(attacker, hh)
	WeaponFx.slash_arc(self, c - Vector3(0, 0.4, 0), aim(), 3.0, 360.0, glow, 0.25, 0.9)
	WeaponFx.ring(self, feet(), 3.2, glow, 0.3)
	swing_to(0.0, -TAU, 0.22)
	Sfx.play("swing_heavy")
	Bus.hitstop.emit(0.06)


func attack_pressed() -> void:
	super.attack_pressed()
	if _hold_whirl:
		return
	if ready_to_attack():
		_swing()
	else:
		buffer("attack")


func special_pressed() -> void:
	super.special_pressed()
	if after_wall_kick():
		air_special()
		return
	if special_cd > 0.0 or _hold_whirl:
		return
	if ready_to_attack():
		_special()
	else:
		buffer("special")


func special_released() -> void:
	super.special_released()
	if _hold_whirl:
		_end_hold()


func _buffered(kind: String) -> void:
	if kind == "attack":
		_swing()
	elif kind == "special" and special_cd <= 0.0:
		_special()


func _on_cancel() -> void:
	if _hold_whirl:
		_end_hold()


# ---------------------------------------------------------------- обычная
func _swing() -> void:
	if try_move_attack():
		return
	var i := next_combo(3)
	var d := aim()
	var heavy := i == 2
	set_recovery(0.5 if heavy else 0.34)
	slow_move(0.45, 0.25)
	player.lunge(d, 7.0 if heavy else 4.5, 0.08)
	anim("attack" if not heavy else "attack_heavy", 1.0)
	Sfx.play("swing_heavy" if heavy else "swing")
	swing_to(ARCS[i][0], ARCS[i][1], 0.13 / aspd())
	schedule(0.06 / aspd(), _swing_hit.bind(i, d))


## Рывок + обычная: выпад сквозь строй.
func dash_attack() -> bool:
	_lunge(true)
	return true


## Прыжок + обычная: рубящий удар сверху вниз по дуге перед героем (первые удары притормаживают падение).
func air_attack() -> bool:
	var d := aim()
	air_hover(1.6)
	set_recovery(0.32)
	anim("attack_down", 1.3)
	Sfx.play("swing")
	swing_to(-1.6, 0.8, 0.12 / aspd())
	schedule(0.05 / aspd(), func():
		var h := make_hit(15.0)
		h.direction = d
		h.armor_mult = 1.0
		h.stun = 0.15
		h.tags.append("air_attack")
		h.tags.append("air_cleave")
		var c := origin() - Vector3(0, 0.9, 0)
		strike_cone(c, d, 2.5, 170.0, h, 3.5)
		WeaponFx.slash_arc(self, c, d, 2.3, 170.0, glow, 0.16, 0.6))
	return true


func _swing_hit(i: int, d: Vector3) -> void:
	var heavy := i == 2
	var h := make_hit(COMBO_DMG[i])
	h.direction = d
	h.tags.append("combo%d" % (i + 1))
	if heavy:
		h.heavy = true
		h.armor_mult = 2.0
		h.stun = 0.3
	else:
		h.armor_mult = 0.7
	strike_cone(origin(), d, 2.4, 150.0, h, 6.5 if heavy else 2.5)
	WeaponFx.slash_arc(self, origin() - Vector3(0, 0.35, 0), d, 2.3, 150.0, glow, 0.16, 0.7 if heavy else 0.5)
	if heavy and aspect == 1:
		_alpamys_wave(d)


## Аспект Алпамыса: золотая волна клинка, пробивающая строй.
func _alpamys_wave(d: Vector3) -> void:
	var h := make_hit(16.0, "normal")
	h.tags.append("alpamys_wave")
	h.tags.append("projectile")
	h.armor_mult = 1.5
	var vis := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.08, 0.25)
	mi.mesh = bm
	mi.material_override = WeaponFx.solid(glow, glow, 4.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vis.add_child(mi)
	var p := spawn_projectile(origin() + d * 0.8 - Vector3(0, 0.3, 0), d, 18.0, h, vis)
	if p:
		p.pierce = -1
		p.radius = 0.9
		p.max_dist = 9.0
		p.knock_force = 3.0
	Sfx.play("wind_wall", -4.0)


# ---------------------------------------------------------------- особая
func _special() -> void:
	if aspect == 2:
		_whirl()
		_hold_whirl = true
		_hold_t = 0.0
		_hold_tick = 0.0
		return
	if moving():
		_lunge(false)
	else:
		_whirl()


func _whirl(dmg := 18.0, hold := false) -> void:
	var c := origin()
	var h := make_hit(dmg, "special")
	h.tags.append("whirl")
	h.armor_mult = 1.2
	strike_radius(c, 2.8, h, 6.0 if not hold else 3.0)
	reflect_projectiles(c, 3.2)
	WeaponFx.slash_arc(self, c - Vector3(0, 0.4, 0), aim(), 2.6, 360.0, glow, 0.22, 0.8)
	swing_to(0.0, -TAU, 0.28)
	if not hold:
		WeaponFx.ring(self, feet(), 3.0, glow, 0.3)
		Sfx.play("swing_heavy")
		Sfx.play("wind_wall", -6.0)
		special_cd = 0.9
		set_recovery(0.4)
		slow_move(0.5, 0.35)
		anim("special", 1.0)
	else:
		Sfx.play("swing", -4.0)


func _lunge(from_dash: bool) -> void:
	var d := aim()
	var start := origin()
	player.lunge(d, 18.0, 0.18)
	thrust(0.6, 0.15)
	anim("attack" if from_dash else "special", 1.2)
	Sfx.play("dash" if from_dash else "swing_heavy")
	set_recovery(0.4)
	if not from_dash:
		special_cd = 0.8
	var h := make_hit(16.0 if from_dash else 22.0, "normal" if from_dash else "special")
	h.tags.append("lunge")
	if from_dash:
		h.tags.append("dash_strike")
	h.armor_mult = 1.5
	h.direction = d
	schedule(0.1, func():
		strike_line(start, start + d * 4.6, 0.75, h, 5.0)
		for k in 4:
			WeaponFx.flash(self, start + d * (1.0 + k * 1.0), glow, 1.0, 0.18))


func _end_hold() -> void:
	_hold_whirl = false
	special_cd = 1.0
	set_recovery(0.25)


func _tick(delta: float) -> void:
	_counter_cd = maxf(0.0, _counter_cd - delta)
	if not _hold_whirl:
		return
	_hold_t += delta
	_hold_tick += delta
	slow_move(0.55, 0.1)
	busy = maxf(busy, 0.1)
	if _hold_t > 2.6 or not special_held:
		_end_hold()
		return
	if _hold_tick >= 0.28 / aspd():
		_hold_tick = 0.0
		_whirl(9.0, true)
