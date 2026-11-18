extends Node
## Запускает сцену на N секунд и выходит. Ошибки рантайма видны в выводе Godot (ищите "ERROR" / "SCRIPT ERROR").
## Godot --headless --path . res://tools/smoke.tscn -- scene=res://game/hub/hub.tscn secs=5 [run] [god]
##   run  — перед сценой вызвать Run.start_run() (сразу первая комната забега)
##   god  — герой бессмертен (Run.hp держится на максимуме)
##   bot  — простой бот: бегает к ближайшему врагу и жмёт атаки/рывок/особую; после зачистки берёт награду
##          (тотем → первая карточка дара), листает диалоги и идёт в ближайшую открытую дверь

var secs := 5.0
var t := 0.0
var god := false
var bot := false
var _bot_t := 0.0
var _ui_t := 0.0
var _stuck := 0.0
var _detour := 0.0
var _detour_sign := 1.0
var _last_pos := Vector3.ZERO
var _rooms := 0
var _last_depth := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if name != "SmokeWatch":
		## Сцена-загрузчик будет заменена — переносим логику в постоянный узел под root.
		var w: Node = (get_script() as GDScript).new()
		w.name = "SmokeWatch"
		get_tree().root.add_child.call_deferred(w)
		set_process(false)
		return
	var scene := ""
	var run := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("scene="):
			scene = a.substr(6)
		elif a.begins_with("secs="):
			secs = float(a.substr(5))
		elif a == "run":
			run = true
		elif a == "god":
			god = true
		elif a == "bot":
			bot = true
	if run:
		Run.start_run()
	elif scene != "":
		get_tree().call_deferred("change_scene_to_file", scene)
	print("SMOKE start scene=", scene, " run=", run)


func _process(delta: float) -> void:
	t += delta / maxf(Engine.time_scale, 0.01)
	if god and Run.hp < Run.max_hp():
		Run.set_hp(Run.max_hp())
	if bot:
		_bot(delta)
	if Run.active and Run.depth != _last_depth:
		_last_depth = Run.depth
		_rooms += 1
		print("SMOKE room #%d depth=%d type=%s t=%.1f" % [_rooms, Run.depth, str(Run.current_room.get("type", "")), t])
	if t >= secs:
		var sc := get_tree().current_scene
		print("SMOKE end t=%.1f scene=%s hp=%.0f depth=%d rooms=%d kills=%d enemies=%d" % [t, sc.scene_file_path if sc else "-", Run.hp, Run.depth, _rooms, Run.kills, get_tree().get_nodes_in_group("enemies").size()])
		get_tree().quit(0)


func _bot(delta: float) -> void:
	_bot_t += delta
	_ui_t += delta
	var tree := get_tree()
	# окна: диалог — листаем, выбор дара — первая карточка (бот «играет» как человек, но без клавиатуры)
	if _ui_t > 0.35:
		_ui_t = 0.0
		if DialogueBox.is_open():
			DialogueBox.ensure(tree).advance()
			return
		for n in tree.root.find_children("*", "CanvasLayer", true, false):
			if n is BoonChoice and n.is_inside_tree():
				n.pick(0)
				return
	var p = tree.get_first_node_in_group("player")
	if p == null:
		return
	for a in ["move_left", "move_right", "move_up", "move_down", "attack", "special", "dash", "jump", "interact"]:
		Input.action_release(a)
	var e: Node3D = Combat.nearest(tree, p.global_position, 80.0, "enemies")
	var goal: Node3D = e
	var near := 2.0
	if e == null:
		goal = _bot_goal(p)
		near = 0.6
	if goal:
		var d: Vector3 = goal.global_position - p.global_position
		d.y = 0.0
		if _detour > 0.0:   # обход препятствия: шаг вбок
			_detour -= delta
			_steer(d.normalized().cross(Vector3.UP) * _detour_sign * 3.0 + d.normalized(), 0.0)
		else:
			_steer(d, near)
		if e == null and goal is Interactable and p.get("current_interactable") == goal and int(_bot_t * 4.0) % 2 == 0:
			Input.action_press("interact")
		# застрял — прыгаем
		if p.global_position.distance_to(_last_pos) < 0.05 and d.length() > near:
			_stuck += delta
		else:
			_stuck = 0.0
		_last_pos = p.global_position
		if _stuck > 0.6 and int(_bot_t * 3.0) % 3 == 0:
			Input.action_press("jump")
		if _stuck > 1.2:
			_stuck = 0.0
			_detour = 0.9
			_detour_sign = -_detour_sign
	if e == null:
		return
	var phase := int(_bot_t * 6.0) % 12
	if phase in [0, 2, 4, 6]:
		Input.action_press("attack")
	elif phase == 8:
		Input.action_press("special")
	elif phase == 10 and randf() < 0.3:
		Input.action_press("dash")
	elif phase == 11 and randf() < 0.2:
		Input.action_press("jump")


## Цель бота вне боя: невзятая награда/тотем → открытая дверь.
func _bot_goal(p: Node3D) -> Node3D:
	var room := get_tree().current_scene
	if room == null or room.scene_file_path != Run.ROOM_SCENE:
		return null
	var cands: Array = []
	var totems = room.get("totems")
	if totems is Array:
		for t in totems:
			if is_instance_valid(t) and (t as Object) is Interactable and t.can_activate(p):
				cands.append(t)
	var rw = room.get("reward_node")
	if rw != null and is_instance_valid(rw) and (rw as Object) is Interactable and rw.can_activate(p):
		cands.append(rw)
	if not cands.is_empty():
		return cands[0]
	var doors = room.get("doors")
	if doors is Array:
		var best: Node3D = null
		for d in doors:
			if is_instance_valid(d) and bool(d.get("is_open")):
				if best == null or p.global_position.distance_to(d.global_position) < p.global_position.distance_to(best.global_position):
					best = d
		return best
	return null


## Жмёт move_* так, чтобы герой шёл по мировому направлению d (управление относительно камеры).
func _steer(d: Vector3, near: float) -> void:
	if d.length() <= near:
		return
	var cam := get_viewport().get_camera_3d()
	var right := Vector3(1, 0, 0)
	var up := Vector3(0, 0, -1)
	if cam:
		right = cam.global_transform.basis.x
		right = Vector3(right.x, 0, right.z).normalized()
		up = -cam.global_transform.basis.z
		up = Vector3(up.x, 0, up.z).normalized()
	var n := d.normalized()
	var a := n.dot(right)
	var b := n.dot(up)
	if a < -0.35: Input.action_press("move_left")
	if a > 0.35: Input.action_press("move_right")
	if b > 0.35: Input.action_press("move_up")
	if b < -0.35: Input.action_press("move_down")
