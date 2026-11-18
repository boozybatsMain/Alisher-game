extends Node3D
## Авто-тест модуля B (оружие + Дары). Headless:
##   godot --headless --path . res://tools/tests/boons_weapons_test.tscn
## Выходит с кодом 0, если всё прошло, иначе 1.

const DUMMY := "res://tools/tests/boons_weapons_dummy.gd"

var fails := 0
var checks := 0
var world: Node3D
var player: Player
var dummies: Array = []
var real_player := false


func ok(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	print("== BoonData / BoonManager")
	_test_data()
	_test_manager()
	print("== Оружие")
	_build_world()
	await get_tree().physics_frame
	await _test_weapons()
	print("== Эффекты Даров в бою")
	await _test_boon_effects()
	print("== Окно выбора и тотем")
	await _test_choice_ui()
	print("BOONS_WEAPONS TEST: checks=%d failed=%d" % [checks, fails])
	get_tree().paused = false
	get_tree().quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- данные
func _test_data() -> void:
	ok(BoonData.GOD_ORDER.size() == 6, "6 духов")
	for g in BoonData.GOD_ORDER:
		var ids := BoonData.boons_of(g)
		var slots := {}
		for id in ids:
			slots[BoonData.slot_of(id)] = true
			var d := BoonData.describe(id, 2, "rare")
			if d == "" or d.contains("{"):
				ok(false, "описание %s: %s" % [id, d])
		ok(ids.size() >= 5, "%s: %d даров" % [g, ids.size()])
		ok(slots.has("attack") and slots.has("special") and slots.has("dash") and slots.has("passive"), "%s: все слоты" % g)
	ok(BoonData.value("tengri_strike", "dmg", 1, "epic") > BoonData.value("tengri_strike", "dmg", 1, "common"), "редкость повышает значения")
	ok(BoonData.value("tengri_strike", "dmg", 3, "common") > BoonData.value("tengri_strike", "dmg", 1, "common"), "уровень повышает значения")
	ok(BoonData.icon("umai_attack") is Texture2D, "процедурная иконка")
	ok(BoonData.icon("nope") == null, "иконка неизвестного дара — null")
	for w in WeaponData.ORDER:
		ok((WeaponData.WEAPONS[w]["aspects"] as Array).size() == Meta.ASPECT_COSTS.size(), "%s: %d аспекта (базовый + 3 платных)" % [w, Meta.ASPECT_COSTS.size()])


func _test_manager() -> void:
	var bm := BoonManager.new()
	add_child(bm)
	for g in BoonData.GOD_ORDER:
		var ch := bm.roll_choices(g, 3)
		var uniq := {}
		var same_god := true
		for c in ch:
			uniq[c["id"]] = true
			same_god = same_god and BoonData.god_of(c["id"]) == g
		ok(ch.size() == 3 and uniq.size() == 3 and same_god, "roll_choices(%s) — 3 уникальных" % g)
	bm.add_boon("tengri_strike")
	ok(bm.has_boon("tengri_strike") and bm.level_of("tengri_strike") == 1, "add_boon")
	bm.add_boon("umai_attack", "rare")
	ok(bm.has_boon("umai_attack") and not bm.has_boon("tengri_strike"), "новый дар заменяет слот attack")
	bm.add_boon("aim_crit")
	bm.add_boon("zher_skin")
	ok(bm.owned().size() == 3, "пассивы копятся (3 дара)")
	ok(bm.stat_bonus("crit_chance") > 0.0, "stat_bonus crit_chance")
	ok(bm.modify_incoming(100.0, null) < 100.0, "каменная кожа уменьшает урон")
	var h := Hit.make(10.0, null, "normal")
	bm.modify_outgoing(h, null)
	var has_burn := false
	for s in h.statuses:
		has_burn = has_burn or s["id"] == "burn"
	ok(has_burn and h.element == "umai", "modify_outgoing: обычная поджигает")
	bm.add_boon("erlik_special")
	var hs := Hit.make(10.0, null, "special")
	bm.modify_outgoing(hs, null)
	ok(hs.amount > 10.0, "modify_outgoing: особая сильнее (Печать Проклятия)")
	var hn := Hit.make(10.0, null, "normal")
	bm.add_boon("zher_attack")
	bm.modify_outgoing(hn, null)
	ok("wall_x2" in hn.tags and hn.knockback.length() > 0.0, "Жер-Су: тег wall_x2 и отбрасывание")
	# улучшение через выбор
	var ups := false
	for i in 10:
		for c in bm.roll_choices("zher_su", 3):
			if c["id"] == "zher_attack":
				ups = ups or (c["upgrade"] and c["level"] == 2)
	ok(ups, "взятый дар предлагается как улучшение")
	bm.level_up("zher_attack")
	ok(bm.level_of("zher_attack") == 2, "level_up")
	var price := bm.remove_boon("zher_attack")
	ok(price > 0 and not bm.has_boon("zher_attack"), "remove_boon → цена %d" % price)
	# дары максимального уровня: улучшение обязано что-то менять (иначе — редкость +1), epic+max не выпадает
	bm.reset()
	for bid in BoonData.boons_of("umai"):
		bm.add_boon(bid, "common", BoonData.MAX_LEVEL)
	var noop := 0
	var total_up := 0
	for i in 200:
		for c in bm.roll_choices("umai", 3):
			if not c["upgrade"]:
				continue
			total_up += 1
			var lv_up: bool = int(c["level"]) > bm.level_of(c["id"])
			var rar_up: bool = BoonData.rarity_index(c["rarity"]) > BoonData.rarity_index(bm.rarity_of(c["id"]))
			if not lv_up and not rar_up:
				noop += 1
	ok(total_up > 0 and noop == 0, "улучшения даров макс. уровня не пустые (%d пустых из %d)" % [noop, total_up])
	for bid in bm.owned():
		bm.add_boon(String(bid["id"]) if bid is Dictionary else String(bid), "epic", BoonData.MAX_LEVEL)
	var maxed_offered := false
	for i in 50:
		for c in bm.roll_choices("umai", 3):
			maxed_offered = maxed_offered or (c["upgrade"] and bm.rarity_of(c["id"]) == "epic" and bm.level_of(c["id"]) >= BoonData.MAX_LEVEL)
	ok(not maxed_offered, "полностью прокачанные (epic, макс. уровень) не предлагаются")
	bm.reset()
	ok(bm.owned().is_empty(), "reset")
	bm.queue_free()


# ---------------------------------------------------------------- мир
func _build_world() -> void:
	world = Node3D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Combat.LAYER_WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(cs)
	world.add_child(floor_body)
	var dl := DirectionalLight3D.new()
	dl.rotation = Vector3(-0.9, 0.5, 0)
	world.add_child(dl)
	var dscript: GDScript = load(DUMMY)
	for i in 8:
		var a := TAU * i / 8.0
		var d: Node3D = dscript.new()
		d.name = "Dummy%d" % i
		world.add_child(d)
		d.global_position = Vector3(sin(a), 0, cos(a)) * 1.6
		dummies.append(d)
	for i in 4:   # дальний ряд для рикошетов и стрел
		var a := TAU * i / 4.0 + 0.4
		var d: Node3D = dscript.new()
		d.name = "Far%d" % i
		world.add_child(d)
		d.global_position = Vector3(sin(a), 0, cos(a)) * 4.5
		dummies.append(d)
	if ResourceLoader.exists(Run.PLAYER_SCENE):
		player = Run.spawn_player(world, Vector3(0, 0.05, 0)) as Player
		real_player = player != null and player.has_method("swap_weapon")
	if player == null:
		player = Player.new()
		world.add_child(player)
	print("  игрок: ", "настоящий player.tscn" if real_player else "заглушка Player")


func _equip(id: String, asp: int) -> WeaponBase:
	if real_player:
		player.call("swap_weapon", id, asp)
	else:
		if player.weapon:
			player.weapon.queue_free()
		var w := WeaponFactory.create(id, asp)
		player.add_child(w)
		w.setup(player, asp)
		player.weapon = w
	return player.weapon


func _reset_dummies() -> void:
	for d in dummies:
		d.reset_stats()


func _sum(key: String, by := "kind") -> float:
	var s := 0.0
	for d in dummies:
		var dict: Dictionary = d.by_kind if by == "kind" else d.by_tag
		s += float(dict.get(key, 0.0))
	return s


func _hit_count() -> int:
	var n := 0
	for d in dummies:
		if d.hits > 0:
			n += 1
	return n


func _wait(secs: float) -> void:
	var t := 0.0
	while t < secs:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		if not real_player and player.weapon:
			player.weapon.tick(dt)


func _reset_player() -> void:
	player.global_position = Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	player.facing = Vector3(0, 0, 1)


func _test_weapons() -> void:
	for id in WeaponData.ORDER:
		for asp in Meta.ASPECT_COSTS.size():
			_reset_player()
			var w := _equip(id, asp)
			await _wait(0.1)
			ok(w != null and w.id == id and w.aspect == asp and w is WeaponBase, "%s/%d создано фабрикой" % [id, asp])
			if w == null:
				continue
			_reset_dummies()
			# обычные атаки
			for i in 6:
				_reset_player()
				w.attack_pressed()
				await _wait(0.62 if id == "bow" else 0.12)
				w.attack_released()
				await _wait(0.3)
			var normal := _sum("normal")
			# особая (+ повторная — возврат/телепорт копья)
			_reset_player()
			w.special_pressed()
			await _wait(0.9 if (id == "sword" and asp == 2) else 0.1)
			w.special_released()
			await _wait(0.05 if (id == "spear" and asp == 2) else 0.9)
			if id == "spear":
				w.special_pressed()
				w.special_released()
				await _wait(1.0)
			if id == "shield":
				await _wait(2.5)
			var special := _sum("special")
			ok(normal > 0.0, "%s/%d: обычная наносит урон (%.0f)" % [id, asp, normal])
			ok(special > 0.0, "%s/%d: особая наносит урон (%.0f)" % [id, asp, special])
			match id:
				"bow":
					ok(_sum("perfect_shot", "tag") > 0.0, "bow/%d: идеальный выстрел" % asp)
					if asp == 2:
						ok(_sum("tostik_split", "tag") > 0.0, "bow/2: стрела Ер Төстіка раскололась")
					if asp == 3:
						ok(_sum("kulamergen", "tag") > 0.0, "bow/3: луч Құламергена")
				"spear":
					if asp == 2:
						ok(_sum("tomiris_blast", "tag") > 0.0, "spear/2: телепорт Томирис со взрывом")
					else:
						ok(_sum("spear_return", "tag") > 0.0, "spear/%d: возврат копья бьёт по пути" % asp)
					ok(w.get("in_hand") == true, "spear/%d: копьё снова в руке" % asp)
				"shield":
					ok(_hit_count() >= 2, "shield/%d: рикошет задел %d целей" % [asp, _hit_count()])
					ok(w.get("in_hand") == true, "shield/%d: щит вернулся" % asp)
					if asp == 2:
						ok(_sum("shield_saw", "tag") > 0.0, "shield/2: жернов Бөгенбая")
				"sword":
					if asp == 1:
						ok(_sum("alpamys_wave", "tag") > 0.0, "sword/1: волна Алпамыса")
					if asp == 2:
						ok(_sum("whirl", "tag") > 18.0, "sword/2: удерживаемый вихрь")
				"gauntlets":
					var launched := false
					for d in dummies:
						launched = launched or d.launched
					ok(launched, "gauntlets/%d: апперкот подбрасывает" % asp)
					if asp == 2:
						ok(int(w.get("fury")) > 0 or _sum("combo5", "tag") > 0.0, "gauntlets/2: ярость Балуана")
					if asp == 3:
						ok(_sum("kambar_wave", "tag") > 0.0, "gauntlets/3: волна Қамбара")
			# блок щитом
			if id == "shield":
				_reset_player()
				w.attack_pressed()
				await _wait(0.9)
				ok(player.blocking, "shield/%d: удержание — блок" % asp)
				if asp == 3:
					_reset_dummies()
					Bus.player_damaged.emit(1.0, null)
					ok(_sum("zhanibek_wave", "tag") > 0.0, "shield/3: ответная волна Ер Жәнібека")
				w.attack_released()
				await _wait(0.05)
				ok(not player.blocking, "shield/%d: отпустил — блок снят" % asp)
			if id == "sword" and asp == 3:
				_reset_dummies()
				_reset_player()
				await _wait(0.5)
				Bus.perfect_dodge.emit(null)
				await _wait(0.1)
				ok(_sum("targyn_counter", "tag") > 0.0, "sword/3: контрудар Ер Тарғына")
			# удар сверху (после отскока от стены)
			_reset_dummies()
			_reset_player()
			await _wait(0.6)
			w.air_special()
			await _wait(0.4)
			ok(_sum("air_slam", "tag") > 0.0, "%s/%d: air_special бьёт под героем" % [id, asp])
			w.cancel()
			# рывок + обычная
			_reset_dummies()
			_reset_player()
			await _wait(0.4)
			w.recovery = 0.0
			w.combo = 0
			w.set("_last_dash", WeaponBase._now())
			w.attack_pressed()
			await _wait(0.1)
			w.attack_released()
			await _wait(0.35)
			ok(_sum("dash_strike", "tag") > 0.0, "%s/%d: рывок + обычная — рывковая атака" % [id, asp])
			w.cancel()
			# прыжок + обычная
			_reset_dummies()
			_reset_player()
			await _wait(0.4)
			player.global_position = Vector3(0, 1.6, 0)
			player.velocity = Vector3.ZERO
			await _wait(0.05)
			w.recovery = 0.0
			w.combo = 0
			w.set("_last_dash", -100.0)
			var was_air := w.airborne()
			w.attack_pressed()
			await _wait(0.1)
			w.attack_released()
			await _wait(0.6)
			ok(was_air and _sum("air_attack" if id != "gauntlets" else "air_combo", "tag") > 0.0,
				"%s/%d: прыжок + обычная — воздушная атака" % [id, asp])
			w.cancel()


func _test_boon_effects() -> void:
	Run.boons.reset()
	_reset_player()
	var w := _equip("sword", 0)
	await _wait(0.6)
	Run.boons.add_boon("tengri_strike", "epic")
	Run.boons.add_boon("kok_frenzy")
	_reset_dummies()
	for i in 3:
		w.attack_pressed()
		w.attack_released()
		await _wait(0.45)
	await _wait(0.2)
	ok(_sum("boon") > 0.0, "Удар Грома: цепная молния бьёт соседей (%.0f)" % _sum("boon"))
	ok(Run.boons.frenzy > 0 and Run.stat("attack_speed_mult") > 1.0, "Охотничий Раж: скорость атаки растёт")
	Run.boons.add_boon("tengri_dash")
	_reset_dummies()
	Bus.player_dashed.emit(Vector3(0, 0, 0), Vector3(0, 0, 3))
	await _wait(0.1)
	ok(_sum("boon") > 0.0, "Шаг Грозы: разряд на месте рывка")
	Run.boons.add_boon("umai_landing")
	_reset_dummies()
	Bus.player_landed.emit(2.0)
	await _wait(0.1)
	ok(_sum("boon:umai", "tag") > 0.0, "Огненная Волна при приземлении")
	Run.boons.add_boon("erlik_blast")
	_reset_dummies()
	dummies[0].statuses["curse"] = {"time": 3.0}
	Bus.enemy_killed.emit(dummies[0], null)
	await _wait(0.1)
	ok(_sum("boon:erlik", "tag") > 0.0, "Взрыв Проклятия при смерти проклятого")
	Run.boons.add_boon("aim_special")
	_reset_dummies()
	w.special_pressed()
	w.special_released()
	await _wait(1.2)
	ok(_sum("boon:ai_mergen", "tag") > 0.0, "Духовные Стрелы при особой")
	Run.boons.reset()


func _test_choice_ui() -> void:
	Run.boons.reset()
	var got := {}
	var w := BoonChoice.open(self, "umai", func(c): got.merge(c))
	await get_tree().process_frame
	ok(w != null and get_tree().paused, "BoonChoice открыт, мир на паузе")
	ok(w != null and w.choices.size() == 3, "3 карточки")
	if ResourceLoader.exists(BoonChoice.UI_KIT):
		ok(w != null and w._root != null and w._root.theme != null, "окно выбора использует тему UiKit")
	if w:
		w.pick(1)
	await get_tree().process_frame
	ok(not get_tree().paused, "после выбора пауза снята")
	ok(got.has("id") and Run.boons.has_boon(got["id"]), "выбранный дар добавлен: %s" % got.get("id", "-"))
	# тотем
	var totem: SpiritTotem = load("res://game/boons/spirit_totem.tscn").instantiate()
	totem.god = "tengri"
	world.add_child(totem)
	totem.global_position = Vector3(5, 0, 5)
	var taken := [false]
	totem.taken.connect(func(_c): taken[0] = true)
	await get_tree().process_frame
	ok(totem.is_in_group("interactable") and totem.can_activate(player), "тотем — interactable")
	totem.activate(player)
	await get_tree().process_frame
	var bc: BoonChoice = null
	for c in get_tree().current_scene.get_children():
		if c is BoonChoice:
			bc = c
	ok(bc != null, "тотем открыл окно выбора")
	if bc:
		bc.pick(0)
	await get_tree().process_frame
	ok(taken[0] and totem.used and not totem.can_activate(player), "тотем: taken и погас")
	Run.boons.reset()
