extends Node
## Авто-тест модуля D (комнаты). godot --headless --path . res://tools/tests/rooms_test.tscn
## 1) RoomPlanner: 50 случайных цепочек забега — всегда 1–2 двери, босс в конце каждого биома, валидные поля.
## 2) ArenaBuilder: каждый шаблон × каждый биом — есть spawn_points (в т.ч. на ярусах), door_slots, точки на полу.
## 3) Формулы: награда Печати Номада растёт с убийствами и временем.
## 4) room.tscn для combat / elite+seal / merchant / duel / boss / rest / финального босса: строится, работает
##    несколько секунд, зачистка → награда → двери; торговец продаёт, колодец покупает дары; Спор Духов — гнев и второй дар.

var fails := 0
var checks := 0


func _ready() -> void:
	if name != "RoomsTestRunner":
		var w: Node = (get_script() as GDScript).new()
		w.name = "RoomsTestRunner"
		get_tree().root.add_child.call_deferred(w)
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("  FAIL: ", msg)


func _run() -> void:
	print("== rooms_test: planner")
	_test_planner()
	print("== rooms_test: arenas")
	await _test_arenas()
	print("== rooms_test: formulas")
	_test_formulas()
	print("== rooms_test: rooms")
	await _test_rooms()
	print("ROOMS TEST DONE: checks=%d failed=%d" % [checks, fails])
	get_tree().quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- планировщик
func _test_planner() -> void:
	var planner := RoomPlanner.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var duels := 0
	var seals := 0
	var merchants := 0
	var elites := 0
	var secrets := 0
	for chain in 50:
		var room := planner.first_room()
		ok(RoomPlanner.validate(room) == "", "first_room: " + RoomPlanner.validate(room))
		ok(int(room["depth"]) == 0 and int(room["biome"]) == 0, "first room depth/biome")
		var bosses := []
		var guard := 0
		while guard < 40:
			guard += 1
			var ch := planner.make_choices(room, rng)
			if int(room["depth"]) >= RoomPlanner.LAST_DEPTH:
				ok(ch.is_empty(), "после финального босса нет дверей")
				break
			ok(ch.size() >= 1 and ch.size() <= 2, "дверей %d на глубине %d" % [ch.size(), int(room["depth"])])
			var next_depth := int(room["depth"]) + 1
			if RoomPlanner.is_boss_depth(next_depth):
				ok(ch.size() == 1 and String(ch[0]["type"]) == "boss", "перед боссом одна дверь-босс (depth %d)" % next_depth)
			if ch.size() == 2:
				var a: Dictionary = ch[0]
				var b: Dictionary = ch[1]
				var same := String(a["type"]) == String(b["type"]) and String(a["reward"]) == String(b["reward"]) and String(a["god"]) == String(b["god"])
				ok(not same, "двери различаются: %s / %s" % [str(a), str(b)])
			for c in ch:
				var err := RoomPlanner.validate(c)
				ok(err == "", "room invalid (%s): %s" % [err, str(c)])
				ok(int(c["depth"]) == next_depth, "depth следующей комнаты")
				match String(c["type"]):
					"duel": duels += 1
					"merchant": merchants += 1
					"elite": elites += 1
				if bool(c["seal"]):
					seals += 1
				if bool(c.get("secret", false)):
					secrets += 1
				ok(String(c["reward"]) != "kui", "видимых дверей с нотой нет (нота — только в тайнике)")
			room = ch[rng.randi_range(0, ch.size() - 1)]
			if String(room["type"]) == "boss":
				bosses.append(int(room["depth"]))
		ok(bosses == [6, 13, 20], "боссы в конце каждого биома: %s" % str(bosses))
	print("   duels=%d merchants=%d elites=%d seals=%d" % [duels, merchants, elites, seals])
	ok(duels > 0 and merchants > 0 and elites > 0 and seals > 0, "встречаются все особые комнаты")
	print("   secrets=%d" % secrets)
	ok(secrets > 0 or RoomPlanner._locked_kuis().is_empty(), "встречаются комнаты с тайным ходом")
	var d0 := RoomPlanner.difficulty(0)
	var d20 := RoomPlanner.difficulty(20)
	ok(float(d20["hp_mult"]) > float(d0["hp_mult"]) and float(d20["dmg_mult"]) > float(d0["dmg_mult"]), "сложность растёт с глубиной")


