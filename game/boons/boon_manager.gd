class_name BoonManager
extends Node
## Духовные Дары текущего забега (живёт в Run.boons). Один дар на слот attack/special/dash
## (новый заменяет старый того же слота) + любое число пассивов. Хранит {id, level, rarity}.
## Модифицирует удары героя (modify_outgoing), входящий урон (modify_incoming), характеристики (stat_bonus)
## и реализует эффекты через подписки на Bus: молнии, стрелы духа, огненные волны, взрывы проклятия и т.д.

const ACTIVE_SLOTS := ["attack", "special", "dash"]

var boons: Array = []                 ## [{id, level, rarity}]
var rng := RandomNumberGenerator.new()

# --- состояние эффектов ---
var frenzy := 0                       ## стаки «Охотничьего Ража» (Көкбөрі)
var _frenzy_t := 0.0
var _storm_t := 0.0
var _dash_crit := false               ## «Тень Охотника»: следующий удар — крит
var _dash_wolf := false               ## «Волчий Бросок»: следующий удар усилен
var _freeze_count := {}               ## instance_id цели → попадания особой (Ледяной Поток)
var _cd := {}                         ## внутренние кулдауны эффектов: ключ → время


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	rng.randomize()
	Bus.hit_landed.connect(_on_hit_landed)
	Bus.enemy_killed.connect(_on_enemy_killed)
	Bus.player_dashed.connect(_on_player_dashed)
	Bus.player_landed.connect(_on_player_landed)


# ================================================================ хранение
func reset() -> void:
	boons.clear()
	frenzy = 0
	_frenzy_t = 0.0
	_storm_t = 0.0
	_dash_crit = false
	_dash_wolf = false
	_freeze_count.clear()
	_cd.clear()
	Bus.boons_changed.emit()


func _find(id: String) -> int:
	for i in boons.size():
		if boons[i]["id"] == id:
			return i
	return -1


## Добавить дар. Если уже есть — повышает редкость/уровень до переданных (не ниже текущих).
## Активный слот: старый дар того же слота удаляется (без выплаты).
func add_boon(id: String, rarity := "common", level := 1) -> void:
	if not BoonData.exists(id):
		push_warning("BoonManager: неизвестный дар " + id)
		return
	var i := _find(id)
	if i >= 0:
		var b: Dictionary = boons[i]
		if BoonData.rarity_index(rarity) > BoonData.rarity_index(b["rarity"]):
			b["rarity"] = rarity
		b["level"] = clampi(maxi(int(b["level"]), level), 1, BoonData.MAX_LEVEL)
	else:
		var slot := BoonData.slot_of(id)
		if slot in ACTIVE_SLOTS:
			var old := slot_boon(slot)
			if old != "":
				boons.remove_at(_find(old))
		boons.append({"id": id, "level": clampi(level, 1, BoonData.MAX_LEVEL), "rarity": rarity if rarity in BoonData.RARITIES else "common"})
	Bus.boons_changed.emit()


func has_boon(id: String) -> bool:
	return _find(id) >= 0


func level_of(id: String) -> int:
	var i := _find(id)
	return int(boons[i]["level"]) if i >= 0 else 0


func rarity_of(id: String) -> String:
	var i := _find(id)
	return String(boons[i]["rarity"]) if i >= 0 else ""


func level_up(id: String) -> void:
	var i := _find(id)
	if i < 0:
		return
	boons[i]["level"] = mini(int(boons[i]["level"]) + 1, BoonData.MAX_LEVEL)
	Bus.boons_changed.emit()


func can_level_up(id: String) -> bool:
	return has_boon(id) and level_of(id) < BoonData.MAX_LEVEL


## Дары, которые можно улучшить (для торговца).
func upgradable() -> Array:
	var out := []
	for b in boons:
		if int(b["level"]) < BoonData.MAX_LEVEL:
			out.append(b["id"])
	return out


