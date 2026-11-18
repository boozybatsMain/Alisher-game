extends Node
## Бот для проверки: запускает арену и жмёт кнопки как игрок, печатает ход боя.
## Godot --path . res://tools/autoplay.tscn -- stage=0 wave=0 god secs=40

var t := 0.0
var secs := 40.0
var god := false
var log_t := 0.0
var next_attack := 0.0
var next_roll := 2.0
var block_until := 0.0
var scene := "arena"
var gift_delay := 0.0
var gift_seen := -1.0
var start_hp := -1.0
var smart := false
var last_hp := -1.0
var step := 0
var step_t := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("stage="):
			GameState.stage = int(a.substr(6))
		elif a.begins_with("secs="):
			secs = float(a.substr(5))
		elif a == "god":
			god = true
		elif a == "smart":
			smart = true
		elif a.begins_with("scene="):
			scene = a.substr(6)
		elif a.begins_with("gift_delay="):
			gift_delay = float(a.substr(11))
		elif a.begins_with("hp="):
			start_hp = float(a.substr(3))
	GameState.start_run() if GameState.stage == 0 else null
	for a in OS.get_cmdline_user_args():
		if a.begins_with("stage="):
			GameState.stage = int(a.substr(6))
	process_mode = Node.PROCESS_MODE_ALWAYS
	_boot.call_deferred()


func _boot() -> void:
	# бот не должен быть «текущей сценой», иначе смена сцены его удалит
	get_tree().current_scene = null
	var path: String = {"arena": "res://scenes/levels/arena.tscn", "yurt": "res://scenes/levels/yurt.tscn", "title": "res://scenes/ui/title.tscn"}[scene]
	get_tree().change_scene_to_file(path)


func _physics_process(delta: float) -> void:
	t += delta
	if t > secs:
		print("AUTOPLAY END t=%.1f kills=%d asyks=%d" % [t, GameState.run_kills, GameState.run_asyks])
		get_tree().quit()
		return
	var hero := get_tree().get_first_node_in_group("player")
	var arena := get_tree().get_first_node_in_group("arena")
	if scene == "yurt":
		_yurt_bot(hero, delta)
		return
	if scene == "title":
		return
	# окно выбора Дара — берём первый
	for n in get_tree().root.get_children():
		pass
	if get_tree().paused:
		var gc := _find_gift_choice(get_tree().root)
		if gc and not gc.closing:
			if gift_seen < 0.0:
				gift_seen = t
			if t - gift_seen >= gift_delay:
				print("GIFT choose t=%.1f" % t)
				gc._choose(randi() % gc.options.size())
				gift_seen = -1.0
		return
	if hero == null:
		return
	if god:
		hero.hp = hero.max_hp
	if start_hp > 0.0 and t > 0.5:
		hero.hp = start_hp
		start_hp = -1.0
	var enemies := get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e.alert.visible and e.st < 0.05:
			print("ALERT t=%.2f %s x=%d" % [t, e.kind, e.global_position.x])
	if last_hp >= 0.0 and hero.hp < last_hp - 0.01:
		var who := []
		for e in enemies:
			if absf(e.global_position.x - hero.global_position.x) < 500.0:
				who.append("%s:%s f%d st%d" % [e.kind, e.sprite.animation, e.sprite.frame, e.state])
		print("  -%d hp (hero st=%d blockT=%.2f scd=%.2f rcd=%.2f) <- %s" % [last_hp - hero.hp, hero.state, hero.block_t, hero.shield_cd, hero.roll_cd, who])
	last_hp = hero.hp
	var target: Node = null
	var bd := 1e9
	for e in enemies:
		var d: float = absf(e.global_position.x - hero.global_position.x)
		if d < bd:
			bd = d
			target = e
	Input.action_release("move_left")
	Input.action_release("move_right")
	if target == null:
		Input.action_press("move_right")
	else:
		var dir := signf(target.global_position.x - hero.global_position.x)
		if bd > 200.0:
			Input.action_press("move_right" if dir > 0 else "move_left")
		elif hero.facing != int(dir):
			Input.action_press("move_right" if dir > 0 else "move_left")
		if t > next_attack and bd < 260.0:
			next_attack = t + 0.13
			Input.action_press("attack")
			Input.action_release.call_deferred("attack")
		if t > next_roll and not smart:
			next_roll = t + randf_range(1.5, 3.0)
			Input.action_press("roll")
			Input.action_release.call_deferred("roll")
		if target.state == 3 and target.st < 0.1 and randf() < 0.3:   # враг начал удар — иногда блок
			block_until = t + 0.4
	# «умный» режим: на замах врага рядом — блок, если щит готов, иначе кувырок прочь
	if smart:
		for e in enemies:
			var d: float = absf(e.global_position.x - hero.global_position.x)
			if e.state == 3 and d < 380.0 and e.sprite.frame in e.attack.get("telegraph", []):
				if hero.shield_cd <= 0.0 or hero.state == 7:
					Input.action_release("move_left")
					Input.action_release("move_right")
					if hero.facing != int(signf(e.global_position.x - hero.global_position.x)):
						Input.action_press("move_right" if e.global_position.x > hero.global_position.x else "move_left")
					block_until = t + 0.35
				elif hero.roll_cd <= 0.0:
					Input.action_press("move_left" if e.global_position.x > hero.global_position.x else "move_right")
					Input.action_press("roll")
					Input.action_release.call_deferred("roll")
				break
	if t < block_until:
		Input.action_press("block")
	else:
		Input.action_release("block")
	log_t -= delta
	if log_t <= 0.0:
		log_t = 2.0
		var names := []
		for e in enemies:
			names.append("%s(%d)" % [e.kind, e.hp])
		print("t=%.1f ts=%.2f paused=%s phase=%s wave=%s hero=%d st=%d x=%d enemies=%s" % [t, Engine.time_scale, get_tree().paused, arena.phase if arena else -1, arena.wave_idx if arena else -1,
			hero.hp, hero.state, hero.global_position.x, names])


func _find_gift_choice(n: Node) -> Node:
	for c in n.get_children():
		if c.get_script() == preload("res://scripts/ui/gift_choice.gd"):
			return c
		var r := _find_gift_choice(c)
		if r:
			return r
	return null


func _press(action: String) -> void:
	# настоящее событие ввода (action_press событий не создаёт)
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event.call_deferred(up)


func _yurt_bot(hero: Node, delta: float) -> void:
	# юрта: дойти до сундука, открыть, закрыть; дойти до очага, открыть, закрыть
	if hero == null:
		return
	step_t += delta
	Input.action_release("move_left")
	Input.action_release("move_right")
	match step:
		0:
			if step_t > 1.0:
				Input.action_press("move_right")
				if hero.global_position.x > 880.0:
					step = 1
					step_t = 0.0
		1:
			if step_t > 0.4:
				_press("interact")
				step = 2
				step_t = 0.0
		2:
			if step_t > 2.0:
				_press("ui_accept")
				step = 3
				step_t = 0.0
		3:
			if step_t > 0.5:
				Input.action_press("move_left")
				if hero.global_position.x < 560.0:
					step = 4
					step_t = 0.0
		4:
			if step_t > 0.4:
				_press("interact")
				step = 5
				step_t = 0.0
		5:
			if step_t > 2.2:
				_press("ui_accept")
				step = 6
				step_t = 0.0
