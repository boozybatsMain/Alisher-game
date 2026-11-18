extends WeaponBase
## Садақ (лук): удержание обычной — натяжение; отпустить во время вспышки на тетиве — идеальный
## пробивающий выстрел, иначе обычный (слабее при раннем отпускании). Особая — веер из 5 стрел.
## Аспекты: 0 — базовый; 1 — Ай-Мерген (стрелы веера самонаводятся); 2 — Ер Төстік (идеальная стрела раскалывается на 3);
## 3 — Құламерген (идеальный выстрел — мгновенный луч, пробивающий всех на линии сквозь броню; обычные стрелы пробивают 1 цель).

const FULL := 0.55          ## время полного натяжения, с (делится на скорость атаки)
const PERFECT := 0.17       ## длительность идеального окна после полного натяжения

var drawing := false
var draw_t := 0.0
var _flashed := false
var _string: MeshInstance3D = null


func _init() -> void:
	id = "bow"
	base_damage = 14.0
	hold_pose = Vector3(0.15, 1.0, 0.0)


func _pose_model() -> void:
	model.position = Vector3(0, 0, -0.4)
	model.rotation = Vector3.ZERO
	if model.has_meta("string"):
		_string = model.get_meta("string") as MeshInstance3D


func attack_pressed() -> void:
	super.attack_pressed()
	if ready_to_attack():
		if try_move_attack():
			return
		_start_draw()
	else:
		buffer("attack")


## Рывок + обычная: мгновенный выстрел без натяжения (стрела сильнее обычного раннего отпускания).
func dash_attack() -> bool:
	var d := aim()
	set_recovery(0.3)
	var h := make_hit(14.0)
	h.direction = d
	h.armor_mult = 1.0
	h.tags.append("arrow")
	h.tags.append("projectile")
	h.tags.append("quick_shot")
	h.tags.append("dash_strike")
	var p := _arrow(origin() + d * 0.6, d, 38.0, h, 1.1)
	if p:
		p.max_dist = 22.0
	anim("shoot", 1.4)
	Sfx.play("shoot_arrow", -2.0)
	return true


## Прыжок + обычная: залп из трёх стрел вниз перед собой, герой зависает в воздухе.
func air_attack() -> bool:
	var d := aim()
	air_hover(3.0)
	set_recovery(0.35)
	var ground := _ground_y()
	var at := feet() + d * 1.2
	at.y = ground + 0.8
	var base_ang := atan2(d.x, d.z)
	for k in [-1, 0, 1]:
		var a := base_ang + deg_to_rad(14.0) * float(k)
		var dd := Vector3(sin(a), 0, cos(a))
		var h := make_hit(9.0)
		h.direction = dd
		h.armor_mult = 0.9
		h.tags.append("arrow")
		h.tags.append("projectile")
		h.tags.append("air_attack")
		h.tags.append("air_volley")
		var p := _arrow(at, dd, 30.0, h, 0.9)
		if p:
			p.max_dist = 12.0
	# след залпа от лука к земле
	for j in 3:
		WeaponFx.flash(self, origin().lerp(at, 0.33 * (j + 1)), glow, 0.7, 0.14)
	anim("shoot", 1.3)
	Sfx.play("shoot_arrow", -1.0)
	return true


## Высота земли под героем (луч вниз по слою мира); если земли нет — уровень ног.
func _ground_y() -> float:
	var f := feet()
	if not is_inside_tree():
		return f.y
	var q := PhysicsRayQueryParameters3D.create(f + Vector3(0, 0.2, 0), f - Vector3(0, 12, 0), Combat.LAYER_WORLD)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return float((r["position"] as Vector3).y) if not r.is_empty() else f.y


func attack_released() -> void:
	super.attack_released()
	if drawing:
		_release()


func special_pressed() -> void:
	super.special_pressed()
	if after_wall_kick():
		air_special()
		return
	if special_cd > 0.0:
		return
	if drawing:
		drawing = false
		_reset_string()
	if ready_to_attack():
		_fan()
	else:
		buffer("special")


func _buffered(kind: String) -> void:
	if kind == "attack" and attack_held:
		_start_draw()
	elif kind == "special" and special_cd <= 0.0:
		_fan()


func _on_cancel() -> void:
	drawing = false
	_reset_string()


func is_busy() -> bool:
	return busy > 0.0 or drawing


func move_mult() -> float:
	return minf(_move_mult, 0.45) if drawing else _move_mult


## Состояние натяжения 0..1 (для HUD/героя) и попадание в идеальное окно.
func draw_ratio() -> float:
	return clampf(draw_t / FULL, 0.0, 1.0)


func in_perfect_window() -> bool:
	return drawing and draw_t >= FULL and draw_t <= FULL + PERFECT


# ---------------------------------------------------------------- натяжение
func _start_draw() -> void:
	drawing = true
	draw_t = 0.0
	_flashed = false
	anim("aim", 1.0)
	Sfx.play("swing", -12.0, 0.05)


func _tick(delta: float) -> void:
	if not drawing:
		return
	draw_t += delta * aspd()
	busy = maxf(busy, 0.05)
	swing_push = -0.12 * draw_ratio()
	if not _flashed and draw_t >= FULL:
		_flashed = true
		_string_flash()
	if _flashed and draw_t > FULL + PERFECT:
		_reset_string()


func _string_flash() -> void:
	Sfx.play("parry", -3.0, 0.0)
	var p := origin() + aim() * 0.5 + Vector3(0, 0.1, 0)
	WeaponFx.flash(self, p, Color(1, 1, 0.85), 1.6, 0.2)
	WeaponFx.light_pop(self, p - Vector3(0, 0.8, 0), glow, 2.0, 3.0, PERFECT)
	if _string and _string.material_override is StandardMaterial3D:
		var m := _string.material_override as StandardMaterial3D
		m.emission = Color(1, 1, 0.85)
		m.emission_energy_multiplier = 8.0