func sell_price(id: String) -> int:
	var i := _find(id)
	if i < 0:
		return 0
	return BoonData.sell_price(boons[i]["rarity"], int(boons[i]["level"]))


## Удалить дар (Колодец Обмена). Возвращает цену продажи в дирхемах.
func remove_boon(id: String) -> int:
	var i := _find(id)
	if i < 0:
		return 0
	var price := sell_price(id)
	boons.remove_at(i)
	Bus.boons_changed.emit()
	return price


func owned() -> Array:
	return boons.duplicate(true)


## id дара в активном слоте ("" если пусто).
func slot_boon(slot: String) -> String:
	for b in boons:
		if BoonData.slot_of(b["id"]) == slot:
			if slot in ACTIVE_SLOTS:
				return b["id"]
	return ""


## Значение параметра собственного дара (0, если дара нет).
func val(id: String, key: String) -> float:
	var i := _find(id)
	if i < 0:
		return 0.0
	return BoonData.value(id, key, int(boons[i]["level"]), boons[i]["rarity"])


# ================================================================ выбор даров
func roll_rarity() -> String:
	var r := rng.randf()
	var epic := Run.stat("epic_chance")
	var rare := Run.stat("rare_chance")
	if r < epic:
		return "epic"
	if r < epic + rare:
		return "rare"
	return "common"


## count случайных даров духа. Каждый вариант: {id, god, rarity, level, upgrade, replaces}.
## Уже взятые предлагаются как улучшение (уровень +1, редкость не ниже текущей; на макс. уровне — редкость +1).
## Полностью прокачанные (макс. уровень и epic) не выпадают.
func roll_choices(god: String, count := 3) -> Array:
	var pool := []
	for id in BoonData.boons_of(god):
		var i := _find(id)
		if i >= 0 and int(boons[i]["level"]) >= BoonData.MAX_LEVEL and boons[i]["rarity"] == "epic":
			continue
		pool.append(id)
	# перемешать
	for k in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp = pool[k]
		pool[k] = pool[j]
		pool[j] = tmp
	# хотя бы один дар активного слота в выборке, если такой есть в пуле
	var pick: Array = pool.slice(0, mini(count, pool.size()))
	if pick.size() > 0 and pick.size() < pool.size():
		var has_active := false
		for id in pick:
			if BoonData.slot_of(id) in ACTIVE_SLOTS:
				has_active = true
				break
		if not has_active:
			for k in range(pick.size(), pool.size()):
				if BoonData.slot_of(pool[k]) in ACTIVE_SLOTS:
					pick[pick.size() - 1] = pool[k]
					break
	var out := []
	for id in pick:
		out.append(_make_choice(id))
	return out


func _make_choice(id: String) -> Dictionary:
	var rar := roll_rarity()
	var i := _find(id)
	var c := {"id": id, "god": BoonData.god_of(id), "rarity": rar, "level": 1, "upgrade": false, "replaces": ""}
	if i >= 0:
		var cur: Dictionary = boons[i]
		c["upgrade"] = true
		c["level"] = mini(int(cur["level"]) + 1, BoonData.MAX_LEVEL)
		var cur_r := BoonData.rarity_index(cur["rarity"])
		if int(cur["level"]) >= BoonData.MAX_LEVEL:
			# уровень уже не поднять — улучшение обязано поднять редкость (epic+max в пул не попадает)
			var nr := maxi(cur_r + 1, BoonData.rarity_index(rar))
			c["rarity"] = BoonData.RARITIES[mini(nr, BoonData.RARITIES.size() - 1)]
		elif cur_r > BoonData.rarity_index(rar):
			c["rarity"] = cur["rarity"]
	else:
		var slot := BoonData.slot_of(id)
		if slot in ACTIVE_SLOTS:
			c["replaces"] = slot_boon(slot)
	return c


