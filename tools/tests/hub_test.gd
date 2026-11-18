extends Node
## Авто-тест модуля E (Хаб). godot --headless --path . res://tools/tests/hub_test.tscn
## Проверяет: Story (первый запуск / смерть / победа над ханом), загрузку hub.tscn (change_scene), 5 стоек,
## манекен (hurtable_enemy, не enemies, DPS > 0, не умирает), Сандык (Meta.buy_chest), оружейную (открыть/взять),
## режим домбры: кюй «Адай» с идеальным таймингом → Meta.kui_prepared == "adai"; ошибка — сброс.
## Работает с тестовым сейвом Meta.save_path (user://tamyr_test_save.json) — сейв игрока не трогается.

var SAVE: String = Meta.save_path   ## тестовый сейв (Meta: сцены из res://tools/ не трогают сейв игрока)

var _fails := 0
var _passes := 0
var _backup = null
var _kills := 0


func _ready() -> void:
	if name != "HubTestRunner":
		var r: Node = (get_script() as GDScript).new()
		r.name = "HubTestRunner"
		get_tree().root.add_child.call_deferred(r)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func ok(cond: bool, what: String) -> void:
	if cond:
		_passes += 1
		print("  PASS ", what)
	else:
		_fails += 1
		print("  FAIL ", what)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs, true).timeout


func _run() -> void:
	if FileAccess.file_exists(SAVE):
		_backup = FileAccess.get_file_as_string(SAVE)
	Bus.enemy_killed.connect(func(_e, _h): _kills += 1)
	print("== HUB TEST ==")
	_test_story()
	_test_kui_data()
	# --- сцена Хаба
	Meta.reset_save()
	Meta.story["seen"] = ["intro"]     # без вступительного диалога (он ставит мир на паузу)
	Meta.story["step"] = 1
	Run.hub_reason = ""
	get_tree().change_scene_to_file("res://game/hub/hub.tscn")
	await _wait(1.5)
	var hub: Node = get_tree().current_scene
	ok(hub != null and hub.scene_file_path == "res://game/hub/hub.tscn", "hub.tscn загружен")
	if hub == null:
		_finish()
		return
	ok(not Run.active, "Run.active == false в Хабе")
	var racks: Array = hub.get("racks")
	ok(racks.size() == 5, "5 стоек оружия (%d)" % racks.size())
	var ids := []
	for r in racks:
		ids.append(r.weapon_id)
	ok(ids == ["sword", "spear", "shield", "bow", "gauntlets"], "стойки: меч, копьё, щит, лук, перчатки")
	ok(get_tree().get_nodes_in_group("player").size() == 1, "герой заспавнен")
	ok(get_viewport().get_camera_3d() != null, "есть камера")
	await _test_dummy(hub)
	await _test_chest(hub)
	await _test_armory(hub)
	await _test_dombra(hub)
	ok(hub.get("gate") is Interactable, "выход на тропу — Interactable")
	ok((hub.get("npcs") as Dictionary).size() >= 2, "NPC в хабе: %d" % (hub.get("npcs") as Dictionary).size())
	_finish()


