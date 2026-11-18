extends WeaponBase
## Темір қолғап (железные перчатки): быстрая серия из 5 ударов (5-й мощный); особая — апперкот,
## подбрасывающий врага (hit.launch). В воздухе удары держат героя (лёгкое зависание) — воздушное комбо.
## Аспекты: 0 — базовый; 1 — Қажымұқан (5-й удар — бросок борца, ×2 о стены);
## 2 — Балуан Шолақ (стаки ярости: +6% скорости атаки и урона за удар без перерыва, до 10);
## 3 — Қамбар (апперкот бьёт ударной волной вокруг и подбрасывает всех рядом).

const COMBO_DMG := [6.0, 6.0, 7.0, 7.0, 16.0]
const COMBO_REC := [0.16, 0.16, 0.18, 0.18, 0.42]

var fury := 0
var _fury_t := 0.0
var _air_window := 0.0     ## после апперкота: воздушные удары зависают сильнее


func _init() -> void:
	id = "gauntlets"
	base_damage = 10.0
	combo_window = 0.45
	hold_pose = Vector3(0.0, 0.95, 0.0)


func _pose_model() -> void:
	model.position = Vector3(0, 0, -0.3)
	model.rotation = Vector3.ZERO


func aspd() -> float:
	var a := super.aspd()
	if aspect == 2:
		a *= 1.0 + 0.06 * fury
	return a


func attack_pressed() -> void:
	super.attack_pressed()
	if ready_to_attack():
		_punch()
	else:
		buffer("attack")


func special_pressed() -> void:
	super.special_pressed()
	if after_wall_kick():
		air_special()
		return
	if special_cd > 0.0:
		return
	if ready_to_attack():
		_uppercut()
	else:
		buffer("special")


func _buffered(kind: String) -> void:
	if kind == "attack":
		_punch()
	elif kind == "special" and special_cd <= 0.0:
		_uppercut()


## Рывок + обычная: таранный удар с разбега (тяжёлый, отбрасывает).
func dash_attack() -> bool:
	var d := aim()
	set_recovery(0.38)
	player.lunge(d, 12.0, 0.14)
	anim("attack_heavy", 1.4)
	Sfx.play("swing_heavy", -2.0, 0.1)
	swing_to(0.0, 0.0, 0.08, 0.8)
	var h := make_hit(15.0)
	h.direction = d
	h.heavy = true
	h.armor_mult = 1.8
	h.stun = 0.3
	h.tags.append("dash_strike")
	h.tags.append("rush_punch")
	schedule(0.08 / aspd(), _punch_hit.bind(h, d, 8.0, 1.0, true))
	return true


func _punch() -> void:
	if try_move_attack():
		return
	var i := next_combo(5)
	var d := aim()
	var heavy := i == 4
	var in_air := airborne()
	set_recovery(COMBO_REC[i])
	slow_move(0.6, 0.15)
	if in_air:
		# воздушное комбо: удары не дают быстро упасть
		var hover := 2.5 if _air_window > 0.0 else 1.0
		player.velocity.y = maxf(player.velocity.y, hover)
	elif heavy:
		player.lunge(d, 6.0, 0.08)
	else:
		player.lunge(d, 2.5, 0.05)
	anim("attack_heavy" if heavy else "attack", 1.3)
	Sfx.play("swing_heavy" if heavy else "swing", -2.0 if heavy else -5.0, 0.15)
	# чередуем кулаки: левый/правый выдвигаются вперёд
	swing_to(0.25 if i % 2 == 0 else -0.25, 0.0, 0.08, 0.45 if not heavy else 0.7)
	var h := make_hit(COMBO_DMG[i])
	h.direction = d
	h.tags.append("combo%d" % (i + 1))
	h.armor_mult = 0.6
	if in_air:
		h.tags.append("air_combo")
	if aspect == 2 and fury > 0:
		h.amount *= 1.0 + 0.06 * fury
	var knock := 1.5
	var up := 0.0
	if heavy:
		h.heavy = true
		h.armor_mult = 2.0
		h.stun = 0.35
		knock = 7.0
		if aspect == 1:
			h.tags.append("wall_x2")
			h.tags.append("wrestler_throw")
			h.stun = 1.0
			knock = 18.0
			up = 3.0
	if in_air:
		up = maxf(up, 2.0)   # подбитые в воздухе враги не падают сразу
	schedule(0.04 / aspd(), _punch_hit.bind(h, d, knock, up, heavy))


func _punch_hit(h: Hit, d: Vector3, knock: float, up: float, heavy: bool) -> void:
	var n := strike_cone(origin(), d, 1.7, 100.0, h, knock, up)
	WeaponFx.flash(self, origin() + d * 0.9, glow, 0.9 if not heavy else 1.8, 0.1)
	if heavy:
		WeaponFx.slash_arc(self, origin() - Vector3(0, 0.3, 0), d, 1.7, 90.0, glow, 0.14, 0.6)
		if aspect == 1 and n > 0:
			Sfx.play("slam", -2.0)
	if aspect == 2 and n > 0:
		fury = mini(fury + 1, 10)
		_fury_t = 1.5
		if light:
			light.light_energy = 0.55 + 0.12 * fury


func _uppercut() -> void:
	var d := aim()
	special_cd = 0.8
	set_recovery(0.45)
	anim("special", 1.2)
	Sfx.play("swing_heavy")
	swing_to(0.0, 0.0, 0.12, 0.6)
	_air_window = 1.6
	var h := make_hit(18.0, "special")
	h.direction = d
	h.launch = true
	h.heavy = true
	h.armor_mult = 1.5
	h.stun = 0.9
	h.tags.append("uppercut")
	if aspect == 2 and fury > 0:
		h.amount *= 1.0 + 0.06 * fury
	schedule(0.06 / aspd(), func():
		var n := strike_cone(origin(), d, 1.9, 110.0, h, 2.0, 9.0)
		WeaponFx.flash(self, origin() + d * 0.9 + Vector3(0, 0.6, 0), glow, 2.0, 0.18)
		WeaponFx.ring(self, feet() + d * 0.9, 1.4, glow, 0.2)
		if n > 0 and aspect == 2:
			fury = mini(fury + 1, 10)
			_fury_t = 1.5)
	if aspect == 3:
		schedule(0.1 / aspd(), _kambar_wave)


## Аспект Қамбара: ударная волна апперкота — подбрасывает всех в радиусе.
func _kambar_wave() -> void:
	var h := make_hit(12.0, "special")
	h.launch = true
	h.stun = 0.7
	h.armor_mult = 1.2
	h.tags.append("kambar_wave")
	strike_radius(feet() + Vector3(0, 0.5, 0), 3.4, h, 3.0, 8.0)
	WeaponFx.ring(self, feet(), 3.4, glow, 0.3)
	Bus.shake.emit(0.2, 0.12)
	Sfx.play("swing_heavy", -4.0)


func _tick(delta: float) -> void:
	_air_window = maxf(0.0, _air_window - delta)
	if fury > 0:
		_fury_t -= delta
		if _fury_t <= 0.0:
			fury = 0
			if light:
				light.light_energy = 0.55