# ---------------------------------------------------------------- арены
func _test_arenas() -> void:
	var holder := Node3D.new()
	add_child(holder)
	for id in ArenaLayouts.all_ids():
		for b in 3:
			var a := ArenaBuilder.create(holder, String(id), b, 1000 + b * 7)
			var tag := "%s/b%d" % [id, b]
			ok(a.spawn_points.size() >= 6, "%s: spawn_points %d" % [tag, a.spawn_points.size()])
			ok(a.door_slots.size() >= 2, "%s: door_slots" % tag)
			ok(a.bounds.size.x > 10.0, "%s: bounds" % tag)
			ok(a.height_at(a.spawn_player.x, a.spawn_player.z) != -INF, "%s: герой не над пропастью" % tag)
			ok(not a.is_pit(a.reward_point.x, a.reward_point.z, 0.8), "%s: награда не у пропасти" % tag)
			ok(is_equal_approx(a.height_at(a.reward_point.x, a.reward_point.z), a.reward_point.y), "%s: награда на поверхности" % tag)
			for d in a.door_slots:
				ok(a.height_at(d.x, d.z + 1.5) != -INF, "%s: перед дверью есть пол" % tag)
			for p in a.spawn_points:
				ok(not a.is_pit(p.x, p.z, 0.5), "%s: спавн не в пропасти %s" % [tag, str(p)])
			var plats: Array = a.layout.get("plats", [])
			var high := false
			for pl in plats:
				if float(pl[4]) >= 2.9:
					high = true
			if high:
				ok(not a.tier_points(2.9).is_empty(), "%s: есть точки спавна на ярусах" % tag)
			ok(not get_tree().get_nodes_in_group("hurtable_enemy").is_empty() or id == "caravan", "%s: есть разрушаемые объекты" % tag)
			a.queue_free()
			await get_tree().process_frame
	# тайный ход: в каждой боевой раскладке находится место для треснувшей плиты
	for id in ArenaLayouts.COMBAT:
		var a := ArenaBuilder.create(holder, String(id), 1, 555)
		var srng := RandomNumberGenerator.new()
		srng.seed = 7
		var sw := a.add_secret_wall(srng)
		ok(sw != null and sw.kind == "secret_wall" and sw.is_in_group("hurtable_enemy"), "%s: место для тайной плиты" % id)
		if sw:
			var dp: Vector3 = sw.get_meta("door_pos")
			ok(a.height_at(dp.x, dp.z) == 0.0, "%s: тайная дверь на полу" % id)
			sw.take_hit(Hit.make(100.0, null, "normal"))
			ok(sw.is_dead(), "%s: тайная плита разрушается" % id)
		a.queue_free()
		await get_tree().process_frame
	# разрушаемая колонна
	var col := ArenaBreakable.make_column(ArenaBuilder.BIOME_COLORS[0], RoomUtil.mat(Color.GRAY), RoomUtil.mat(Color.CYAN), 5.0)
	holder.add_child(col)
	ok(col.is_in_group("hurtable_enemy") and col.is_in_group("destructible"), "колонна в группах")
	var h := Hit.make(100.0, null, "normal")
	col.take_hit(h)
	ok(col.is_dead(), "колонна разрушена")
	var jar := ArenaBreakable.make_jar(ArenaBuilder.BIOME_COLORS[0], RandomNumberGenerator.new())
	holder.add_child(jar)
	var before := Run.dirhams
	jar.take_hit(Hit.make(5.0, null))
	ok(Run.dirhams > before, "кувшин даёт дирхемы")
	await get_tree().create_timer(0.3).timeout
	holder.queue_free()
	await get_tree().process_frame


func _test_formulas() -> void:
	ok(NomadSeal.reward_for(10, 20.0, 3, false) > NomadSeal.reward_for(10, 0.0, 3, false), "печать: быстрее — больше")
	ok(NomadSeal.reward_for(14, 0.0, 3, false) > NomadSeal.reward_for(5, 0.0, 3, false), "печать: больше убито — больше")
	ok(NomadSeal.reward_for(0, 0.0, 0, true) >= 3, "печать: минимум пепла")
	ok(RoomRewards.price("upgrade", 10) > RoomRewards.price("upgrade", 0), "цены растут с глубиной")
	var ash := RoomRewards.ash_amount(0)
	ok(ash >= 10 and RoomRewards.ash_amount(30) <= 30, "пепел 10–30")


