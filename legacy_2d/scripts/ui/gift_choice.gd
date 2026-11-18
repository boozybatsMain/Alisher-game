extends CanvasLayer
## Выбор Дара после волны: один из трёх богов (Тенгри, Умай, От-Ана). Дар сразу ложится в ромб под полосой здоровья.
## Когда все три ромба заняты — предлагаются усиления (до III уровня), лечение или асыки.

signal chosen

const UI := preload("res://scripts/ui/ui_kit.gd")
const Gifts := preload("res://scripts/data/gifts.gd")

var hero: Node
var options := []
var buttons: Array[Button] = []
var closing := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_make_options()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme()
	add_child(root)
	UI.dim(root, 0.66)
	var slot := GameState.next_empty_slot()
	var title := UI.label("Дар богов" if slot >= 0 else "Благословение богов", 44, Color(1, 0.86, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_font_override("font", UI.bold())
	title.size = Vector2(1280, 56)
	title.position = Vector2(0, 46)
	root.add_child(title)
	var sub := UI.label(("Выбери один — он займёт ромб «%s»" % Gifts.SLOT_NAMES[slot]) if slot >= 0 else "Все ромбы заняты — усиль один из Даров",
		22, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	sub.size = Vector2(1280, 30)
	sub.position = Vector2(0, 104)
	root.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 34)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size = Vector2(1280, 460)
	row.position = Vector2(0, 160)
	root.add_child(row)
	for i in options.size():
		var b := _card(options[i], i)
		row.add_child(b)
		buttons.append(b)
	var hint := UI.label("1 / 2 / 3, стрелки + Enter или мышь", 18, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	hint.size = Vector2(1280, 26)
	hint.position = Vector2(0, 650)
	root.add_child(hint)
	if buttons.size() > 0:
		buttons[0].call_deferred("grab_focus")
	Sfx.play("gift_open")


func _make_options() -> void:
	var slot := GameState.next_empty_slot()
	if slot >= 0:
		for god in Gifts.GOD_ORDER:
			options.append({"type": "gift", "slot": slot, "god": god, "level": 1})
		return
	for s in 3:
		var lvl := GameState.gift_level(s)
		if lvl < 3:
			options.append({"type": "gift", "slot": s, "god": GameState.gift_god(s), "level": lvl + 1})
	if options.size() < 3:
		options.append({"type": "heal"})
	if options.size() < 3:
		options.append({"type": "asyks"})


func _card(o: Dictionary, idx: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(330, 450)
	b.focus_mode = Control.FOCUS_ALL
	var col := Color(1, 0.85, 0.5)
	var tex: Texture2D
	var head := ""
	var head_sub := ""
	var name := ""
	var desc := ""
	var lvl_text := ""
	match o["type"]:
		"gift":
			var god: String = o["god"]
			col = Gifts.GODS[god]["color"]
			tex = load(Gifts.emblem_path(god))
			head = Gifts.GODS[god]["name"]
			head_sub = Gifts.GODS[god]["title"]
			name = Gifts.gift_name(god, o["slot"])
			desc = Gifts.describe(god, o["slot"], o["level"])
			lvl_text = ("Ромб: %s" % Gifts.SLOT_NAMES[o["slot"]]) + ("" if o["level"] == 1 else ("   ·   Усиление → %s" % ["", "I", "II", "III"][o["level"]]))
		"heal":
			col = Color(1, 0.45, 0.4)
			tex = preload("res://assets/ui/icons/heart.png")
			head = "Целебный кымыз"
			head_sub = "Дар очага"
			name = "Восстановление"
			desc = "Восстанавливает 40% здоровья."
		"asyks":
			col = Color(1, 0.85, 0.4)
			tex = preload("res://assets/ui/icons/asyk.png")
			head = "Горсть асыков"
			head_sub = "Дар степи"
			name = "Богатство"
			desc = "+15 асыков для вечной прокачки в сундуке."
	for st_name in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.14, 0.08, 0.06, 0.96) if st_name == "normal" else Color(0.22, 0.12, 0.08, 0.98)
		sb.border_color = col if st_name != "normal" else col.darkened(0.35)
		sb.set_border_width_all(4 if st_name != "normal" else 3)
		sb.set_corner_radius_all(14)
		if st_name == "focus":
			sb.bg_color = Color(0, 0, 0, 0)
		b.add_theme_stylebox_override(st_name, sb)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 18
	v.offset_right = -18
	v.offset_top = 16
	v.offset_bottom = -16
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var num := UI.label(str(idx + 1), 18, UI.MUTED)
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(num)
	var img := TextureRect.new()
	img.texture = tex
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.custom_minimum_size = Vector2(150, 150)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	img.material = UI.boil_mat()
	v.add_child(img)
	for item in [[head, 30, col, true], [head_sub, 17, UI.MUTED, false], [name, 23, Color(1, 0.9, 0.6), true]]:
		var l := UI.label(item[0], item[1], item[2], HORIZONTAL_ALIGNMENT_CENTER)
		if item[3]:
			l.add_theme_font_override("font", UI.bold())
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	var d := UI.label(desc, 18, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(290, 80)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)
	var lv := UI.label(lvl_text, 15, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(lv)
	b.pressed.connect(_choose.bind(idx))
	b.mouse_entered.connect(func(): b.grab_focus())
	b.focus_entered.connect(func(): Sfx.play("ui_hover", -12.0))
	return b


func _unhandled_input(event: InputEvent) -> void:
	if closing:
		return
	for i in options.size():
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_1 + i:
			_choose(i)
			get_viewport().set_input_as_handled()


func _choose(i: int) -> void:
	if closing:
		return
	closing = true
	var o: Dictionary = options[i]
	match o["type"]:
		"gift":
			GameState.set_gift(o["slot"], o["god"])
		"heal":
			if hero:
				hero.heal(hero.max_hp * 0.4)
		"asyks":
			GameState.add_asyks(15)
	Sfx.play("gift_take")
	get_tree().paused = false
	chosen.emit()
	queue_free()
