extends WeaponBase
## Найза (копьё): быстрые колющие выпады; особая — бросок сквозь строй (застревает в стене/на дальности),
## повторная особая — возврат в руку с уроном по пути. Без копья обычная атака — слабый тычок кулаком.
## Аспекты: 0 — базовый; 1 — Наурызбай (длиннее выпады, урон растёт за каждую пронзённую цель);
## 2 — Томирис (вместо возврата — телепорт к копью со взрывом);
## 3 — Райымбек (выпады пускают кровь; по кровоточащим целям выпад +35%).

const COMBO_DMG := [9.0, 9.0, 14.0]
const COMBO_RANGE := [3.6, 3.6, 4.4]

var in_hand := true
var thrown: WeaponProjectile = null


func _init() -> void:
	id = "spear"
	base_damage = 12.0
	combo_window = 0.45


func _pose_model() -> void:
	model.position = Vector3(0, 0, 0.5)
	model.rotation = Vector3(-0.08, 0, 0)


func _range_mult() -> float:
	return 1.4 if aspect == 1 else 1.0


func attack_pressed() -> void:
	super.attack_pressed()
	if ready_to_attack():
		_attack()
	else:
		buffer("attack")


func special_pressed() -> void:
	super.special_pressed()
	if after_wall_kick():
		air_special()
		return
	if not in_hand:
		_recall()
		return
	if special_cd > 0.0:
		return
	if ready_to_attack():
		_throw()
	else:
		buffer("special")


func _buffered(kind: String) -> void:
	if kind == "attack":
		_attack()
	elif kind == "special" and in_hand and special_cd <= 0.0:
		_throw()


# ---------------------------------------------------------------- обычная
func _attack() -> void:
	var d := aim()
	if not in_hand:
		# тычок кулаком, пока копьё в полёте/в стене
		set_recovery(0.3)
		anim("attack", 1.2)
		Sfx.play("swing", -4.0)
		var hj := make_hit(5.0)
		hj.tags.append("unarmed")
		hj.armor_mult = 0.4
		strike_cone(origin(), d, 1.4, 90.0, hj, 2.0)
		WeaponFx.slash_arc(self, origin() - Vector3(0, 0.3, 0), d, 1.3, 60.0, glow, 0.12, 0.3)
		return
	if try_move_attack():
		return
	var i := next_combo(3)
	set_recovery(0.38 if i == 2 else 0.24)
	slow_move(0.55, 0.2)
	if i == 2:
		player.lunge(d, 5.0, 0.08)
	_thrust(d, COMBO_RANGE[i] * _range_mult(), COMBO_DMG[i], false, i)


## Рывок + обычная: длинный выпад (только с копьём в руке — иначе тычок кулаком в _attack).
func dash_attack() -> bool:
	if not in_hand:
		return false
	var d := aim()
	_thrust(d, 5.5 * _range_mult(), 16.0, true)
	player.lunge(d, 14.0, 0.15)
	set_recovery(0.4)
	return true


## Прыжок + обычная: выпад вниз-вперёд — герой ныряет по диагонали, наконечник бьёт линию под ним.
func air_attack() -> bool:
	if not in_hand:
		return false
	var d := aim()
	set_recovery(0.42)
	anim("attack_down", 1.3)
	Sfx.play("swing", -1.0, 0.1)
	thrust(1.2, 0.1 / aspd())
	player.velocity = Vector3(d.x * 7.0, minf(player.velocity.y, -9.0), d.z * 7.0)
	var h := make_hit(17.0)
	h.direction = d
	h.armor_mult = 1.6
	h.stun = 0.2
	h.tags.append("thrust")
	h.tags.append("air_attack")
	h.tags.append("air_dive_thrust")
	schedule(0.07 / aspd(), func():
		var a := feet() - Vector3(0, 0.3, 0)
		var b := a + d * 3.4 * _range_mult()
		strike_line(a, b, 0.7, h, 4.0)
		for j in 3:
			WeaponFx.flash(self, a.lerp(b, 0.3 + 0.3 * j) + Vector3(0, 0.3, 0), glow, 0.7, 0.14))
	return true


func _thrust(d: Vector3, reach: float, dmg: float, dash: bool, idx := 0) -> void:
	anim("attack", 1.3)
	Sfx.play("swing", -2.0, 0.15)
	thrust(0.9 if idx < 2 else 1.3, 0.1 / aspd())
	var h := make_hit(dmg)
	h.direction = d
	h.armor_mult = 0.8 if idx < 2 else 1.4
	h.tags.append("thrust")
	h.tags.append("combo%d" % (idx + 1))
	if dash:
		h.tags.append("dash_strike")
		h.heavy = true
	schedule(0.05 / aspd(), _thrust_hit.bind(h, d, reach))