## Применить выбранный вариант из roll_choices.
func take_choice(choice: Dictionary) -> void:
	if choice.is_empty():
		return
	var id: String = choice.get("id", "")
	if choice.get("upgrade", false) and has_boon(id):
		var i := _find(id)
		boons[i]["level"] = clampi(int(choice.get("level", 1)), 1, BoonData.MAX_LEVEL)
		boons[i]["rarity"] = choice.get("rarity", boons[i]["rarity"])
		Bus.boons_changed.emit()
	else:
		add_boon(id, choice.get("rarity", "common"), int(choice.get("level", 1)))


# ================================================================ характеристики
func stat_bonus(key: String) -> float:
	if boons.is_empty():
		return 0.0
	match key:
		"crit_chance":
			return val("aim_crit", "v") * 0.01
		"crit_mult":
			return val("aim_critdmg", "v") * 0.01
		"damage_mult":
			return val("erlik_blood", "v") * 0.01
		"attack_speed_mult":
			return frenzy * val("kok_frenzy", "as") * 0.01
		"move_speed_mult":
			return frenzy * val("kok_frenzy", "ms") * 0.01 + val("kok_swift", "v") * 0.01
		"backstab_mult":
			return val("kok_hunt", "b") * 0.01
		"dash_charges":
			return val("kok_swift", "d")
	return 0.0


# ================================================================ удары
func _slot_for(hit: Hit) -> String:
	match hit.kind:
		"normal": return "attack"
		"special": return "special"
		"dash": return "dash"
	return ""


static func _has_status(target: Node, st: String) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var s = target.get("statuses")
	return s is Dictionary and (s as Dictionary).has(st)


static func _poison_stacks(target: Node) -> int:
	if not _has_status(target, "poison"):
		return 0
	var p = target.get("statuses")["poison"]
	if p is Dictionary:
		return int(p.get("stacks", 1))
	return 1


func modify_outgoing(hit: Hit, target: Node) -> void:
	if hit.no_boons or boons.is_empty() and not _dash_crit and not _dash_wolf:
		return
	var slot := _slot_for(hit)
	var sb := slot_boon(slot) if slot != "" else ""
	if sb != "":
		hit.tags.append("boon:" + sb)
		if hit.element == "":
			hit.element = BoonData.god_of(sb)
	match sb:
		"tengri_strike":
			hit.tags.append("tengri_chain")
		"tengri_flash":
			hit.tags.append("tengri_flash")
		"aim_attack":
			if not hit.is_crit and rng.randf() < val(sb, "crit") * 0.01:
				hit.is_crit = true
		"aim_special":
			hit.tags.append("aim_arrows")
		"umai_attack":
			hit.statuses.append({"id": "burn", "dps": val(sb, "dps"), "time": 3.0})
		"umai_special":
			hit.amount *= 1.0 + val(sb, "v") * 0.01
			hit.statuses.append({"id": "burn", "dps": val(sb, "dps"), "time": 4.0})
		"zher_attack":
			var m := 1.0 + val(sb, "v") * 0.01
			if hit.knockback.length() < 1.0:
				hit.knockback += hit.direction * 3.0
			hit.knockback = Vector3(hit.knockback.x * m, hit.knockback.y, hit.knockback.z * m)
			if not "wall_x2" in hit.tags:
				hit.tags.append("wall_x2")
		"zher_special":
			hit.statuses.append({"id": "slow", "mult": 1.0 - val(sb, "slow") * 0.01, "time": 3.0})
			if target:
				var key := target.get_instance_id()
				var n: int = int(_freeze_count.get(key, 0)) + 1
				if n >= 3:
					n = 0
					hit.statuses.append({"id": "freeze", "time": val(sb, "freeze")})
				_freeze_count[key] = n
		"erlik_attack":
			hit.statuses.append({"id": "poison", "stacks": int(val(sb, "n"))})
		"erlik_special":
			hit.amount *= 1.0 + val(sb, "v") * 0.01
			hit.statuses.append({"id": "curse", "time": val(sb, "t")})
		"kok_attack":
			hit.statuses.append({"id": "bleed", "dps": val(sb, "dps"), "time": 4.0})
		"kok_special":
			var cnt := 0
			if target is Node3D:
				for e in Combat.in_radius(get_tree(), (target as Node3D).global_position, 6.0):
					if _has_status(e, "bleed"):
						cnt += 1
			hit.amount *= 1.0 + val(sb, "v") * 0.01 * mini(cnt, 5)
	# рывковые заряды
	if hit.kind in ["normal", "special"]:
		if _dash_crit:
			_dash_crit = false
			hit.is_crit = true
			hit.amount *= 1.0 + val("aim_dash", "dmg") * 0.01
		if _dash_wolf:
			_dash_wolf = false
			hit.amount *= 1.0 + val("kok_dash", "v") * 0.01
			hit.statuses.append({"id": "bleed", "dps": 8.0, "time": 4.0})
	# пассивы
	if hit.is_crit and has_boon("aim_pierce"):
		hit.pierce_armor = true
		hit.armor_mult *= 1.0 + val("aim_pierce", "armor") * 0.01
	if has_boon("umai_ember") and _has_status(target, "burn"):
		hit.amount *= 1.0 + val("umai_ember", "v") * 0.01
	if has_boon("zher_frost") and (_has_status(target, "slow") or _has_status(target, "freeze")):
		hit.amount *= 1.0 + val("zher_frost", "v") * 0.01
	if has_boon("erlik_rot") and _has_status(target, "poison"):
		hit.amount *= 1.0 + val("erlik_rot", "v") * 0.01
	if has_boon("kok_hunt") and _has_status(target, "bleed"):
		hit.amount *= 1.0 + val("kok_hunt", "v") * 0.01


