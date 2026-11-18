extends Node
## Скриншоты Хаба (нужен рендер): xvfb-run godot --path . res://tools/tests/hub_shot.tscn -- out=/путь
var out := "user://"
var _backup = null


func _ready() -> void:
	if name != "HubShotRunner":
		var r: Node = (get_script() as GDScript).new()
		r.name = "HubShotRunner"
		get_tree().root.add_child.call_deferred(r)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	_go.call_deferred()


func _go() -> void:
	if FileAccess.file_exists(Meta.save_path):
		_backup = FileAccess.get_file_as_string(Meta.save_path)
	get_tree().change_scene_to_file("res://game/scenes/title.tscn")
	await get_tree().create_timer(1.0).timeout
	await _shot("title")
	Meta.story["seen"] = ["intro"]
	Run.hub_reason = ""
	get_tree().change_scene_to_file("res://game/hub/hub.tscn")
	await get_tree().create_timer(2.0).timeout
	var hub := get_tree().current_scene
	await _shot("hub_fire")
	var p: Node3D = hub.player
	p.global_position = Vector3(7.5, 0.2, 0.5)
	await get_tree().create_timer(1.0).timeout
	var d = hub.dummy
	for i in 3:
		var h := Hit.make(12.0 + i * 10, p, "special" if i == 1 else "normal")
		h.is_crit = i == 2
		d.take_hit(h)
	await get_tree().create_timer(0.25).timeout
	await _shot("hub_armory")
	p.global_position = Vector3(-6.5, 0.2, 1.5)
	await get_tree().create_timer(1.0).timeout
	await _shot("hub_yurt")
	p.global_position = Vector3(0, 0.2, -9.5)
	await get_tree().create_timer(1.2).timeout
	await _shot("hub_gate")
	p.global_position = Vector3(1.5, 0.2, 2.5)
	await get_tree().create_timer(0.5).timeout
	var m: DombraMode = hub.open_dombra()
	await get_tree().create_timer(1.3).timeout
	m.set_fret(4)
	m.begin_kui("adai")
	await get_tree().create_timer(2.2).timeout
	m.strike("down")
	await get_tree().create_timer(0.05).timeout
	await _shot("dombra")
	var w := ArmoryWindow.new()
	w.weapon_id = "spear"
	m.close()
	await get_tree().create_timer(1.0).timeout
	w.open_on(hub, p)
	await get_tree().create_timer(0.4).timeout
	await _shot("armory_window")
	w.close()
	var c := ChestWindow.new()
	await get_tree().create_timer(0.4).timeout
	c.open_on(hub, p)
	await get_tree().create_timer(0.4).timeout
	await _shot("chest_window")
	if _backup != null:
		var f := FileAccess.open(Meta.save_path, FileAccess.WRITE)
		f.store_string(_backup)
	get_tree().quit()


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join("hub_%s.png" % n))
	print("shot ", n)
