class_name RoomUi
extends CanvasLayer
## Окна и экранные элементы комнат (модуль D) в стиле UiKit (если он есть):
##   RoomUi.open_window(host, title, accent) -> RoomUi   — модальное окно с паузой мира; win.body — VBoxContainer
##       win.add_row(text, button_text, on_press, enabled) / win.add_text(text) / win.close()  ; Esc / кнопка «Закрыть»
##   RoomUi.BossBar   — полоса босса внизу экрана (set_target(enemy))
##   RoomUi.BigTimer  — крупный таймер «Печати Номада» вверху (set_time(sec), set_info(text))

signal closed

const UI_KIT := "res://game/ui/ui_kit.gd"

var body: VBoxContainer
var _root: Control
var _was_paused := false
var _closed := false
var _accent := Color(0.88, 0.72, 0.36)


static func kit() -> Variant:
	return RoomUtil.script_of(UI_KIT)


static func styled_box(bg: Color, border: Color, bw := 2, radius := 10) -> StyleBoxFlat:
	var k: Variant = kit()
	if k and k.has_method("box"):
		var sb: Variant = k.box(bg, border, bw, radius)
		if sb is StyleBoxFlat:
			return sb
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


static func make_label(text: String, size := 20, color := Color(0.95, 0.9, 0.82), bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.03))
	l.add_theme_constant_override("outline_size", 5)
	var k: Variant = kit()
	var m := "bold" if bold else "font"
	if k and k.has_method(m):
		var f: Variant = k.call(m)
		if f is Font:
			l.add_theme_font_override("font", f)
	return l


static func open_window(host: Node, title: String, accent := Color(0.88, 0.72, 0.36)) -> RoomUi:
	var w := RoomUi.new()
	w._accent = accent
	w._title = title
	if host == null or not host.is_inside_tree():
		return null
	host.add_child(w)
	return w


var _title := ""


func _ready() -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("room_window")
	_was_paused = get_tree().paused
	get_tree().paused = true
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var k: Variant = kit()
	if k and k.has_method("theme"):
		var th: Variant = k.theme()
		if th is Theme:
			_root.theme = th
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.03, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	panel.add_theme_stylebox_override("panel", styled_box(Color(0.14, 0.09, 0.07, 0.97), _accent, 3, 12))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var t := make_label(_title, 34, _accent, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	col.add_child(body)
	var close_btn := _button("Закрыть (Esc)", close)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(close_btn)
	close_btn.grab_focus.call_deferred()
	Sfx.play("ui_click")


func _button(text: String, cb: Callable) -> Button:
	var k: Variant = kit()
	if k and k.has_method("button"):
		var b: Variant = k.button(text, cb, 220)
		if b is Button:
			return b
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(220, 40)
	btn.pressed.connect(cb)
	return btn


func add_text(text: String, color := Color(0.85, 0.78, 0.68), size := 18) -> Label:
	var l := make_label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	body.add_child(l)
	return l


## Строка: иконка (опц.) + текст + кнопка справа.
func add_row(text: String, button_text: String, on_press: Callable, enabled := true, icon: Texture2D = null, color := Color(0.95, 0.9, 0.82)) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	if icon:
		var tr := TextureRect.new()
		tr.texture = icon
		tr.custom_minimum_size = Vector2(40, 40)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(tr)
	var l := make_label(text, 19, color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(340, 0)
	row.add_child(l)
	var b := _button(button_text, on_press)
	b.custom_minimum_size = Vector2(180, 40)
	b.disabled = not enabled
	row.add_child(b)
	body.add_child(row)
	return b


func clear_body() -> void:
	for c in body.get_children():
		c.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if _closed:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if _closed:
		return
	_closed = true
	if is_inside_tree():
		get_tree().paused = _was_paused
	closed.emit()
	queue_free()


# ================================================================ полоса босса
class BossBar extends CanvasLayer:
	var target: Node = null
	var _bar: ProgressBar
	var _armor: ProgressBar
	var _name: Label
	var _shown := 0.0

	func _ready() -> void:
		layer = 30
		add_to_group("boss_bar")
		var root := Control.new()
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)
		var box := VBoxContainer.new()
		box.anchor_left = 0.2
		box.anchor_right = 0.8
		box.anchor_top = 1.0
		box.anchor_bottom = 1.0
		box.offset_top = -92
		box.offset_bottom = -24
		box.add_theme_constant_override("separation", 4)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(box)
		_name = RoomUi.make_label("", 26, Color(1.0, 0.86, 0.7), true)
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_name)
		_bar = _mk_bar(Color(0.85, 0.15, 0.12), 20)
		box.add_child(_bar)
		_armor = _mk_bar(Color(0.72, 0.76, 0.82), 8)
		box.add_child(_armor)

	func _mk_bar(c: Color, h: int) -> ProgressBar:
		var b := ProgressBar.new()
		b.show_percentage = false
		b.custom_minimum_size = Vector2(0, h)
		b.max_value = 1.0
		b.step = 0.0
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.05, 0.03, 0.03, 0.85)
		bg.border_color = Color(0.6, 0.45, 0.25)
		bg.set_border_width_all(2)
		bg.set_corner_radius_all(4)
		var fill := StyleBoxFlat.new()
		fill.bg_color = c
		fill.set_corner_radius_all(3)
		b.add_theme_stylebox_override("background", bg)
		b.add_theme_stylebox_override("fill", fill)
		return b

	func set_target(e: Node) -> void:
		target = e
		var n := ""
		if e:
			var dn: Variant = e.get("display_name")
			n = String(dn) if dn != null and String(dn) != "" else "Владыка"
		_name.text = n

	func _process(delta: float) -> void:
		if target == null or not is_instance_valid(target):
			_bar.value = 0.0
			_armor.visible = false
			return
		var hp := float(target.get("hp") if target.get("hp") != null else 0.0)
		var mhp := maxf(1.0, float(target.get("max_hp") if target.get("max_hp") != null else 1.0))
		var ar := float(target.get("armor") if target.get("armor") != null else 0.0)
		var mar := float(target.get("max_armor") if target.get("max_armor") != null else 0.0)
		_shown = lerpf(_shown, hp / mhp, 1.0 - exp(-8.0 * delta))
		_bar.value = _shown
		_armor.visible = mar > 0.0
		_armor.value = ar / maxf(1.0, mar)


# ================================================================ таймер Печати
class BigTimer extends CanvasLayer:
	var _label: Label
	var _info: Label

	func _ready() -> void:
		layer = 30
		var root := Control.new()
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)
		var box := VBoxContainer.new()
		box.anchor_left = 0.3
		box.anchor_right = 0.7
		box.offset_top = 70
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(box)
		_label = RoomUi.make_label("45", 72, Color(0.85, 0.5, 1.0), true)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_label)
		_info = RoomUi.make_label("", 22, Color(0.95, 0.85, 1.0))
		_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_info)

	func set_time(t: float) -> void:
		_label.text = "%d" % ceili(maxf(0.0, t))
		_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25) if t < 10.0 else Color(0.85, 0.5, 1.0))

	func set_info(text: String) -> void:
		_info.text = text
