extends Control
## Главное меню «TAMYR: Steppe of Ancestors / Тамыр: Степь Предков».
## Фон — закатное небо (assets/bg/sky_day.jpg) + слои курганов/руин с медленным параллаксом, тлеющие искры.
## Кнопки: «Начать» / «Продолжить» (→ Run.goto_hub()), «Сбросить прогресс» (подтверждение → Meta.reset_save()), «Выход».
## При первом запуске (Meta.stats.runs == 0) перед Хабом — короткий пролог.

const PROLOGUE := [
	"Над степью стоит Байтерек — Древо-Мира. Его корни держат землю, ветви — небо, а в листьях живут имена предков.",
	"Но с востока поползла Кара-Тұман — чёрная Мгла. Она пьёт имена, и духи рода забывают, кем были.",
	"Последний хранитель родового огня — батыр Кайсар. Пока огонь горит в его груди, корни Байтерека возвращают его к очагу Стойбища, сколько бы раз он ни пал.",
	"Дирхемы сгорают со смертью. Пепел Тамыра — остаётся.",
]

var _layers: Array = []      ## [[TextureRect, скорость, амплитуда]]
var _t := 0.0
var _menu: VBoxContainer
var _confirm: Control
var _prologue: Control
var _note: Label
var _start_btn: Button
var _embers: CPUParticles2D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var th := HubWindow.k_theme()
	if th:
		theme = th
	_build_bg()
	_build_menu()
	Sfx.music("calm")
	Run.active = false


func _tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func _build_bg() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.35, 0.17, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var sky := TextureRect.new()
	sky.texture = _tex("res://assets/bg/sky_day.jpg")
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)
	_layers.append([sky, 0.05, 8.0])
	# силуэты: дальние руины, курганы и балбалы
	_add_sprite("res://assets/bg/ruins_far_0.png", Vector2(0.05, 0.6), 0.42, Color(0.6, 0.35, 0.3, 0.85), 0.12, 14.0)
	_add_sprite("res://assets/bg/kurgan_0.png", Vector2(0.62, 0.58), 0.38, Color(0.55, 0.38, 0.4), 0.2, 22.0)
	_add_sprite("res://assets/bg/stone_0.png", Vector2(0.86, 0.6), 0.36, Color(0.35, 0.22, 0.2), 0.3, 30.0)
	_add_sprite("res://assets/bg/stone_3.png", Vector2(0.02, 0.66), 0.3, Color(0.3, 0.18, 0.15), 0.3, 30.0)
	# нижнее затемнение
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0.05, 0.02, 0.02, 0.85))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var shade := TextureRect.new()
	shade.texture = gt
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	# искры костра
	_embers = CPUParticles2D.new()
	_embers.amount = 60
	_embers.lifetime = 6.0
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_embers.emission_rect_extents = Vector2(900, 10)
	_embers.direction = Vector2(0.2, -1)
	_embers.spread = 25.0
	_embers.gravity = Vector2(8, -10)
	_embers.initial_velocity_min = 25.0
	_embers.initial_velocity_max = 70.0
	_embers.scale_amount_min = 1.5
	_embers.scale_amount_max = 3.5
	var eg := Gradient.new()
	eg.set_color(0, Color(1, 0.8, 0.35, 1))
	eg.set_color(1, Color(1, 0.3, 0.05, 0))
	_embers.color_ramp = eg
	add_child(_embers)


func _add_sprite(path: String, pos_frac: Vector2, height_frac: float, tint: Color, speed: float, amp: float) -> void:
	var t := _tex(path)
	if t == null:
		return
	var r := TextureRect.new()
	r.texture = t
	r.modulate = tint
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_meta("pos_frac", pos_frac)
	r.set_meta("h_frac", height_frac)
	r.set_meta("aspect", float(t.get_width()) / float(t.get_height()))
	add_child(r)
	_layers.append([r, speed, amp])


