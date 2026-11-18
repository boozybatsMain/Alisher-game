extends Node
## Запускает сцену на N секунд и выходит. Ошибки рантайма видны в выводе Godot (ищите "ERROR" / "SCRIPT ERROR").
## Godot --headless --path . res://tools/smoke.tscn -- scene=res://game/hub/hub.tscn secs=5 [run] [god]
##   run  — перед сценой вызвать Run.start_run() (сразу первая комната забега)
##   god  — герой бессмертен (Run.hp держится на максимуме)
##   bot  — простой бот: бегает к ближайшему врагу и жмёт атаки/рывок/особую

var secs := 5.0
var t := 0.0
var god := false
var bot := false
var _bot_t := 0.0


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
	if t >= secs:
		var sc := get_tree().current_scene
		print("SMOKE end t=%.1f scene=%s hp=%.0f depth=%d kills=%d enemies=%d" % [t, sc.scene_file_path if sc else "-", Run.hp, Run.depth, Run.kills, get_tree().get_nodes_in_group("enemies").size()])
		get_tree().quit(0)


func _bot(delta: float) -> void:
	_bot_t += delta
	var p = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	var e: Node3D = Combat.nearest(get_tree(), p.global_position, 80.0, "enemies")
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)
	if e:
		var d: Vector3 = e.global_position - p.global_position
		if d.length() > 2.0:
			if d.x < -0.5: Input.action_press("move_left")
			if d.x > 0.5: Input.action_press("move_right")
			if d.z < -0.5: Input.action_press("move_up")
			if d.z > 0.5: Input.action_press("move_down")
	var phase := int(_bot_t * 6.0) % 12
	for a in ["attack", "special", "dash", "jump"]:
		Input.action_release(a)
	if phase in [0, 2, 4, 6]:
		Input.action_press("attack")
	elif phase == 8:
		Input.action_press("special")
	elif phase == 10 and randf() < 0.3:
		Input.action_press("dash")
	elif phase == 11 and randf() < 0.2:
		Input.action_press("jump")