func modify_incoming(amount: float, source: Node) -> float:
	if boons.is_empty():
		return amount
	if has_boon("zher_skin"):
		amount *= 1.0 - val("zher_skin", "v") * 0.01
	if has_boon("tengri_shock") and source is Node3D and is_instance_valid(source) and source.is_in_group("hurtable_enemy") and _ready_cd("shock", 0.5):
		_retaliate.call_deferred(source)
	return amount


# ================================================================ эффекты (Bus)
func _player() -> Node3D:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("player") as Node3D


static func _is_player(n: Node) -> bool:
	return n != null and is_instance_valid(n) and n.is_in_group("player")


func _ready_cd(key: String, cd: float) -> bool:
	var now := Time.get_ticks_msec() * 0.001
	if now < float(_cd.get(key, -100.0)):
		return false
	_cd[key] = now + cd
	return true


## Удар Дара: не проходит через Дары повторно (no_boons), чтобы не было бесконечных цепочек.
func boon_hit(target: Node, amount: float, god: String, stun := 0.0, statuses: Array = [], knock := Vector3.ZERO) -> void:
	if not is_instance_valid(target) or not target.has_method("take_hit"):
		return
	if target.has_method("is_dead") and target.is_dead():
		return
	var h := Hit.make(amount, _player(), "boon")
	h.no_boons = true
	h.element = god
	h.stun = stun
	h.statuses = statuses.duplicate(true)
	h.knockback = knock
	h.tags.append("boon:" + god)
	if target is Node3D:
		h.position = (target as Node3D).global_position
	Combat.player_hit(target, h)