func _build_menu() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.anchor_left = 0.0
	col.anchor_right = 1.0
	col.offset_top = 70
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var t1 := HubWindow.k_title("TAMYR", 96, Color(1.0, 0.86, 0.5))
	col.add_child(t1)
	col.add_child(HubWindow.k_title("Steppe of Ancestors", 34, Color(1.0, 0.93, 0.8)))
	col.add_child(HubWindow.k_title("Тамыр: Степь Предков", 30, Color(0.55, 0.95, 0.88)))
	var center := CenterContainer.new()
	center.anchor_left = 0.0
	center.anchor_right = 1.0
	center.anchor_top = 0.5
	center.anchor_bottom = 1.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 14)
	center.add_child(_menu)
	var first := int(Meta.stats.get("runs", 0)) == 0
	_start_btn = HubWindow.k_button("Начать" if first else "Продолжить", _on_start, 320)
	_menu.add_child(_start_btn)
	_menu.add_child(HubWindow.k_button("Сбросить прогресс", _on_reset, 320))
	_menu.add_child(HubWindow.k_button("Выход", _on_quit, 320))
	_note = HubWindow.k_label("", 18, Color(0.85, 0.8, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	_menu.add_child(_note)
	_refresh_note()
	_start_btn.grab_focus.call_deferred()
	var foot := HubWindow.k_label("Пепел Тамыра сохраняется между походами  ·  ЛКМ/ПКМ — атаки, Shift — рывок, E — действие", 15, Color(0.8, 0.72, 0.62), HORIZONTAL_ALIGNMENT_CENTER)
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.anchor_right = 1.0
	foot.offset_top = -34
	add_child(foot)


func _refresh_note() -> void:
	var s: Dictionary = Meta.stats
	if int(s.get("runs", 0)) == 0:
		_note.text = ""
	else:
		_note.text = "Походов: %d   ·   Побед: %d   ·   Пепел: %d" % [int(s.get("runs", 0)), int(s.get("victories", 0)), Meta.ash]


func _process(delta: float) -> void:
	_t += delta
	var vs := size if size.x > 0 else get_viewport_rect().size
	for L in _layers:
		var r: Control = L[0]
		var dx := sin(_t * float(L[1])) * float(L[2])
		if r.has_meta("pos_frac"):
			var pf: Vector2 = r.get_meta("pos_frac")
			var h: float = vs.y * float(r.get_meta("h_frac"))
			var w: float = h * float(r.get_meta("aspect"))
			r.size = Vector2(w, h)
			r.position = Vector2(pf.x * vs.x + dx, pf.y * vs.y + vs.y * 0.4 - h)
		else:
			r.position.x = dx - L[2]
			r.size = vs + Vector2(float(L[2]) * 2.0, 0)
	if _embers:
		_embers.position = Vector2(vs.x * 0.5, vs.y + 10)


# ================================================================ кнопки
func _on_start() -> void:
	if int(Meta.stats.get("runs", 0)) == 0 and not ("intro" in Meta.story.get("seen", [])):
		_show_prologue()
		return
	Run.goto_hub()


func _show_prologue() -> void:
	if _prologue:
		return
	_menu.visible = false
	_prologue = Control.new()
	_prologue.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_prologue)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.02, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prologue.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prologue.add_child(c)
	var p := HubWindow.k_panel(Vector2(820, 0))
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(HubWindow.k_title("Корни Забвения", 40))
	var lines: Array = []
	for i in PROLOGUE.size():
		var l := HubWindow.k_label(PROLOGUE[i], 21, Color(0.95, 0.9, 0.82))
		l.modulate.a = 0.0
		v.add_child(l)
		lines.append(l)
	var go := HubWindow.k_button("В путь", func(): Run.goto_hub(), 260)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(go)
	v.add_child(hb)
	var tw := create_tween()
	for l in lines:
		tw.tween_property(l, "modulate:a", 1.0, 0.9)
	go.grab_focus.call_deferred()
	Sfx.play("dombra", -6.0, 0.0)


func _on_reset() -> void:
	if _confirm:
		return
	_confirm = Control.new()
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_confirm)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.02, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(c)
	var p := HubWindow.k_panel(Vector2(560, 0), Color(0.88, 0.25, 0.22))
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(HubWindow.k_title("Сбросить прогресс?", 32, Color(1, 0.6, 0.5)))
	v.add_child(HubWindow.k_label("Пепел, Сандык, оружие, аспекты, кюи и сюжет будут забыты. Это нельзя отменить.", 19, Color(0.95, 0.9, 0.82), HORIZONTAL_ALIGNMENT_CENTER))
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 18)
	v.add_child(h)
	var no := HubWindow.k_button("Отмена", _close_confirm, 200)
	h.add_child(no)
	h.add_child(HubWindow.k_button("Сбросить", _do_reset, 200))
	no.grab_focus.call_deferred()


func _close_confirm() -> void:
	if _confirm:
		_confirm.queue_free()
		_confirm = null
	_start_btn.grab_focus.call_deferred()


func _do_reset() -> void:
	Meta.reset_save()
	_close_confirm()
	_start_btn.text = "Начать"
	_refresh_note()
	_note.text = "Прогресс сброшен. Степь ждёт нового хранителя."


func _on_quit() -> void:
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if _confirm:
			_close_confirm()
			get_viewport().set_input_as_handled()
