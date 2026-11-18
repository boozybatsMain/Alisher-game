class_name DialogueBox
extends CanvasLayer
## Диалоговое окно: слушает Bus.dialogue_requested(lines), lines = [{speaker, text, portrait?: путь к текстуре, color?: Color}].
## Печатает текст по буквам; interact / attack / Enter / Пробел — ускорить или дальше. На время диалога мир на паузе.
##
## API:
##   DialogueBox.ensure(tree) -> DialogueBox  — единственное окно (живёт под root, переживает смену сцен). HUD вызывает сам.
##   DialogueBox.show_lines(tree, lines)      — показать без Bus
##   DialogueBox.is_open() -> bool
##   DialogueBox.blocks_input() -> bool       — окно открыто или только что закрылось (герой не жмёт interact повторно)
##   сигнал closed                            — диалог дочитан (ensure(tree).closed.connect(...))
##   pause_world := true                      — ставить ли get_tree().paused на время диалога

signal closed

const CHARS_PER_SEC := 48.0

static var _inst: DialogueBox = null
static var _closed_msec := -100000

var pause_world := true
var _lines: Array = []
var _index := 0
var _shown := 0.0
var _typing := false
var _paused_by_me := false
var _open := false
var _input_cd := 0.0

var _root: Control
var _panel: PanelContainer
var _speaker: Label
var _text: RichTextLabel
var _portrait: TextureRect
var _hint: Label


static func ensure(tree: SceneTree) -> DialogueBox:
	if _inst != null and is_instance_valid(_inst):
		return _inst
	var d := DialogueBox.new()
	d.name = "DialogueBox"
	_inst = d
	tree.root.add_child.call_deferred(d)
	return d


static func show_lines(tree: SceneTree, lines: Array) -> void:
	ensure(tree).open(lines)


static func is_open() -> bool:
	return _inst != null and is_instance_valid(_inst) and _inst._open


static func blocks_input() -> bool:
	return is_open() or Time.get_ticks_msec() - _closed_msec < 300


func _init() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _ready() -> void:
	if _inst == null or not is_instance_valid(_inst):
		_inst = self
	elif _inst != self:
		queue_free()
		return
	if not Bus.dialogue_requested.is_connected(open):
		Bus.dialogue_requested.connect(open)
	var tree := get_tree()
	if tree.has_signal("scene_changed"):
		tree.connect("scene_changed", _on_scene_changed)


func _exit_tree() -> void:
	if _inst == self:
		_inst = null
	if _paused_by_me and is_inside_tree():
		get_tree().paused = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.theme()
	_root.visible = false
	add_child(_root)
	_panel = UiKit.panel(Vector2(0, 210))
	_panel.anchor_left = 0.12
	_panel.anchor_right = 0.88
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = -260
	_panel.offset_bottom = -36
	_root.add_child(_panel)
	var h := UiKit.hbox(22)
	_panel.add_child(h)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(150, 150)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.visible = false
	h.add_child(_portrait)
	var v := UiKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	_speaker = UiKit.title("", 28, UiKit.GOLD)
	_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(_speaker)
	v.add_child(UiKit.ornament())
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(0, 90)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", 24)
	_text.add_theme_font_size_override("bold_font_size", 24)
	_text.add_theme_color_override("default_color", UiKit.TEXT)
	v.add_child(_text)
	_hint = UiKit.label("E / ЛКМ — далее", 16, UiKit.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	v.add_child(_hint)


func open(lines: Array) -> void:
	if lines.is_empty():
		return
	if _open:
		_lines.append_array(lines)   # дописываем в очередь
		return
	_lines = lines.duplicate()
	_index = 0
	_open = true
	_root.visible = true
	_input_cd = 0.2
	if pause_world and is_inside_tree() and not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.15)
	_show_line()


func _show_line() -> void:
	var l = _lines[_index]
	var speaker := ""
	var text := ""
	var portrait := ""
	var col := UiKit.GOLD
	if l is Dictionary:
		speaker = str(l.get("speaker", ""))
		text = str(l.get("text", ""))
		portrait = str(l.get("portrait", ""))
		var c = l.get("color", null)
		if c is Color:
			col = c
	else:
		text = str(l)
	_speaker.text = speaker
	_speaker.visible = speaker != ""
	_speaker.add_theme_color_override("font_color", col)
	_text.text = text
	_text.visible_characters = 0
	_shown = 0.0
	_typing = true
	_portrait.visible = false
	if portrait != "" and ResourceLoader.exists(portrait):
		var t = load(portrait)
		if t is Texture2D:
			_portrait.texture = t
			_portrait.visible = true
	_hint.text = "E / ЛКМ — далее" if _index < _lines.size() - 1 else "E / ЛКМ — закрыть"


func _process(delta: float) -> void:
	if not _open:
		return
	var real := delta / maxf(Engine.time_scale, 0.01)
	_input_cd -= real
	if _typing:
		_shown += real * CHARS_PER_SEC
		var total := _text.get_total_character_count()
		_text.visible_characters = int(_shown)
		if _shown >= total:
			_text.visible_characters = -1
			_typing = false
	if _input_cd <= 0.0 and (Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("attack")
			or Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("jump")):
		advance()


## Ускорить печать или перейти к следующей реплике.
func advance() -> void:
	if not _open:
		return
	_input_cd = 0.12
	if _typing:
		_typing = false
		_text.visible_characters = -1
		return
	Sfx.play("ui_click", -10.0)
	_index += 1
	if _index >= _lines.size():
		close()
	else:
		_show_line()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	_lines = []
	_closed_msec = Time.get_ticks_msec()
	if _paused_by_me and is_inside_tree():
		get_tree().paused = false
	_paused_by_me = false
	closed.emit()


func _on_scene_changed() -> void:
	if _open:
		close()