func _test_story() -> void:
	print("-- Story")
	Meta.reset_save()
	Run.hub_reason = ""
	var l1 := Story.on_hub_enter()
	ok(l1.size() >= 3, "первый запуск: вступление (%d реплик)" % l1.size())
	ok(l1.size() > 0 and l1[0].has("speaker") and l1[0].has("text"), "формат реплик {speaker, text}")
	ok("adai" in Meta.kuis_unlocked, "Әже дарит кюй «Адай»")
	ok(Story.on_hub_enter().is_empty(), "повторный вход без события — тишина")
	Run.hub_reason = "death"
	Meta.last_run = {"died": true, "depth": 3, "biome": 0, "killer": "wolf", "boss": ""}
	var l2 := Story.on_hub_enter()
	ok(l2.size() >= 2, "смерть: сценка (%d реплик)" % l2.size())
	var txt := ""
	for l in l2:
		txt += str(l["text"])
	ok(txt.contains("Волки"), "смерть: реплика про убийцу (волк)")
	ok("roots_first" in Meta.story["seen"], "смерть: шаг сюжета roots_first")
	ok(Run.hub_reason == "", "hub_reason сброшен после сценки")
	# три смерти подряд → намёки, потом находка в биоме 1
	for i in 2:
		Run.hub_reason = "death"
		Story.on_hub_enter()
	ok("hint_wound" in Meta.story["seen"], "намёки идут по порядку (hint_wound)")
	Run.hub_reason = "death"
	Meta.last_run = {"died": true, "depth": 7, "biome": 1, "killer": "shoyyn", "boss": ""}
	Story.on_hub_enter()
	ok("find_tamga" in Meta.story["seen"], "находка тамги после биома 1")
	Run.hub_reason = "victory"
	Meta.last_run = {"died": false, "depth": 14, "biome": 2, "killer": "", "boss": "khan"}
	var l3 := Story.on_hub_enter()
	var t3 := ""
	for l in l3:
		t3 += str(l["text"])
	ok(l3.size() >= 4 and t3.contains("впустил Мглу"), "победа над ханом: признание")
	ok(int(Meta.story["step"]) >= 8, "шаг сюжета после признания: %d" % int(Meta.story["step"]))
	for npc in ["aje", "root", "usta"]:
		ok(not Story.talk(npc).is_empty(), "разговор с NPC %s" % npc)
	# чистые функции выбора
	var st := {"step": 0, "seen": [], "reason": "", "last_run": {}}
	ok(Story.pick_scene(st) == "intro", "pick_scene: первый запуск → intro")
	st = {"step": 1, "seen": ["intro"], "reason": "death", "last_run": {"killer": "archer"}}
	ok(Story.pick_scene(st) == "roots_first", "pick_scene: первая смерть → roots_first")
	st = {"step": 2, "seen": ["intro", "roots_first"], "reason": "victory", "last_run": {"boss": "khan"}}
	ok(Story.pick_scene(st) == "khan_confession", "pick_scene: победа над ханом → признание")


func _test_kui_data() -> void:
	print("-- KuiData")
	for id in Run.KUIS:
		ok(KuiData.has(id), "кюй %s есть в KuiData" % id)
		var beats := 0.0
		for n in KuiData.notes(id):
			beats = maxf(beats, float(n["beat"]))
			assert(int(n["fret"]) >= 0 and int(n["fret"]) <= 6)
		ok(beats >= 8.0 and beats < 16.0, "кюй %s: 3–4 такта" % id)
	Meta.kuis_unlocked = []
	ok(KuiData.available() == ["adai"], "без открытых кюев доступен «Адай»")


func _test_dummy(hub: Node) -> void:
	print("-- Манекен")
	var d: Node = hub.get("dummy")
	ok(d != null, "манекен есть")
	if d == null:
		return
	ok(d.is_in_group("hurtable_enemy"), "манекен в группе hurtable_enemy")
	ok(not d.is_in_group("enemies"), "манекен НЕ в группе enemies")
	ok(d.get("hit_radius") != null and float(d.hit_radius) > 0.0, "hit_radius")
	var p: Node3D = get_tree().get_first_node_in_group("player")
	var landed := [0]
	var cb := func(_h, t): if t == d: landed[0] += 1
	Bus.hit_landed.connect(cb)
	var h1 := Hit.make(20.0, p, "normal")
	h1.knockback = Vector3(4, 0, 0)
	d.take_hit(h1)
	var h2 := Hit.make(35.0, p, "special")
	h2.stun = 1.0
	h2.launch = true
	d.take_hit(h2)
	var h3 := Hit.make(15.0, p, "normal")
	h3.is_crit = true
	h3.statuses = [{"id": "burn", "dps": 6.0, "time": 2.0}]
	d.take_hit(h3)
	var h4 := Hit.make(10.0, p, "normal")
	Combat.player_hit(d, h4)  # Run.modify_outgoing может случайно дать крит (3%)
	ok(landed[0] == 4, "Bus.hit_landed от манекена (%d)" % landed[0])
	ok(d.last_kind == ("crit" if h4.is_crit else "normal"), "тип последней атаки (%s)" % d.last_kind)
	ok(d.dps() > 0.0, "DPS > 0 (%.1f)" % d.dps())
	ok(d.statuses.has("burn") and d.statuses.has("stun"), "статусы burn/stun на манекене")
	var huge := Hit.make(99999.0, p, "normal")
	d.take_hit(huge)
	await _wait(0.6)
	ok(is_instance_valid(d) and d.is_inside_tree() and not d.is_dead(), "манекен бессмертен")
	ok(_kills == 0, "манекен не шлёт enemy_killed")
	ok(d.get_facing() is Vector3, "get_facing()")
	ok(d.total_window() >= 99999.0, "окно 5 с копит урон")
	Bus.hit_landed.disconnect(cb)


