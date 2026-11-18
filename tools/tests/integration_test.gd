extends Node
## Интеграционный тест стыков модулей (A↔B↔C↔D↔E).
## godot --headless --path . res://tools/tests/integration_test.tscn
## 1) герой ↔ оружие: WeaponFactory создаёт настоящие оружия, ввод attack/special доходит до оружия;
## 2) оружие ↔ враг/HUD: Combat.player_hit → take_hit, HUD рисует числа урона (Label3D);
## 3) Дары ↔ Bus: эффекты реально срабатывают в бою (горение Умай, цепная молния Тенгри, рывок);
## 4) Хаб: Meta.equip → Bus.weapon_changed → герой меняет оружие;
## 5) кюи: Meta.kui_prepared → Run.start_run → Run.kui → stat / slowmo при идеальном уклонении;
## 6) смерть: Клятва (воскрешение) → вторая смерть → Хаб, hub_reason "death", диалог Story в DialogueBox.

var fails := 0
var checks := 0
var _save_backup := ""
var arena: Node3D


func _ready() -> void:
	if name != "IntegrationRunner":
		var w: Node = (get_script() as GDScript).new()
		w.name = "IntegrationRunner"
		get_tree().root.add_child.call_deferred(w)
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func ok(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	if FileAccess.file_exists(Meta.save_path):
		_save_backup = FileAccess.get_file_as_string(Meta.save_path)
	Meta.reset_save()
	await _test_weapons_and_enemies()
	await _test_boons()
	await _test_kui()
	await _test_hub_equip()
	await _test_death()
	_restore_save()
	print("INTEGRATION TEST: checks=%d failed=%d -> %s" % [checks, fails, "PASS" if fails == 0 else "FAIL"])
	get_tree().quit(1 if fails > 0 else 0)


func _restore_save() -> void:
	if _save_backup != "":
		var f := FileAccess.open(Meta.save_path, FileAccess.WRITE)
		f.store_string(_save_backup)
		f.close()
		Meta.load_game()
	else:
		Meta.reset_save()


# ---------------------------------------------------------------- арена
func _make_arena() -> Node3D:
	if arena and is_instance_valid(arena):
		arena.queue_free()
		await get_tree().process_frame
	var old := get_tree().current_scene
	arena = Node3D.new()
	arena.name = "TestArena"
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	if old and old != arena and is_instance_valid(old):
		old.queue_free()
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Combat.LAYER_WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	arena.add_child(floor_body)
	return arena


func _spawn_enemy(type_id: String, pos: Vector3, mods := {}) -> EnemyBase:
	var m := {"no_fx": true, "spawn_delay": 0.05, "music": false}
	m.merge(mods, true)
	var e := EnemyFactory.spawn(type_id, arena, pos, m)
	await _wait(0.2)
	return e


# ---------------------------------------------------------------- 1–2. оружие ↔ враги ↔ HUD
func _test_weapons_and_enemies() -> void:
	print("== герой ↔ оружие ↔ враги ↔ HUD")
	Run.start_run.call_deferred()   # смена сцены на room.tscn — сразу заменим тестовой ареной
	await _wait(0.5)
	await _make_arena()
	Run.active = true
	Run.hp = Run.max_hp()
	var p: Player = Run.spawn_player(arena, Vector3(0, 0.1, 0)) as Player
	Run.spawn_hud(arena)
	await _frames(4)
	ok(get_viewport().get_camera_3d() is GameCamera, "герой сам подключил GameCamera")
	ok(Hud.find(get_tree()) != null, "HUD заспавнен")
	var expected := {"sword": "sword.gd", "spear": "spear.gd", "shield": "shield.gd", "bow": "bow.gd", "gauntlets": "gauntlets.gd"}
	for id in expected:
		p.swap_weapon(id, 0)
		await _frames(2)
		var w := p.weapon
		ok(w != null and w.id == id and str(w.get_script().resource_path).ends_with(expected[id]), "%s: WeaponFactory создал настоящее оружие" % id)
		p.teleport_to(Vector3(0, 0.1, 0))
		p.velocity = Vector3.ZERO
		p.facing = Vector3(1, 0, 0)
		var e := await _spawn_enemy("balbal", Vector3(2.0 if id != "bow" else 5.0, 0, 0), {"hp_mult": 50.0})
		e.apply_status("stun", {"time": 60.0})   # манекен-враг: не бьёт и не уходит
		Run.hp = Run.max_hp()
		var hp0 := e.hp + e.armor
		var labels := [0]
		var lcb := func(n: Node): if n is Label3D: labels[0] += 1
		get_tree().node_added.connect(lcb)
		var dn := [0]
		var cb := func(_pos, _a, _k): dn[0] += 1
		Bus.damage_number.connect(cb)
		# ввод: обычная атака (лук — натяжение и отпуск)
		for k in 3:
			Input.action_press("attack")
			await _frames(2)
			if id == "bow":
				await _wait(0.6)
			Input.action_release("attack")
			await _wait(0.45)
		await _wait(0.5)
		var hp1 := e.hp + e.armor
		ok(hp1 < hp0, "%s: атака по вводу «attack» ранила врага (%.0f → %.0f)" % [id, hp0, hp1])
		Input.action_press("special")
		await _frames(3)
		Input.action_release("special")
		await _wait(1.6)
		if id in ["spear", "shield"]:   # бросок — вернуть оружие
			Input.action_press("special")
			await _frames(2)
			Input.action_release("special")
			await _wait(1.2)
		ok(e.hp + e.armor < hp1 or e.is_dead(), "%s: особая по вводу «special» ранила врага" % id)
		Bus.damage_number.disconnect(cb)
		get_tree().node_added.disconnect(lcb)
		ok(dn[0] > 0, "%s: Bus.damage_number от врага (%d)" % [id, dn[0]])
		ok(labels[0] >= dn[0], "%s: HUD нарисовал числа урона (Label3D %d на %d чисел)" % [id, labels[0], dn[0]])
		if is_instance_valid(e):
			e.queue_free()
		await _frames(2)
	# Combat.player_hit → take_hit напрямую, крупный удар убивает и шлёт enemy_killed
	var e2 := await _spawn_enemy("wolf", Vector3(3, 0, 0))
	var killed := [false]
	var kcb := func(en, _h): if en == e2: killed[0] = true
	Bus.enemy_killed.connect(kcb)
	var k0 := Run.kills
	var big := Hit.make(9999.0, p, "normal")
	Combat.player_hit(e2, big)
	await _frames(2)
	Bus.enemy_killed.disconnect(kcb)
	ok(killed[0] and e2.is_dead() and Run.kills == k0 + 1, "Combat.player_hit → take_hit → enemy_killed + Run.register_kill")
	await _wait(0.3)


# ---------------------------------------------------------------- 3. Дары ↔ Bus
func _test_boons() -> void:
	print("== Дары ↔ Bus")
	var p: Player = get_tree().get_first_node_in_group("player")
	Run.boons.reset()
	# Умай: обычные атаки поджигают
	Run.boons.add_boon("umai_attack")
	ok(Run.boons.has_boon("umai_attack"), "дар добавлен в Run.boons")
	var e := await _spawn_enemy("balbal", Vector3(2, 0, 0), {"hp_mult": 20.0})
	var h := Hit.make(5.0, p, "normal")
	h.tags.append("weapon:sword")
	Combat.player_hit(e, h)
	await _frames(3)
	ok(e.statuses.has("burn"), "Умай: удар поджёг врага (statuses=%s)" % str(e.statuses.keys()))
	# Тенгри: цепная молния на соседей (через Bus.hit_landed)
	Run.boons.reset()
	Run.boons.add_boon("tengri_strike")
	var e3 := await _spawn_enemy("balbal", Vector3(3.5, 0, 0), {"hp_mult": 20.0})
	var boon_hits := [0]
	var cb := func(hit: Hit, _t): if hit.kind == "boon": boon_hits[0] += 1
	Bus.hit_landed.connect(cb)
	var hp3 := e3.hp + e3.armor
	var h2 := Hit.make(5.0, p, "normal")
	Combat.player_hit(e, h2)
	await _wait(0.3)
	Bus.hit_landed.disconnect(cb)
	ok(boon_hits[0] > 0 and e3.hp + e3.armor < hp3, "Тенгри: цепная молния ударила соседа (boon hits %d)" % boon_hits[0])
	# Тенгри: разряд на месте рывка по Bus.player_dashed
	Run.boons.reset()
	Run.boons.add_boon("tengri_dash")
	var hp_e := e.hp + e.armor
	Bus.player_dashed.emit(Vector3(1.5, 0, 0), Vector3(2, 0, 0))
	await _wait(0.3)
	ok(e.hp + e.armor < hp_e, "Тенгри: Bus.player_dashed → разряд на месте рывка")
	# stat_bonus доходит до Run.stat
	Run.boons.reset()
	var cc0 := Run.stat("crit_chance")
	Run.boons.add_boon("aim_crit")
	ok(Run.stat("crit_chance") > cc0, "Ай-Мерген: stat_bonus крит → Run.stat (%.2f → %.2f)" % [cc0, Run.stat("crit_chance")])
	Run.boons.reset()
	for n in [e, e3]:
		if is_instance_valid(n):
			n.queue_free()
	await _frames(2)


# ---------------------------------------------------------------- 5. кюи
func _test_kui() -> void:
	print("== домбра → кюй → забег")
	Meta.unlock_kui("adai")
	Meta.kui_prepared = "adai"
	Run.start_run()
	ok(Run.kui == "adai" and Meta.kui_prepared == "", "Run.start_run забрал Meta.kui_prepared → Run.kui")
	ok(is_equal_approx(Run.stat("dash_speed_mult"), 1.15), "Адай: dash_speed_mult = %.2f" % Run.stat("dash_speed_mult"))
	await _wait(1.0)
	ok(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == Run.ROOM_SCENE, "старт забега → room.tscn")
	# Қорқыт: идеальное уклонение → slowmo
	await _make_arena()
	Run.kui = "korkyt"
	var p: Player = Run.spawn_player(arena, Vector3(0, 0.1, 0)) as Player
	await _frames(4)
	var attacker := await _spawn_enemy("wolf", Vector3(4, 0, 0))
	Input.action_press("move_right")
	Input.action_press("dash")
	await _frames(3)
	Input.action_release("dash")
	Input.action_release("move_right")
	ok(p.is_dashing(), "рывок по вводу «dash»")
	var pd := [false]
	var cb := func(_a): pd[0] = true
	Bus.perfect_dodge.connect(cb)
	var hp0 := Run.hp
	p.take_hit(Hit.make(20.0, attacker, "normal"))
	Bus.perfect_dodge.disconnect(cb)
	ok(pd[0] and Run.hp == hp0, "удар во время рывка → perfect_dodge, урона нет")
	ok(Engine.time_scale < 0.5, "Қорқыт: идеальное уклонение замедлило время (%.2f)" % Engine.time_scale)
	await _wait(1.3)
	ok(is_equal_approx(Engine.time_scale, 1.0), "время вернулось к 1.0")
	Run.kui = ""
	attacker.queue_free()


# ---------------------------------------------------------------- 4. Хаб ↔ оружейная
func _test_hub_equip() -> void:
	print("== Хаб ↔ оружейная ↔ Meta.equip ↔ герой")
	Run.goto_hub()
	await _wait(1.0)
	var hub := get_tree().current_scene
	ok(hub != null and hub.scene_file_path == Run.HUB_SCENE, "Run.goto_hub → hub.tscn")
	ok(not Run.active, "в Хабе Run.active == false")
	_close_dialogue()
	var p: Player = get_tree().get_first_node_in_group("player")
	Meta.ash = 9999
	ok(Meta.unlock_weapon("spear"), "открыли копьё за пепел")
	Meta.equip("spear", 0)
	await _frames(2)
	ok(p.weapon != null and p.weapon.id == "spear", "Meta.equip → Bus.weapon_changed → у героя копьё")
	Meta.unlock_aspect("spear", 1)
	Meta.equip("spear", 1)
	await _frames(2)
	ok(p.weapon.aspect == 1, "аспект сменился на 1")
	Meta.equip("sword", 0)
	await _frames(2)
	ok(p.weapon.id == "sword", "вернули меч")
	# манекен получает удар оружием
	var dummy: Node = hub.get("dummy")
	if dummy:
		var hc: int = dummy.hits_count
		Combat.player_hit(dummy, Hit.make(10.0, p, "normal"))
		ok(dummy.hits_count == hc + 1, "манекен принял удар через Combat.player_hit")


func _close_dialogue() -> void:
	for i in 40:
		if not DialogueBox.is_open():
			return
		var d := DialogueBox.ensure(get_tree())
		d.advance()
		d.advance()


# ---------------------------------------------------------------- 6. смерть
func _test_death() -> void:
	print("== смерть → Клятва → Хаб + Story")
	Meta.chest["oath"] = 1
	Run.start_run()
	ok(Run.revives_left == 1, "Клятва Жизни: revives_left = 1")
	await _wait(1.5)
	var room := get_tree().current_scene
	ok(room and room.scene_file_path == Run.ROOM_SCENE, "комната загружена")
	var p: Player = get_tree().get_first_node_in_group("player")
	var revived := [false]
	var cb := func(_c): revived[0] = true
	Bus.player_revived.connect(cb)
	await _wait(0.6)
	var killer := Node3D.new()
	killer.name = "wolf"
	room.add_child(killer)
	killer.set("type_id", "wolf")
	p._iframes = 0.0
	p.take_hit(Hit.make(99999.0, killer, "normal"))
	await _frames(3)
	Bus.player_revived.disconnect(cb)
	ok(revived[0] and Run.hp > 0.0 and Run.active, "первая смерть → воскрешение (hp %.0f)" % Run.hp)
	for k in 60:   # после воскрешения герой неуязвим ~2 с
		if not p.invulnerable():
			break
		await _wait(0.1)
	ok(not p.invulnerable(), "неуязвимость после воскрешения закончилась")
	var died := [false]
	var dcb := func(): died[0] = true
	Bus.player_died.connect(dcb)
	p.take_hit(Hit.make(99999.0, killer, "normal"))
	await _frames(3)
	Bus.player_died.disconnect(dcb)
	ok(died[0] and not Run.active, "вторая смерть → Bus.player_died, забег окончен")
	ok(int(Meta.stats["deaths"]) >= 1 and Run.hub_reason == "death", "Meta.stats.deaths и hub_reason = death")
	await _wait(2.0)
	var hub := get_tree().current_scene
	ok(hub and hub.scene_file_path == Run.HUB_SCENE, "после смерти — Хаб")
	await _wait(1.5)
	ok(DialogueBox.is_open(), "в Хабе Story показала диалог через DialogueBox")
	ok(Run.hub_reason == "", "Story.on_hub_enter обнулил hub_reason")
	_close_dialogue()
	await _frames(2)
	ok(not get_tree().paused, "после диалога пауза снята")
	Meta.chest["oath"] = 0
