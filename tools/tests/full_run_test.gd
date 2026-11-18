extends Node
## Полный забег без человека: godot --headless --path . res://tools/tests/full_run_test.tscn [-- fast]
## Run.start_run → в каждой комнате враги убиваются через take_hit (большой урон от героя), награда
## забирается (тотем — через окно BoonChoice, предметы — подбором), герой входит в первую дверь.
## Три биома, три босса, финальная победа → Run.end_run → Хаб (диалог Story), Meta.stats.victories + 1.
## fast — после первых 3 комнат каждого биома прыгает к комнате перед боссом (переписывая Run.current_room).

const MAX_ROOMS := 40

var fails := 0
var checks := 0
var fast := false
var _save_backup := ""
var _god := true


func _ready() -> void:
	if name != "FullRunRunner":
		var w: Node = (get_script() as GDScript).new()
		w.name = "FullRunRunner"
		get_tree().root.add_child.call_deferred(w)
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	fast = "fast" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _process(_d: float) -> void:
	if _god and Run.active and Run.hp < Run.max_hp():
		Run.set_hp(Run.max_hp())


func ok(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _room() -> Node:
	var sc := get_tree().current_scene
	if sc and sc.scene_file_path == Run.ROOM_SCENE:
		return sc
	return null


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player")


func _run() -> void:
	if FileAccess.file_exists(Meta.save_path):
		_save_backup = FileAccess.get_file_as_string(Meta.save_path)
	Meta.reset_save()
	var victories0 := int(Meta.stats["victories"])
	var boss_kills0 := int(Meta.stats.get("boss_kills", 0))
	var t0 := Time.get_ticks_msec()
	Run.start_run()
	var visited := []
	var biomes := {}
	var types := {}
	var prev_scene: Node = null
	var won := false
	for i in MAX_ROOMS:
		var r := await _await_room(prev_scene)
		if r == null:
			ok(false, "комната %d не загрузилась" % i)
			break
		prev_scene = r
		var room: Dictionary = r.get("room")
		visited.append(int(room["depth"]))
		biomes[int(room["biome"])] = true
		types[String(room["type"])] = int(types.get(String(room["type"]), 0)) + 1
		print("-- комната depth=%d biome=%d type=%s reward=%s god=%s" % [room["depth"], room["biome"], room["type"], room["reward"], room.get("god", "")])
		var cleared := await _clear_room(r)
		ok(cleared, "depth %d (%s): комната пройдена (state=%s)" % [room["depth"], room["type"], r.get("state")])
		if not cleared:
			break
		if String(r.get("state")) == "victory":
			won = true
			break
		await _take_reward(r)
		_close_dialogue()
		var doors: Array = r.get("doors")
		var opened := false
		for k in 40:
			if not doors.is_empty() and (doors[0] as RoomDoor).is_open:
				opened = true
				break
			_close_dialogue()
			await _wait(0.1)
		ok(opened, "depth %d: двери открылись после награды" % room["depth"])
		if not opened:
			break
		var door: RoomDoor = doors[0]
		for d in doors:   # предпочитаем боевые двери: больше стыков проверяется
			if String((d as RoomDoor).room_data.get("type", "")) in ["combat", "elite", "boss"]:
				door = d
				break
		var next: Dictionary = door.room_data.duplicate(true)
		if fast and String(next["type"]) != "boss" and int(next["depth"]) >= 0 and RoomPlanner.local_of(int(next["depth"])) >= 3:
			# ускорение: сразу к комнате перед боссом — переписываем Run.current_room и берём её двери
			var pre := int(next["biome"]) * 7 + 5
			if int(next["depth"]) < pre:
				next["depth"] = pre
				Run.current_room = next
				Run.enter_room(next)
				continue
		door.activate(_player())
	var hub := await _await_hub()
	ok(won, "финальный босс повержен — победа")
	ok(biomes.has(0) and biomes.has(1) and biomes.has(2), "пройдены все 3 биома: %s" % str(biomes.keys()))
	ok(int(Meta.stats.get("boss_kills", 0)) == boss_kills0 + 3, "3 босса убиты (Meta.stats.boss_kills %d)" % int(Meta.stats.get("boss_kills", 0)))
	ok(hub != null, "после победы — Хаб")
	ok(int(Meta.stats["victories"]) == victories0 + 1, "Meta.stats.victories увеличен (%d)" % int(Meta.stats["victories"]))
	ok(not Run.active, "Run.active == false")
	ok(bool(Meta.last_run.get("died", true)) == false and String(Meta.last_run.get("boss", "")) == "khan", "Meta.last_run: победа над %s" % str(Meta.last_run.get("boss", "")))
	if hub:
		await _wait(1.6)
		ok(DialogueBox.is_open(), "в Хабе сюжетный диалог после победы")
		_close_dialogue()
	print("комнат: %d, типы: %s, время %.1f с" % [visited.size(), str(types), (Time.get_ticks_msec() - t0) / 1000.0])
	_restore_save()
	print("FULL RUN TEST: checks=%d failed=%d -> %s" % [checks, fails, "PASS" if fails == 0 else "FAIL"])
	get_tree().quit(1 if fails > 0 else 0)


func _restore_save() -> void:
	if _save_backup != "":
		var f := FileAccess.open(Meta.save_path, FileAccess.WRITE)
		f.store_string(_save_backup)
		f.close()
		Meta.load_game()
	else:
		Meta.reset_save()


func _await_room(prev: Node) -> Node:
	for k in 100:
		await _wait(0.1)
		var r := _room()
		if r and r != prev and r.is_inside_tree() and _player() != null:
			await _wait(0.4)
			return r
	return null


func _await_hub() -> Node:
	for k in 120:
		await _wait(0.1)
		var sc := get_tree().current_scene
		if sc and sc.scene_file_path == Run.HUB_SCENE:
			return sc
	return null


## Добить всех живых врагов ударами героя (take_hit через Combat.player_hit).
func _strike_all() -> int:
	var p := _player()
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or (e.has_method("is_dead") and e.is_dead()):
			continue
		var h := Hit.make(99999.0, p, "normal")
		h.heavy = true
		h.pierce_armor = true
		h.no_boons = true
		Combat.player_hit(e, h)
		n += 1
	return n


func _clear_room(r: Node) -> bool:
	var type := String(r.get("room")["type"])
	if type == "duel":
		var totems: Array = r.get("totems")
		await _use_totem(totems[0])
		await _fight(r, 60.0)
		await _wait(0.3)
		if is_instance_valid(totems[1]) and bool(totems[1].get("enabled")):
			await _use_totem(totems[1])
		return String(r.get("state")) in ["reward", "open"]
	if type in ["merchant", "rest"]:
		return String(r.get("state")) == "open"
	if type == "boss":
		for k in 60:   # ждём появления босса
			if r.get("boss") != null:
				break
			await _wait(0.1)
		ok(r.get("boss") != null, "босс появился: %s" % str(r.get("boss_id")))
		await _wait(1.6)   # босс активируется и показывает свою полосу (BossBase.own_bar)
		var bars := get_tree().get_nodes_in_group("boss_bar").size()
		ok(bars == 1, "ровно одна полоса босса (%d)" % bars)
	await _fight(r, 90.0)
	return String(r.get("state")) in ["reward", "open", "victory"]


func _fight(r: Node, limit: float) -> void:
	var t := 0.0
	while t < limit and String(r.get("state")) in ["fight", "intro"]:
		_strike_all()
		_close_dialogue()
		await _wait(0.25)
		t += 0.25
	# пауза после убийства босса (диалог) — закрыть
	_close_dialogue()


func _take_reward(r: Node) -> void:
	var node = r.get("reward_node")
	if node == null or not is_instance_valid(node):
		return
	if node is SpiritTotem:
		await _use_totem(node)
	else:
		r.take_reward_now()
	await _wait(0.2)


func _use_totem(t: Node) -> void:
	if t == null or not is_instance_valid(t):
		return
	var n0 := (Run.boons.owned() as Array).size()
	t.activate(_player())
	await get_tree().process_frame
	var picked := false
	for k in 10:
		for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
			if n is BoonChoice and n.is_inside_tree():
				n.pick(0)
				picked = true
				break
		if picked:
			break
		await get_tree().process_frame
	await _wait(0.2)
	ok(picked and not get_tree().paused, "тотем %s: дар выбран в BoonChoice, пауза снята" % str(t.get("god")))
	ok((Run.boons.owned() as Array).size() >= n0, "дары героя: %d" % (Run.boons.owned() as Array).size())


func _close_dialogue() -> void:
	for i in 40:
		if not DialogueBox.is_open():
			return
		var d := DialogueBox.ensure(get_tree())
		d.advance()
		d.advance()