func _test_chest(hub: Node) -> void:
	print("-- Сандык")
	Meta.ash = 0
	Meta.add_ash(100)
	var before: int = Meta.chest["blood"]
	ok(Meta.buy_chest("blood"), "Meta.buy_chest(blood)")
	ok(Meta.chest["blood"] == before + 1 and Meta.ash == 90, "уровень +1, пепел списан (%d)" % Meta.ash)
	var p: Node = get_tree().get_first_node_in_group("player")
	var w := ChestWindow.new()
	w.open_on(hub, p)
	await _wait(0.1)
	ok(w.body.get_child_count() >= 5 + 3, "окно Сандыка: 5 улучшений")
	w._buy("shadow")
	ok(Meta.chest["shadow"] == 1, "покупка через окно (Тень Степи)")
	ok(p.get("input_enabled") == false, "окно блокирует управление героем")
	w.close()
	await _wait(0.4)
	ok(p.get("input_enabled") == true, "после закрытия управление вернулось")
	ok(hub.get("chest") is AncestorChest, "Сандык в юрте")


func _test_armory(hub: Node) -> void:
	print("-- Оружейная")
	Meta.ash = 0
	Meta.add_ash(500)
	var p: Node = get_tree().get_first_node_in_group("player")
	var w := ArmoryWindow.new()
	w.weapon_id = "spear"
	w.open_on(hub, p)
	await _wait(0.1)
	w._unlock()
	ok(Meta.weapons_unlocked.get("spear", false), "копьё открыто за пепел")
	ok(Meta.equipped_weapon == "spear", "копьё взято")
	await _wait(0.1)
	var pw = p.get("weapon")
	if pw != null:
		ok(str(pw.id) == "spear", "герой мгновенно сменил оружие (%s)" % str(pw.id))
	w._unlock_aspect(2)
	ok(2 in Meta.aspects_unlocked["spear"] and Meta.equipped_aspect == 2, "аспект Томирис открыт и выбран")
	w._choose(0)
	ok(Meta.equipped_aspect == 0, "выбор аспекта 0")
	w.close()
	await _wait(0.3)


func _test_dombra(hub: Node) -> void:
	print("-- Домбра")
	Meta.kui_prepared = ""
	Meta.kuis_unlocked = []
	var m: DombraMode = hub.open_dombra()
	await _wait(0.5)
	ok(m != null and is_instance_valid(m), "режим домбры открыт")
	ok(get_viewport().get_camera_3d() != null and get_viewport().get_camera_3d().name == "DombraCam", "крупный план — своя камера")
	# свободная игра: пул голосов без обрыва
	m.set_fret(3)
	m.strike("down")
	m.strike("up")
	await _wait(0.1)
	var playing := 0
	for s in ["upper", "lower"]:
		for v in m._voices[s]:
			if (v as AudioStreamPlayer).playing:
				playing += 1
	ok(playing >= 3, "звучат несколько голосов одновременно (%d)" % playing)
	ok(m._streams["upper"][0] != null and m._streams["lower"][6] != null, "сэмплы домбры загружены")
	ok(m.model.current_fret == 3, "левая рука на 3-м ладу")
	# ошибка: не тот удар
	m.begin_kui("adai")
	m.song_time = KuiData.note_time("adai", 0)
	m.set_fret(0)
	m.strike("up")
	ok(m.errors == 1 and Meta.kui_prepared == "", "ошибка сбрасывает кюй")
	# идеальное исполнение
	m.begin_kui("adai")
	var ns := KuiData.notes("adai")
	for i in ns.size():
		m.song_time = KuiData.note_time("adai", i) + (0.05 if i % 2 == 0 else -0.05)
		m.set_fret(int(ns[i]["fret"]))
		m.strike(str(ns[i]["stroke"]))
	ok(m.errors == 0, "кюй без ошибок")
	ok(Meta.kui_prepared == "adai", "Meta.kui_prepared == adai")
	var saved := FileAccess.get_file_as_string(SAVE)
	ok(saved.contains("\"kui_prepared\": \"adai\""), "кюй сохранён в сейв")
	m.close()
	await _wait(1.2)
	ok(hub.get("dombra_mode") == null, "режим домбры закрыт")
	var p: Node = get_tree().get_first_node_in_group("player")
	ok(p.get("input_enabled") == true, "герой снова управляем")


func _finish() -> void:
	if _backup != null:
		var f := FileAccess.open(SAVE, FileAccess.WRITE)
		if f:
			f.store_string(_backup)
			f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("HUB TEST: %d passed, %d failed -> %s" % [_passes, _fails, "PASS" if _fails == 0 else "FAIL"])
	get_tree().quit(0 if _fails == 0 else 1)