func _reset_string() -> void:
	if _string and _string.material_override is StandardMaterial3D:
		var m := _string.material_override as StandardMaterial3D
		m.emission = glow
		m.emission_energy_multiplier = 2.2


func _release() -> void:
	var t := draw_t
	var perfect := t >= FULL and t <= FULL + PERFECT
	drawing = false
	_reset_string()
	swing_push = 0.0
	set_recovery(0.22)
	var d := aim()
	var dmg := 18.0
	var spd := 30.0
	var h: Hit
	if perfect:
		h = make_hit(30.0)
		h.heavy = true
		h.armor_mult = 2.5
		h.tags.append("perfect_shot")
		spd = 44.0
	else:
		if t < 0.2:
			dmg = 7.0
			spd = 24.0
		elif t < FULL:
			dmg = lerpf(9.0, 16.0, (t - 0.2) / (FULL - 0.2))
		h = make_hit(dmg)
		h.armor_mult = 0.8
	h.tags.append("arrow")
	h.tags.append("projectile")
	if perfect and aspect == 3:
		_kulamergen_shot(d, h)
		anim("shoot", 1.0)
		Sfx.play("shoot_arrow")
		return
	var p := _arrow(origin() + d * 0.6, d, spd, h, 1.4 if perfect else 1.0)
	if p and not perfect and aspect == 3:
		p.pierce = 1
	if p and perfect:
		p.pierce = -1
		p.radius = 0.45
		p.max_dist = 26.0
		p.knock_force = 4.0
		if aspect == 2:
			p.target_hit.connect(_tostik_split, CONNECT_ONE_SHOT)
		WeaponFx.flash(self, origin() + d * 0.8, glow, 1.8, 0.15)
		Bus.shake.emit(0.2, 0.1)
	anim("shoot", 1.0)
	Sfx.play("shoot_arrow", 0.0 if perfect else -3.0)


## Аспект Құламергена: идеальный выстрел бьёт мгновенно всех на линии (до 30 м или стены).
func _kulamergen_shot(d: Vector3, h: Hit) -> void:
	h.tags.append("kulamergen")
	h.amount *= 1.2
	h.armor_mult = 3.0
	var a := origin() + d * 0.6
	var length := 30.0
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(a, a + d * length, Combat.LAYER_WORLD)
		var res := get_world_3d().direct_space_state.intersect_ray(q)
		if not res.is_empty():
			length = maxf(1.0, a.distance_to(res["position"]))
	strike_line(a, a + d * length, 0.6, h, 4.0)
	var n := int(length / 1.5)
	for k in n:
		WeaponFx.flash(self, a + d * (1.5 * k), glow, 0.7, 0.16)
	Bus.shake.emit(0.25, 0.12)


## Аспект Ер Төстіка: идеальная стрела раскалывается на 3 при первом попадании.
func _tostik_split(p: WeaponProjectile, target: Node) -> void:
	var base_ang := atan2(p.dir.x, p.dir.z)
	for k in [-1, 0, 1]:
		var a := base_ang + deg_to_rad(28.0) * float(k)
		var dd := Vector3(sin(a), 0, cos(a))
		var h := make_hit(12.0)
		h.tags.append("arrow")
		h.tags.append("projectile")
		h.tags.append("tostik_split")
		var np := _arrow(p.global_position, dd, 30.0, h, 0.8)
		if np:
			np.hit_set[target] = true
			np.max_dist = 10.0
	Sfx.play("shoot_arrow", -6.0)


func _fan() -> void:
	var d := aim()
	var base_ang := atan2(d.x, d.z)
	for k in 5:
		var a := base_ang + deg_to_rad(-20.0 + 10.0 * k)
		var dd := Vector3(sin(a), 0, cos(a))
		var h := make_hit(9.0, "special")
		h.tags.append("arrow")
		h.tags.append("projectile")
		h.tags.append("fan")
		var p := _arrow(origin() + dd * 0.6, dd, 30.0, h, 0.9)
		if p:
			p.max_dist = 15.0
			if aspect == 1:
				p.homing = 7.0
				p.max_dist = 22.0
	special_cd = 1.0
	set_recovery(0.35)
	anim("shoot", 1.2)
	Sfx.play("shoot_arrow")
	Sfx.play("wind_wall", -10.0)


func _arrow(pos: Vector3, dir: Vector3, spd: float, h: Hit, size := 1.0) -> WeaponProjectile:
	var vis := Node3D.new()
	var shaft := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, 0.035, 0.75) * size
	shaft.mesh = bm
	shaft.material_override = WeaponFx.solid(Color(0.55, 0.38, 0.2))
	vis.add_child(shaft)
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.07, 0.03, 0.16) * size
	head.mesh = hm
	head.position = Vector3(0, 0, -0.42 * size)
	head.material_override = WeaponFx.solid(glow, glow, 3.0)
	vis.add_child(head)
	var fl := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.12, 0.01, 0.14) * size
	fl.mesh = fm
	fl.position = Vector3(0, 0, 0.32 * size)
	fl.material_override = WeaponFx.solid(glow.lerp(Color.WHITE, 0.5), glow, 1.0)
	vis.add_child(fl)
	var p := spawn_projectile(pos, dir, spd, h, vis)
	if p:
		p.radius = 0.35
		p.max_dist = 20.0
		p.knock_force = 1.5
	return p
