extends CanvasLayer
## Эффекты: затемнение при смене сцен, хитстоп, тряска камеры, всплывающие цифры.

var _fade: ColorRect
var _hitstop_depth := 0
var _font: Font


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	_font = preload("res://scripts/ui/ui_kit.gd").font()


func change_scene(path: String, duration := 0.45) -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, duration)
	await tw.finished
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, duration)
	await tw2.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


func hitstop(duration: float, scale := 0.05) -> void:
	## Короткая «заморозка» кадра на попадании — ощущение веса удара.
	_hitstop_depth += 1
	Engine.time_scale = scale
	await get_tree().create_timer(duration, true, false, true).timeout
	_hitstop_depth -= 1
	if _hitstop_depth <= 0:
		_hitstop_depth = 0
		Engine.time_scale = 1.0


func shake(amount: float, duration := 0.25) -> void:
	get_tree().call_group("game_camera", "shake", amount, duration)


func punch(amount: float) -> void:
	## Короткий наезд камеры на тяжёлом ударе.
	get_tree().call_group("game_camera", "punch", amount)


func float_text(world_parent: Node, pos: Vector2, text: String, color := Color.WHITE, size := 30) -> void:
	## Всплывающая цифра урона / лечения в мировых координатах.
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.03))
	l.add_theme_constant_override("outline_size", 7)
	l.z_index = 50
	world_parent.add_child(l)
	l.position = pos + Vector2(randf_range(-18, 18) - 30, -10)
	l.size = Vector2(60, 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.pivot_offset = Vector2(30, 15)
	l.scale = Vector2(0.6, 0.6)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 70, 0.8).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)
