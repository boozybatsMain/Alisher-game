class_name BoonChoice
extends CanvasLayer
## Окно «Дар духа»: 3 карточки (дух, слот, редкость рамкой, описание, «заменит: ...»).
## Выбор мышью, клавишами 1–3, стрелками/геймпадом + Enter. Мир на паузе, пока окно открыто.
## BoonChoice.open(parent, god, on_done, choices := []) — on_done(choice: Dictionary) после выбора ({} если даров нет).

const UI_KIT := "res://game/ui/ui_kit.gd"

var god := ""
var choices: Array = []
var on_done: Callable
var _was_paused := false
var _buttons: Array[Button] = []
var _done := false
var _root: Control


static func open(parent: Node, p_god: String, p_on_done: Callable, p_choices := []) -> BoonChoice:
	var w := BoonChoice.new()
	w.god = p_god
	w.on_done = p_on_done
	w.choices = p_choices
	if w.choices.is_empty() and Run.boons and Run.boons.has_method("roll_choices"):
		w.choices = Run.boons.roll_choices(p_god, 3)
	var host: Node = parent if parent != null else null
	if host == null or not host.is_inside_tree():
		host = Engine.get_main_loop().root if Engine.get_main_loop() is SceneTree else null
	if host == null:
		return null
	host.add_child(w)
	return w


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	if choices.is_empty():
		Bus.toast.emit("%s безмолвствует — дары исчерпаны (+30 дирхемов)" % BoonData.god_name(god), BoonData.god_color(god))
		Run.add_dirhams(30)
		_finish({})
		return
	_was_paused = get_tree().paused
	get_tree().paused = true
	Sfx.play("gift_open")
	_build()


func _kit() -> Variant:
	if ResourceLoader.exists(UI_KIT):
		return load(UI_KIT)
	return null


func _font(bold := false) -> Font:
	var k = _kit()
	var m := "bold" if bold else "font"
	if k and k.has_method(m):
		return k.call(m)
	return null


func _style(bg: Color, border: Color, bw := 2, radius := 10) -> StyleBoxFlat:
	var k = _kit()
	if k and k.has_method("box"):
		var sb = k.call("box", bg, border, bw, radius)
		if sb is StyleBoxFlat:
			return sb
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s


func _label(text: String, size: int, color: Color, bold := false, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.03))
	l.add_theme_constant_override("outline_size", 4)
	var f := _font(bold)
	if f:
		l.add_theme_font_override("font", f)
	return l


func _build() -> void:
	var gc := BoonData.god_color(god)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var k = _kit()
	if k and k.has_method("theme"):
		var th = k.call("theme")
		if th is Theme:
			_root.theme = th
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.04, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var glow := ColorRect.new()
	glow.color = Color(gc.r, gc.g, gc.b, 0.08)
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(glow)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	center.add_child(col)

	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	var gi := BoonData.god_icon(god)
	if gi:
		var tr := TextureRect.new()
		tr.texture = gi
		tr.custom_minimum_size = Vector2(72, 72)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		head.add_child(tr)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	head.add_child(hv)
	hv.add_child(_label("Дар духа — %s" % BoonData.god_name(god), 40, gc, true))
	hv.add_child(_label(String(BoonData.GODS.get(god, {}).get("title", "")), 20, gc.lerp(Color.WHITE, 0.5)))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	col.add_child(row)
	for i in choices.size():
		row.add_child(_card(i, choices[i]))

	col.add_child(_label("1–3 / мышь / ←→ + Enter — взять дар", 18, Color(0.75, 0.68, 0.58)))
	if not _buttons.is_empty():
		_buttons[0].grab_focus.call_deferred()
	# появление
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.18)


func _card(i: int, c: Dictionary) -> Button:
	var id: String = c.get("id", "")
	var rarity: String = c.get("rarity", "common")
	var lvl := int(c.get("level", 1))
	var gc := BoonData.god_color(BoonData.god_of(id))
	var rc := BoonData.rarity_color(rarity)
	var b := Button.new()
	b.custom_minimum_size = Vector2(320, 400)
	b.focus_mode = Control.FOCUS_ALL
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := Color(0.12, 0.075, 0.06, 0.97)
	b.add_theme_stylebox_override("normal", _style(bg, rc, 3, 12))
	b.add_theme_stylebox_override("hover", _style(bg.lightened(0.08), rc.lightened(0.3), 4, 12))
	b.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), Color(1, 1, 1, 0.85), 3, 12))
	b.add_theme_stylebox_override("pressed", _style(bg.darkened(0.2), gc, 4, 12))
	b.pressed.connect(_pick.bind(i))
	b.mouse_entered.connect(func(): b.grab_focus(); Sfx.play("ui_hover", -10.0))

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 18
	v.offset_right = -18
	v.offset_top = 16
	v.offset_bottom = -16
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 8)
	b.add_child(v)

	var key := _label("[%d]" % (i + 1), 16, Color(0.7, 0.62, 0.52))
	v.add_child(key)
	var ic := TextureRect.new()
	ic.texture = BoonData.icon(id, rarity)
	ic.custom_minimum_size = Vector2(76, 76)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic)
	v.add_child(_label(BoonData.title_of(id), 26, gc.lerp(Color.WHITE, 0.25), true))
	var meta := "%s · %s" % [BoonData.SLOT_TITLE.get(BoonData.slot_of(id), ""), BoonData.RARITY_TITLE.get(rarity, "")]
	if lvl > 1 or c.get("upgrade", false):
		meta += " · ур. %d" % lvl
	v.add_child(_label(meta, 17, rc))
	var sep := ColorRect.new()
	sep.color = Color(rc.r, rc.g, rc.b, 0.5)
	sep.custom_minimum_size = Vector2(0, 2)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sep)
	var desc := _label(BoonData.describe(id, lvl, rarity), 19, Color(0.95, 0.9, 0.82))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(280, 0)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(desc)
	if c.get("upgrade", false):
		v.add_child(_label("Улучшение уже взятого дара", 16, Color(0.55, 0.9, 0.5)))
	elif String(c.get("replaces", "")) != "":
		v.add_child(_label("Заменит: " + BoonData.title_of(c["replaces"]), 16, Color(1.0, 0.5, 0.42)))
	for ch in v.get_children():
		if ch is Control:
			(ch as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons.append(b)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if _done or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var kc := (event as InputEventKey).keycode
	var idx := -1
	match kc:
		KEY_1, KEY_KP_1: idx = 0
		KEY_2, KEY_KP_2: idx = 1
		KEY_3, KEY_KP_3: idx = 2
	if idx >= 0 and idx < choices.size():
		get_viewport().set_input_as_handled()
		_pick(idx)


## Выбрать вариант programmatically (для тестов и геймпада).
func pick(i: int) -> void:
	_pick(i)


func _pick(i: int) -> void:
	if _done or i < 0 or i >= choices.size():
		return
	var c: Dictionary = choices[i]
	if Run.boons and Run.boons.has_method("take_choice"):
		Run.boons.take_choice(c)
	elif Run.boons:
		Run.boons.add_boon(c["id"])
	Sfx.play("gift_take")
	Bus.toast.emit("Дар: " + BoonData.title_of(c["id"]), BoonData.god_color(BoonData.god_of(c["id"])))
	_finish(c)


func _finish(c: Dictionary) -> void:
	if _done:
		return
	_done = true
	if is_inside_tree():
		get_tree().paused = _was_paused
	if on_done.is_valid():
		on_done.call(c)
	queue_free()
