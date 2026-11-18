class_name HubWindow
extends CanvasLayer
## Базовое окно Хаба (оружейная, Сандык): затемнение + панель по центру, закрытие по Esc / interact / кнопке.
## На время окна управление героем выключено. Стили — из UiKit (game/ui/ui_kit.gd), если он есть, иначе свои.
##
## API:
##   win.open_on(parent: Node, player: Node)  — добавить в дерево и показать
##   win.close()                              — закрыть (сигнал closed)
##   win.body: VBoxContainer                  — содержимое панели (наследники заполняют в _fill())
##   win.refresh()                            — перестроить содержимое (после покупки)
##   HubWindow.kit() -> GDScript|null         — UiKit, если доступен
##   HubWindow.k_label/k_title/k_button/k_panel — обёртки UiKit с запасным вариантом

signal closed

const UI_KIT := "res://game/ui/ui_kit.gd"
const C_GOLD := Color(0.88, 0.72, 0.36)
const C_TEXT := Color(0.95, 0.90, 0.82)
const C_MUTED := Color(0.70, 0.62, 0.52)
const C_TEAL := Color(0.33, 0.85, 0.80)
const C_RED := Color(0.88, 0.25, 0.22)

static var open_count := 0           ## сколько окон Хаба открыто (герой не реагирует на ввод)

var player: Node = null
var body: VBoxContainer
var _root: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _closing := false
var _opened_msec := 0


static func kit() -> GDScript:
	if ResourceLoader.exists(UI_KIT):
		var s = load(UI_KIT)
		if s is GDScript and (s as GDScript).can_instantiate():
			return s
	return null


static func k_label(text: String, size := 20, color := C_TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var k := kit()
	if k:
		return k.label(text, size, color, align)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.07, 0.04, 0.03))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func k_title(text: String, size := 40, color := C_GOLD) -> Label:
	var k := kit()
	if k:
		return k.title(text, size, color)
	var l := k_label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_constant_override("outline_size", 8)
	return l


static func k_button(text: String, on_press: Callable = Callable(), min_w := 220) -> Button:
	var k := kit()
	if k:
		var kb: Button = k.button(text, on_press, min_w)
		kb.custom_minimum_size.y = 44
		kb.add_theme_font_size_override("font_size", 20)
		return kb
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(func(): Sfx.play("ui_click", -6.0))
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


static func k_panel(min_size := Vector2.ZERO, accent := C_GOLD) -> PanelContainer:
	var k := kit()
	if k:
		return k.panel(min_size, accent)
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.10, 0.08, 0.96)
	sb.border_color = accent
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(24)
	p.add_theme_stylebox_override("panel", sb)
	return p


static func k_theme() -> Theme:
	var k := kit()
	if k:
		return k.theme()
	return null


func _init() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS


func open_on(parent: Node, p_player: Node) -> void:
	player = p_player
	parent.add_child(self)


func _ready() -> void:
	open_count += 1
	_opened_msec = Time.get_ticks_msec()
	if player and is_instance_valid(player) and player.has_method("set_input_enabled"):
		player.set_input_enabled(false)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var th := k_theme()
	if th:
		_root.theme = th
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.02, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_panel = k_panel(Vector2(_panel_width(), 0), _accent())
	center.add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	_panel.add_child(outer)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(_panel_width() - 60, _panel_height())
	outer.add_child(_scroll)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(body)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(bottom)
	var close_b := k_button("Закрыть  [Esc]", close, 240)
	bottom.add_child(close_b)
	refresh()
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.15)
	close_b.grab_focus.call_deferred()


func _exit_tree() -> void:
	open_count = maxi(0, open_count - 1)


func _panel_width() -> float:
	return 860.0


func _panel_height() -> float:
	return 560.0


func _accent() -> Color:
	return C_GOLD


## Перестроить содержимое.
func refresh() -> void:
	if body == null:
		return
	var keep_scroll := _scroll.scroll_vertical if _scroll else 0
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	_fill()
	if _scroll:
		_scroll.set_deferred("scroll_vertical", keep_scroll)


## Наследники заполняют body.
func _fill() -> void:
	pass


func _input(event: InputEvent) -> void:
	if _closing:
		return
	if Time.get_ticks_msec() - _opened_msec < 250:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if _closing:
		return
	_closing = true
	HubWindow.reenable_player(player, self)
	closed.emit()
	if is_inside_tree() and _root:
		var tw := create_tween()
		tw.tween_property(_root, "modulate:a", 0.0, 0.12)
		tw.tween_callback(queue_free)
	else:
		queue_free()


## Вернуть герою управление с небольшой задержкой (чтобы та же клавиша interact не открыла окно снова).
static func reenable_player(p: Node, ctx: Node) -> void:
	if p == null or not is_instance_valid(p) or not p.has_method("set_input_enabled"):
		return
	if ctx == null or not ctx.is_inside_tree():
		p.set_input_enabled(true)
		return
	ctx.get_tree().create_timer(0.2, true).timeout.connect(func():
		if is_instance_valid(p) and HubWindow.open_count <= 0:
			p.set_input_enabled(true))


## Строка-разделитель.
func sep() -> Control:
	var k := kit()
	if k:
		return k.ornament(C_GOLD)
	var r := ColorRect.new()
	r.color = Color(C_GOLD, 0.5)
	r.custom_minimum_size = Vector2(0, 2)
	return r


## Иконка пепла + число.
func ash_line() -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(nowrap(k_label("Пепел Тамыра:", 22, C_MUTED)))
	h.add_child(nowrap(k_label(str(Meta.ash), 26, Color(0.75, 0.85, 1.0))))
	return h


## Метка без переноса слов (для строк внутри HBoxContainer).
static func nowrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l
