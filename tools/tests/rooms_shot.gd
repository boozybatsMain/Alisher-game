extends Node
## Скриншоты арен модуля D (нужен рендер): xvfb-run godot --path . res://tools/tests/rooms_shot.tscn -- out=/путь [layout=terraces] [biome=0] [room=combat]
## room=<type> — запустить настоящую комнату (room.tscn) этого типа и снять кадры.
var out := "user://"
var layouts: Array = []
var biomes: Array = [0, 1, 2]
var room_type := ""

func _ready() -> void:
	if name != "RoomsShotRunner":
		var w: Node = (get_script() as GDScript).new()
		w.name = "RoomsShotRunner"
		get_tree().root.add_child.call_deferred(w)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("layout="):
			layouts = a.substr(7).split(",")
		elif a.begins_with("biome="):
			biomes = []
			for b in a.substr(6).split(","):
				biomes.append(int(b))
		elif a.begins_with("room="):
			room_type = a.substr(5)
	if layouts.is_empty():
		layouts = ArenaLayouts.all_ids()
	_go.call_deferred()


func _go() -> void:
	if room_type != "":
		await _room_shots()
		get_tree().quit(0)
		return
	for l in layouts:
		for b in biomes:
			var holder := Node3D.new()
			get_tree().root.add_child(holder)
			var arena := ArenaBuilder.create(holder, String(l), int(b), 12345)
			var target := Node3D.new()
			holder.add_child(target)
			target.global_position = Vector3(0, 0, 2)
			var cam := GameCamera.attach(holder, target)
			cam.snap()
			await get_tree().create_timer(0.4).timeout
			_shot("%s_b%d" % [l, b])
			target.global_position = arena.door_slots[0] + Vector3(0, 0, 4)
			cam.snap()
			await get_tree().create_timer(0.2).timeout
			_shot("%s_b%d_north" % [l, b])
			target.global_position = Vector3(0, 0, 0)
			cam.zoom_mult = 2.3
			cam.snap()
			await get_tree().create_timer(0.2).timeout
			_shot("%s_b%d_wide" % [l, b])
			holder.queue_free()
			await get_tree().process_frame
	get_tree().quit(0)


func _room_shots() -> void:
	Run.active = true
	Run.hp = Run.max_hp()
	var b := 0
	if not biomes.is_empty():
		b = int(biomes[0])
	Run.current_room = {"type": room_type, "reward": "boon", "god": "umai", "god2": "tengri", "depth": 3 + b * 7, "biome": b, "seed": 777, "seal": false}
	if room_type == "merchant":
		Run.current_room["reward"] = "merchant"
		Run.add_dirhams(300)
	if room_type == "boss":
		Run.current_room["depth"] = 6 + b * 7
	get_tree().change_scene_to_file("res://game/rooms/room.tscn")
	await get_tree().create_timer(2.5).timeout
	_shot("room_%s_b%d_a" % [room_type, b])
	await get_tree().create_timer(2.5).timeout
	_shot("room_%s_b%d_b" % [room_type, b])
	var room := get_tree().current_scene
	if room and room.has_method("debug_clear"):
		room.debug_clear()
		await get_tree().create_timer(2.0).timeout
		_shot("room_%s_b%d_cleared" % [room_type, b])


func _shot(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join("rooms_%s.png" % n))
	print("shot ", n)