func _thrust_hit(h: Hit, d: Vector3, reach: float) -> void:
	var a := origin()
	var b := a + d * reach
	var targets := Combat.along_line(get_tree(), a, b, 0.45)
	targets.sort_custom(func(x, y): return a.distance_squared_to(x.global_position) < a.distance_squared_to(y.global_position))
	var k := 0
	for t in targets:
		if t == player or (t.has_method("is_dead") and t.is_dead()):
			continue
		var hh := h.duplicate_hit()
		hh.position = (t as Node3D).global_position
		hh.knockback = d * 3.0
		if aspect == 1:
			hh.amount *= 1.0 + 0.25 * k
		elif aspect == 3:
			var st = t.get("statuses")
			if st is Dictionary and st.has("bleed"):
				hh.amount *= 1.35
			hh.statuses.append({"id": "bleed", "dps": 5.0, "time": 3.0})
		deal(t, hh)
		k += 1
	# след выпада
	for j in 3:
		WeaponFx.flash(self, a + d * reach * (0.4 + 0.3 * j) - Vector3(0, 0.1, 0), glow, 0.6, 0.12)


# ---------------------------------------------------------------- бросок / возврат
func _throw() -> void:
	var d := aim()
	var h := make_hit(18.0, "special")
	h.tags.append("spear_throw")
	h.tags.append("projectile")
	h.armor_mult = 1.5
	var vis := WeaponModel.build("spear", glow)
	vis.position = Vector3(0, 0, 0.9)
	var holder := Node3D.new()
	holder.add_child(vis)
	var p := spawn_projectile(origin() + d * 0.5, d, 28.0, h, holder)
	if p == null:
		return
	p.pierce = -1
	p.stick = true
	p.radius = 0.5
	p.max_dist = 16.0
	p.knock_force = 4.0
	p.lifetime = 30.0
	if aspect == 1:
		p.hit_mult_per_target = 0.25
	p.finished.connect(_on_spear_finished)
	thrown = p
	in_hand = false
	show_model(false)
	special_cd = 0.35
	set_recovery(0.3)
	anim("special", 1.2)
	Sfx.play("swing_heavy")


func _recall() -> void:
	if thrown == null or not is_instance_valid(thrown):
		_catch()
		return
	if aspect == 2:
		_tomiris_jump()
		return
	var h := make_hit(14.0, "special")
	h.tags.append("spear_return")
	h.tags.append("projectile")
	h.armor_mult = 1.2
	thrown.hit_proto = h
	thrown.knock_force = 3.0
	thrown.hit_mult_per_target = 0.25 if aspect == 1 else 0.0
	thrown.recall(player, 32.0)
	Sfx.play("swing", 0.0, 0.2)


## Аспект Томирис: телепорт к копью и взрыв.
func _tomiris_jump() -> void:
	var p := thrown.global_position
	var dest := Vector3(p.x, p.y - 0.9, p.z) - thrown.dir * 0.4
	WeaponFx.flash(self, origin(), glow, 2.0, 0.2)
	player.teleport_to(dest)
	thrown.queue_free()
	thrown = null
	_catch()
	var h := make_hit(26.0, "special")
	h.tags.append("tomiris_blast")
	h.heavy = true
	h.armor_mult = 2.0
	h.stun = 0.4
	strike_radius(dest, 3.0, h, 8.0, 3.0)
	WeaponFx.ring(self, dest, 3.4, glow, 0.35)
	WeaponFx.flash(self, dest + Vector3(0, 0.8, 0), glow, 3.0, 0.3)
	WeaponFx.light_pop(self, dest, glow, 4.0, 6.0, 0.3)
	Sfx.play("teleport")
	Sfx.play("slam")
	Bus.shake.emit(0.45, 0.25)
	special_cd = 0.6


func _on_spear_finished(p: WeaponProjectile, reason: String) -> void:
	if p != thrown:
		return
	if reason == "wall" or reason == "range":
		Sfx.play("block", -6.0)
		WeaponFx.flash(self, p.global_position, glow, 1.0, 0.2)
		return    # воткнулось, ждёт возврата
	if reason == "returned":
		Sfx.play("block", -3.0)
	thrown = null
	_catch()


func _catch() -> void:
	in_hand = true
	thrown = null
	show_model(true)


func _tick(_delta: float) -> void:
	if not in_hand and (thrown == null or not is_instance_valid(thrown)):
		_catch()


func _exit_tree() -> void:
	if thrown and is_instance_valid(thrown):
		thrown.queue_free()