func _on_hit_landed(hit: Hit, target: Node) -> void:
	if hit == null or hit.no_boons or not _is_player(hit.source) or boons.is_empty():
		return
	if not is_instance_valid(target) or not (target is Node3D):
		return
	var tpos := (target as Node3D).global_position
	if has_boon("kok_frenzy"):
		frenzy = mini(frenzy + 1, int(val("kok_frenzy", "max")))
		_frenzy_t = 3.0
	if "tengri_chain" in hit.tags:
		_chain_lightning.call_deferred(target, val("tengri_strike", "dmg"), int(val("tengri_strike", "jumps")))
	if "tengri_flash" in hit.tags and _ready_cd("flash:%d" % target.get_instance_id(), 0.3):
		_sky_bolt.call_deferred(target, val("tengri_flash", "dmg"), val("tengri_flash", "stun"))
	if "aim_arrows" in hit.tags and _ready_cd("arrows", 0.6):
		_spirit_arrows.call_deferred(int(val("aim_special", "n")), val("aim_special", "dmg"))
	if has_boon("tengri_static") and _ready_cd("static", 0.4) and rng.randf() < val("tengri_static", "chance") * 0.01:
		_static_stun.call_deferred(tpos, val("tengri_static", "stun"))
	if has_boon("zher_quake") and hit.heavy and _ready_cd("quake", 0.3):
		_quake.call_deferred(tpos, val("zher_quake", "dmg"))
	if has_boon("erlik_blood") and _ready_cd("blood", 0.25):
		_blood_price()


func _on_enemy_killed(enemy: Node, _hit: Hit) -> void:
	if boons.is_empty() or not is_instance_valid(enemy) or not (enemy is Node3D):
		return
	var pos := (enemy as Node3D).global_position
	if has_boon("umai_heal") and _has_status(enemy, "burn"):
		var v := val("umai_heal", "v")
		Run.heal(v)
		Bus.damage_number.emit(pos + Vector3(0, 1.5, 0), v, "heal")
	if has_boon("erlik_blast") and (_has_status(enemy, "curse") or _poison_stacks(enemy) >= 5):
		_curse_blast.call_deferred(pos, val("erlik_blast", "dmg"), enemy)


func _on_player_dashed(from: Vector3, to: Vector3) -> void:
	if boons.is_empty():
		return
	match slot_boon("dash"):
		"tengri_dash":
			_discharge.call_deferred(from, val("tengri_dash", "dmg"))
		"umai_dash":
			_fire_trail.call_deferred(from, to, val("umai_dash", "dmg"), val("umai_dash", "dps"))
		"zher_dash":
			_ice_burst.call_deferred(to, val("zher_dash", "t"))
		"erlik_dash":
			_dark_step.call_deferred(from, to, int(val("erlik_dash", "n")))
		"aim_dash":
			_dash_crit = true
		"kok_dash":
			_dash_wolf = true
	if has_boon("erlik_blood"):
		_blood_price()


func _on_player_landed(fall_height: float) -> void:
	if has_boon("umai_landing") and fall_height >= 0.4 and _ready_cd("landing", 0.4):
		var p := _player()
		if p:
			_fire_wave.call_deferred(p.global_position, val("umai_landing", "dmg"), val("umai_landing", "r"))


func _process(delta: float) -> void:
	if frenzy > 0:
		_frenzy_t -= delta
		if _frenzy_t <= 0.0:
			frenzy = maxi(0, frenzy - 1)
			_frenzy_t = 0.5
	if has_boon("tengri_storm"):
		_storm_t += delta
		if _storm_t >= val("tengri_storm", "cd"):
			_storm_t = 0.0
			_storm_strike()


# ================================================================ реализации эффектов
const C_TENGRI := Color("#8cc8ff")
const C_AIM := Color("#c9b3ff")
const C_UMAI := Color("#ff8a3d")
const C_ZHER := Color("#5fd3c4")
const C_ERLIK := Color("#9b4dff")


func _chain_lightning(first: Node, dmg: float, jumps: int) -> void:
	if not is_instance_valid(first) or not (first is Node3D):
		return
	var visited: Array = [first]
	var cur: Node3D = first
	for i in jumps:
		var nxt := Combat.nearest(get_tree(), cur.global_position, 6.0, "hurtable_enemy", visited)
		if nxt == null:
			break
		WeaponFx.bolt(self, cur.global_position + Vector3(0, 1, 0), nxt.global_position + Vector3(0, 1, 0), C_TENGRI, 0.2, 0.08)
		boon_hit(nxt, dmg, "tengri")
		visited.append(nxt)
		cur = nxt
	if visited.size() > 1:
		Sfx.play("thunder", -12.0, 0.2)