# ---------------------------------------------------------------- комнаты
func _enter(room: Dictionary) -> Node:
	Run.active = true
	Run.hp = Run.max_hp()
	Run.current_room = room
	Run.depth = int(room["depth"])
	Run.biome = int(room["biome"])
	get_tree().change_scene_to_file(Run.ROOM_SCENE)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	return get_tree().current_scene


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs, true, false, true).timeout


func _hold_hp() -> void:
	Run.set_hp(Run.max_hp())


func _test_rooms() -> void:
	var diff := RoomPlanner.difficulty(3)
	# --- combat
	var r: Node = await _enter({"type": "combat", "reward": "ash", "god": "", "god2": "", "depth": 3, "biome": 0, "seed": 11, "seal": false,
		"hp_mult": diff["hp_mult"], "dmg_mult": diff["dmg_mult"]})
	ok(r != null and r.get("arena") != null, "combat: комната построена")
	ok(get_tree().get_first_node_in_group("player") != null, "combat: герой есть")
	ok((r.get("doors") as Array).size() >= 1, "combat: двери созданы")
	ok(not (r.get("doors")[0] as RoomDoor).is_open, "combat: двери заперты")
	await _wait(2.5)
	ok(WaveDirector.group_alive(get_tree()) > 0, "combat: волна врагов появилась")
	for i in 12:
		_hold_hp()
		r.debug_clear()
		await _wait(0.8)
		if String(r.get("state")) != "fight":
			break
	ok(String(r.get("state")) == "reward", "combat: после зачистки — награда (state=%s)" % String(r.get("state")))
	ok(r.get("reward_node") is RewardPickup, "combat: кучка пепла")
	var ash_before := Meta.ash
	r.take_reward_now()
	await _wait(0.2)
	ok(Meta.ash > ash_before, "combat: пепел начислен")
	ok((r.get("doors")[0] as RoomDoor).is_open, "combat: двери открылись")

	# --- тайный ход → тайная комната с Забытой нотой
	var kuis_saved: Array = Meta.kuis_unlocked.duplicate()
	Meta.kuis_unlocked = []
	r = await _enter({"type": "combat", "reward": "ash", "god": "", "god2": "", "depth": 3, "biome": 1, "seed": 23, "seal": false,
		"secret": true, "hp_mult": diff["hp_mult"], "dmg_mult": diff["dmg_mult"]})
	var sw: ArenaBreakable = r.get("secret_wall")
	ok(sw != null, "secret: в комнате есть треснувшая плита")
	if sw:
		sw.take_hit(Hit.make(100.0, null, "normal"))
		await _wait(0.1)
		var sd: RoomDoor = r.get("secret_door")
		ok(sd != null and String(sd.room_data.get("type", "")) == "secret" and String(sd.room_data["reward"]) == "kui",
			"secret: после разрушения — дверь в тайник с нотой")
		ok(sd != null and not sd.is_open, "secret: тайная дверь заперта до зачистки")
		if sd:
			ok(RoomPlanner.validate(sd.room_data) == "", "secret: комната валидна (%s)" % RoomPlanner.validate(sd.room_data))
			r = await _enter(sd.room_data)
			ok(r.get("arena").layout_id == "secret_trial", "secret: раскладка-испытание")
			await _wait(1.0)
			ok(WaveDirector.group_alive(get_tree()) == 0, "secret: врагов нет")
			ok(r.get("reward_node") is RewardPickup and (r.get("reward_node") as RewardPickup).kind == "kui", "secret: награда — нота")
			ok(not (r.get("doors")[0] as RoomDoor).is_open, "secret: двери заперты, пока нота не взята")
			r.take_reward_now()
			await _wait(0.2)
			ok(Meta.kuis_unlocked.size() == 1, "secret: нота открыла кюй")
			ok((r.get("doors")[0] as RoomDoor).is_open, "secret: после ноты двери открылись")
			ok(int((r.get("doors")[0] as RoomDoor).room_data["depth"]) == 4, "secret: дальше — следующая глубина")
	Meta.kuis_unlocked = kuis_saved

	# --- elite + seal
	r = await _enter({"type": "elite", "reward": "gold", "god": "", "god2": "", "depth": 5, "biome": 1, "seed": 99, "seal": true,
		"hp_mult": 1.3, "dmg_mult": 1.2})
	r.set("seal_chance", 1.0)
	for i in 14:
		_hold_hp()
		await _wait(0.8)
		r.debug_clear()
		if String(r.get("state")) != "fight":
			break
	ok(String(r.get("state")) == "reward", "elite: зачищена")
	var seal: NomadSeal = r.get("seal_node")
	ok(seal != null, "elite+seal: появилась Печать Номада")
	if seal:
		var d0 := Run.dirhams
		var a0 := Meta.ash
		seal.begin()
		await _wait(2.0)
		ok(seal.active and seal.spawned_n > 0, "печать: враги появляются")
		r.take_reward_now()
		await _wait(0.1)
		ok(not (r.get("doors")[0] as RoomDoor).is_open, "печать: двери заперты во время испытания")
		seal.time_left = 0.05
		await _wait(0.3)
		ok(seal.done, "печать: испытание завершено")
		ok(Run.dirhams > d0 or Meta.ash > a0, "печать: награда выдана")
		ok((r.get("doors")[0] as RoomDoor).is_open, "печать: двери открылись после испытания")

	# --- merchant
	Run.boons.reset()
	var some := ""
	var bd: Variant = RoomUtil.script_of(RoomUtil.BOON_DATA)
	if bd:
		some = String((bd.boons_of("umai") as Array)[0])
		Run.boons.add_boon(some)
	r = await _enter({"type": "merchant", "reward": "merchant", "god": "", "god2": "", "depth": 5, "biome": 0, "seed": 5, "seal": false})
	ok(String(r.get("state")) == "open", "merchant: двери сразу открыты")
	var m: RoomMerchant = r.get_node_or_null("Merchant")
	ok(m != null and m.goods.size() == 3, "merchant: 3 товара")
	if m:
		Run.dirhams = 0
		Run.add_dirhams(1000)
		Run.set_hp(10.0)
		var food: Node = null
		var upg: Node = null
		for g in m.goods:
			if g.kind == "food":
				food = g
			if g.kind == "upgrade":
				upg = g
		var pl := get_tree().get_first_node_in_group("player")
		food.activate(pl)
		ok(Run.hp > 10.0 and Run.dirhams == 1000 - food.price, "merchant: еда лечит и стоит дирхемы")
		if some != "" and upg:
			var lvl0: int = Run.boons.level_of(some)
			upg.activate(pl)
			ok(Run.boons.level_of(some) == lvl0 + 1, "merchant: улучшение дара")
		Run.dirhams = 0
		var food2 := food as RoomMerchant.ShopItem
		food2.sold = false
		food2.enabled = true
		food2.activate(pl)
		ok(not food2.sold, "merchant: без денег не продаёт")
		if some != "":
			var d1 := Run.dirhams
			var got: int = (m.well as RoomMerchant.ExchangeWell).sell(some)
			ok(got > 0 and Run.dirhams == d1 + got and not Run.boons.has_boon(some), "колодец: продажа дара")
			# окно колодца
			Run.boons.add_boon(some)
			var win: RoomUi = (m.well as RoomMerchant.ExchangeWell).open_window()
			ok(win != null and get_tree().paused, "колодец: окно открыто, мир на паузе")
			await get_tree().process_frame
			if win:
				win.close()
			await get_tree().process_frame
			ok(not get_tree().paused, "колодец: окно закрыто, пауза снята")

	# --- duel
	r = await _enter({"type": "duel", "reward": "boon", "god": "tengri", "god2": "erlik", "depth": 4, "biome": 1, "seed": 31, "seal": false,
		"hp_mult": 1.2, "dmg_mult": 1.1})
	var totems: Array = r.get("totems")
	ok(totems.size() == 2, "duel: два тотема")
	if totems.size() == 2:
		var pl := get_tree().get_first_node_in_group("player")
		totems[0].activate(pl)
		await get_tree().process_frame
		_pick_boon_choice()
		await _wait(0.3)
		ok(String(r.get("state")) == "fight", "duel: отвергнутый дух гневается (волна)")
		ok(not bool(totems[1].get("enabled")), "duel: второй тотем погас")
		await _wait(1.5)
		var elem_ok := false
		for e in get_tree().get_nodes_in_group("enemies"):
			if String(e.get("element")) == "erlik":
				elem_ok = true
		ok(elem_ok, "duel: враги со стихией отвергнутого духа")
		for i in 14:
			_hold_hp()
			r.debug_clear()
			await _wait(0.8)
			if String(r.get("state")) != "fight":
				break
		ok(bool(totems[1].get("enabled")), "duel: второй тотем снова доступен")
		totems[1].activate(pl)
		await get_tree().process_frame
		_pick_boon_choice()
		await _wait(0.3)
		ok((r.get("doors")[0] as RoomDoor).is_open, "duel: двери открылись после второго дара")

	# --- rest
	r = await _enter({"type": "rest", "reward": "heal", "god": "", "god2": "", "depth": 9, "biome": 1, "seed": 3, "seal": false})
	ok(r.get("reward_node") is RewardPickup and String(r.get("state")) == "open", "rest: родник и открытые двери")

	# --- boss (биом 0)
	var kb := int(Meta.stats.get("boss_kills", 0))
	r = await _enter({"type": "boss", "reward": "ash", "god": "", "god2": "", "depth": 6, "biome": 0, "seed": 66, "seal": false})
	await _wait(2.0)
	ok(r.get("boss") != null, "boss: босс появился")
	ok(get_tree().get_first_node_in_group("boss_bar") != null, "boss: полоса босса")
	for i in 10:
		_hold_hp()
		r.debug_clear()
		await _wait(0.6)
		if String(r.get("state")) != "fight":
			break
	ok(String(r.get("state")) == "reward", "boss: побеждён")
	ok(int(Meta.stats["boss_kills"]) == kb + 1, "boss: Meta.stats.boss_kills")
	var doors: Array = r.get("doors")
	ok(doors.size() >= 1 and int((doors[0] as RoomDoor).room_data["biome"]) == 1, "boss: двери ведут в следующий биом")
	r.take_reward_now()
	await _wait(0.2)
	ok((doors[0] as RoomDoor).is_open, "boss: двери открылись после пепла")
	# вход в дверь меняет комнату
	(doors[0] as RoomDoor).activate(get_tree().get_first_node_in_group("player"))
	await _wait(0.6)
	ok(int(Run.current_room.get("biome", -1)) == 1 and get_tree().current_scene != r, "дверь: переход в следующую комнату")

	# --- финальный босс
	r = await _enter({"type": "boss", "reward": "ash", "god": "", "god2": "", "depth": 20, "biome": 2, "seed": 67, "seal": false})
	ok((r.get("doors") as Array).is_empty(), "финал: нет дверей")
	await _wait(2.0)
	for i in 10:
		_hold_hp()
		r.debug_clear()
		await _wait(0.6)
		if String(r.get("state")) != "fight":
			break
	ok(String(r.get("state")) == "victory", "финал: победа")
	# смерть в окне победы не превращает победу в поражение
	var deaths0 := int(Meta.stats["deaths"])
	var vict0 := int(Meta.stats["victories"])
	ok(Run.victory_pending, "финал: окно победы — Run.victory_pending")
	var pl := get_tree().get_first_node_in_group("player")
	ok(pl != null and pl.invulnerable(), "финал: герой неуязвим до перехода в Хаб")
	Run.revives_left = 0
	ok(Run.on_player_death("test") == true and Run.active, "финал: смерть в окне победы не завершает забег")
	# финальный диалог: пока он открыт, переход в Хаб не начинается (таймер победы ждёт closed)
	if DialogueBox.is_open():
		await _wait(5.8)
		ok(Run.active and DialogueBox.is_open(), "финал: открытый диалог не обрывается переходом в Хаб")
		DialogueBox.ensure(get_tree()).close()
	await _wait(4.0)
	ok(not Run.active and Run.hub_reason == "victory", "финал: Run.end_run(победа) → Хаб")
	Run.end_run(true, "late")
	ok(int(Meta.stats["deaths"]) == deaths0 and int(Meta.stats["victories"]) == vict0 + 1 and not bool(Meta.last_run.get("died", true)),
		"финал: повторный end_run игнорируется (смертей +0, побед +1)")


func _pick_boon_choice() -> void:
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if n.has_method("pick") and n.is_inside_tree():
			n.pick(0)
			return
