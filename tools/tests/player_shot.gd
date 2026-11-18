extends Node
## Скриншоты песочницы модуля A (нужен рендер: xvfb-run godot --path . res://tools/tests/player_shot.tscn -- out=/путь)
var out := "user://"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	_go.call_deferred()

func _go() -> void:
	var sb: Node = load("res://game/player/sandbox.tscn").instantiate()
	get_tree().root.add_child(sb)
	await get_tree().create_timer(1.0).timeout
	Input.action_press("move_right")
	await get_tree().create_timer(0.3).timeout
	_shot("run")
	Input.action_press("dash")
	await get_tree().create_timer(0.08).timeout
	Input.action_release("dash")
	_shot("dash")
	Input.action_release("move_right")
	await get_tree().create_timer(0.5).timeout
	Bus.damage_number.emit(Vector3(5, 2, 3), 24, "crit")
	Bus.damage_number.emit(Vector3(7, 2, 3), 12, "normal")
	Fx3D.telegraph_circle(sb, Vector3(0, 0, 0), 2.5, 1.0)
	Fx3D.slash_arc(sb, sb.player.global_position, Vector3(1, 0, 0), 2.0)
	Fx3D.lightning(sb, sb.player.global_position + Vector3(0, 1, 0), Vector3(6, 1, 3))
	Bus.toast.emit("Дар Тенгри принят", UiKit.god_color("tengri"))
	await get_tree().create_timer(0.3).timeout
	_shot("fx")
	Bus.dialogue_requested.emit([{"speaker": "Дух предка", "text": "Кайсар, корни Байтерека стонут."}])
	await get_tree().create_timer(1.2).timeout
	_shot("dialogue")
	DialogueBox.ensure(get_tree()).close()
	Input.action_press("pause")
	await get_tree().process_frame
	Input.action_release("pause")
	var hud := Hud.find(get_tree())
	hud.open_pause()
	await get_tree().create_timer(0.3).timeout
	_shot("pause")
	get_tree().quit()

func _shot(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join("shot_%s.png" % n))
	print("shot ", n)