func _sky_bolt(target: Node, dmg: float, stun: float) -> void:
	if not is_instance_valid(target) or not (target is Node3D):
		return
	var p := (target as Node3D).global_position
	WeaponFx.bolt(self, p + Vector3(0.4, 7, -0.6), p + Vector3(0, 0.3, 0), C_TENGRI, 0.3, 0.16)
	WeaponFx.light_pop(self, p, C_TENGRI, 4.0, 6.0, 0.25)
	boon_hit(target, dmg, "tengri", stun, [{"id": "shock", "time": stun}])
	Sfx.play("thunder", -4.0)
	Bus.shake.emit(0.25, 0.12)


func _static_stun(pos: Vector3, stun: float) -> void:
	WeaponFx.ring(self, pos, 3.0, C_TENGRI, 0.3)
	for e in Combat.in_radius(get_tree(), pos, 3.0):
		if e.has_method("apply_status"):
			e.apply_status("stun", {"time": stun})
		WeaponFx.bolt(self, pos + Vector3(0, 1, 0), (e as Node3D).global_position + Vector3(0, 1, 0), C_TENGRI, 0.15, 0.05)
	Sfx.play("thunder", -10.0, 0.25)


func _storm_strike() -> void:
	var p := _player()
	if p == null:
		return
	var cands := []
	for e in Combat.in_radius(get_tree(), p.global_position, 12.0, "enemies", 6.0):
		if not (e.has_method("is_dead") and e.is_dead()):
			cands.append(e)
	if cands.is_empty():
		return
	_sky_bolt(cands[rng.randi_range(0, cands.size() - 1)], val("tengri_storm", "dmg"), 0.3)


func _retaliate(source: Node) -> void:
	var p := _player()
	if p == null or not is_instance_valid(source):
		return
	WeaponFx.bolt(self, p.global_position + Vector3(0, 1, 0), (source as Node3D).global_position + Vector3(0, 1, 0), C_TENGRI, 0.25, 0.1)
	boon_hit(source, val("tengri_shock", "dmg"), "tengri", 0.3)
	Sfx.play("thunder", -8.0)


func _discharge(pos: Vector3, dmg: float) -> void:
	WeaponFx.bolt(self, pos + Vector3(0.3, 6, 0.2), pos, C_TENGRI, 0.25, 0.14)
	WeaponFx.ring(self, pos, 2.5, C_TENGRI, 0.3)
	for e in Combat.in_radius(get_tree(), pos, 2.5):
		boon_hit(e, dmg, "tengri", 0.4, [{"id": "shock", "time": 1.0}])
	Sfx.play("thunder", -6.0)


func _spirit_arrows(n: int, dmg: float) -> void:
	var p := _player()
	if p == null:
		return
	var host := WeaponFx.host(self)
	if host == null:
		return
	for i in n:
		var pr := WeaponProjectile.new()
		host.add_child(pr)
		var orb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		orb.mesh = sm
		orb.material_override = WeaponFx.solid(C_AIM, C_AIM, 5.0)
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pr.set_visual(orb)
		var a := TAU * float(i) / float(maxi(1, n)) + rng.randf() * 0.5
		var h := Hit.make(dmg, p, "boon")
		h.no_boons = true
		h.element = "ai_mergen"
		h.pierce_armor = true
		h.tags.append("boon:ai_mergen")
		h.tags.append("projectile")
		pr.launch(p.global_position + Vector3(0, 1.3, 0), Vector3(sin(a), 0, cos(a)), 14.0, h)
		pr.homing = 9.0
		pr.max_dist = 24.0
		pr.radius = 0.4
		pr.stop_on_wall = false
	Sfx.play("shoot_orb", -6.0)


func _fire_trail(a: Vector3, b: Vector3, dmg: float, dps: float) -> void:
	var steps := maxi(2, int(a.distance_to(b) / 0.8))
	for i in steps + 1:
		WeaponFx.flash(self, a.lerp(b, float(i) / steps) + Vector3(0, 0.4, 0), C_UMAI, 1.4, 0.45, WeaponFx.TEX_SOFT)
	for e in Combat.along_line(get_tree(), a + Vector3(0, 0.5, 0), b + Vector3(0, 0.5, 0), 1.0):
		boon_hit(e, dmg, "umai", 0.0, [{"id": "burn", "dps": dps, "time": 3.0}])
	Sfx.play("fire_whoosh", -6.0)


func _fire_wave(pos: Vector3, dmg: float, r: float) -> void:
	WeaponFx.ring(self, pos, r, C_UMAI, 0.35)
	WeaponFx.light_pop(self, pos, C_UMAI, 3.0, r + 2.0, 0.3)
	for e in Combat.in_radius(get_tree(), pos, r):
		var d: Vector3 = (e as Node3D).global_position - pos
		d.y = 0.0
		boon_hit(e, dmg, "umai", 0.0, [{"id": "burn", "dps": dmg * 0.25, "time": 3.0}], d.normalized() * 4.0)
	Sfx.play("fire_whoosh", -2.0)


func _ice_burst(pos: Vector3, t: float) -> void:
	WeaponFx.ring(self, pos, 2.5, C_ZHER, 0.35)
	for e in Combat.in_radius(get_tree(), pos, 2.5):
		if e.has_method("apply_status"):
			e.apply_status("freeze", {"time": t})
		WeaponFx.flash(self, (e as Node3D).global_position + Vector3(0, 1, 0), C_ZHER, 1.5, 0.3)
	Sfx.play("block", -6.0, 0.3)


func _dark_step(a: Vector3, b: Vector3, n: int) -> void:
	for e in Combat.along_line(get_tree(), a + Vector3(0, 0.5, 0), b + Vector3(0, 0.5, 0), 1.0):
		boon_hit(e, 2.0, "erlik", 0.0, [{"id": "poison", "stacks": n}])
		WeaponFx.flash(self, (e as Node3D).global_position + Vector3(0, 1, 0), C_ERLIK, 1.2, 0.3)


func _quake(pos: Vector3, dmg: float) -> void:
	WeaponFx.ring(self, pos, 2.5, C_ZHER, 0.3)
	for e in Combat.in_radius(get_tree(), pos, 2.5):
		var d: Vector3 = (e as Node3D).global_position - pos
		d.y = 0.0
		boon_hit(e, dmg, "zher_su", 0.0, [], d.normalized() * 5.0 + Vector3(0, 2, 0))
	Bus.shake.emit(0.2, 0.12)


func _curse_blast(pos: Vector3, dmg: float, dead: Node) -> void:
	WeaponFx.ring(self, pos, 3.0, C_ERLIK, 0.4)
	WeaponFx.flash(self, pos + Vector3(0, 1, 0), C_ERLIK, 3.0, 0.35)
	WeaponFx.light_pop(self, pos, C_ERLIK, 4.0, 5.0, 0.35)
	for e in Combat.in_radius(get_tree(), pos, 3.0):
		if e == dead:
			continue
		boon_hit(e, dmg, "erlik", 0.0, [{"id": "poison", "stacks": 1}])
	Sfx.play("slam", -4.0)
	Bus.shake.emit(0.3, 0.15)


func _blood_price() -> void:
	var cost := val("erlik_blood", "hp")
	if cost <= 0.0 or Run.hp <= 1.0:
		return
	Run.set_hp(maxf(1.0, Run.hp - cost))
