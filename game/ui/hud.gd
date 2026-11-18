class_name Hud
extends CanvasLayer
## HUD забега и Хаба: здоровье, заряды рывка, дирхемы, пепел, оружие+аспект, кюй, иконки даров (Tab — список с описаниями),
## номер комнаты/биом, волна, тосты (Bus.toast), всплывающие числа урона (Bus.damage_number → Label3D в мире),
## меню паузы (Esc), экран смерти «Корни возвращают тебя…», вспышка при воскрешении.
## Создаётся через Run.spawn_hud(parent). Сам создаёт DialogueBox (DialogueBox.ensure).
##
## Сверх контракта:
##   Hud.find(tree) -> Hud           — текущий HUD
##   hud.toast(text, color)          — то же, что Bus.toast
##   hud.set_visible_hud(on)         — спрятать/показать всё (крупный план домбры и т.п.)
##   hud.open_pause() / close_pause()
##   Hud.boon_info(id) -> {title, desc, god, slot, rarity}  — сведения о даре из game/boons/boon_data.gd (если есть)
##   Hud.weapon_title(id, aspect) -> String

const BOON_DATA := "res://game/boons/boon_data.gd"
const WEAPON_DATA := "res://game/weapons/weapon_data.gd"
const BIOMES := ["Осквернённая степь", "Корни Байтерека", "Чертог Ерлика"]
const WEAPON_NAMES := {"sword": "Меч", "spear": "Копьё", "shield": "Щит", "bow": "Лук", "gauntlets": "Железные перчатки"}
const ROOM_TYPES := {"combat": "Битва", "elite": "Элита", "boss": "Владыка", "merchant": "Лавка Караванщика",
	"duel": "Спор Духов", "rest": "Привал"}
const NUMBER_COLORS := {
	"normal": Color(1, 1, 1), "special": Color(0.45, 0.85, 1.0), "crit": Color(1.0, 0.86, 0.2),
	"armor": Color(0.68, 0.7, 0.74), "dot": Color(1.0, 0.6, 0.2), "heal": Color(0.45, 1.0, 0.45),
	"player": Color(1.0, 0.25, 0.22),
}
const RARITY_COLORS := {"common": Color(0.92, 0.9, 0.85), "rare": Color(0.4, 0.7, 1.0), "epic": Color(0.75, 0.45, 1.0),
	"legendary": Color(1.0, 0.8, 0.3), "duo": Color(0.4, 1.0, 0.7)}

static var _boon_cache := {}

var _root: Control
var _hp_bar: _Bar
var _hp_text: Label
var _pips: _Pips
var _dirhams: Label
var _ash: Label
var _weapon: Label
var _kui: Label
var _room: Label
var _wave: Label
var _boon_row: HBoxContainer
var _boon_panel: PanelContainer
var _boon_list: VBoxContainer
var _toasts: VBoxContainer
var _pause: Control
var _death: ColorRect
var _death_label: Label
var _flash: ColorRect
var _vignette: TextureRect
var _paused_by_me := false
var _gold_box: HBoxContainer
var _hp_box: Control


static func find(tree: SceneTree) -> Hud:
	for n in tree.get_nodes_in_group("hud"):
		if n is Hud:
			return n
	return null


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")
	_build()
	Bus.hp_changed.connect(_on_hp)
	Bus.dash_charges_changed.connect(_on_dash)
	Bus.dirhams_changed.connect(func(v: int): _dirhams.text = str(v); _pop(_dirhams))
	Bus.ash_changed.connect(func(v: int): _ash.text = str(v); _pop(_ash))
	Bus.boons_changed.connect(_refresh_boons)
	Bus.weapon_changed.connect(func(_id: String, _a: int): _refresh_weapon())
	Bus.room_entered.connect(func(_r: Dictionary): _refresh_room())
	Bus.wave_started.connect(_on_wave)
	Bus.room_cleared.connect(func(): _wave.text = "")
	Bus.toast.connect(toast)
	Bus.damage_number.connect(_on_damage_number)
	Bus.player_died.connect(_on_died)
	Bus.player_revived.connect(_on_revived)
	Bus.player_damaged.connect(_on_player_damaged)
	DialogueBox.ensure(get_tree())
	_refresh_all()


# ================================================================ построение
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.theme()
	add_child(_root)

	_vignette = TextureRect.new()
	if ResourceLoader.exists("res://assets/fx/vignette.png"):
		_vignette.texture = load("res://assets/fx/vignette.png")
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate = Color(1, 0.1, 0.08, 0.0)
	_root.add_child(_vignette)

	# --- левый верх: здоровье, рывки, валюты
	var tl := UiKit.vbox(6)
	tl.position = Vector2(28, 22)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tl)
	_hp_box = Control.new()
	_hp_box.custom_minimum_size = Vector2(380, 34)
	tl.add_child(_hp_box)
	_hp_bar = _Bar.new()
	_hp_bar.size = Vector2(380, 30)
	_hp_box.add_child(_hp_bar)
	_hp_text = UiKit.label("100 / 100", 19, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hp_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hp_text.size = Vector2(380, 30)
	_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_box.add_child(_hp_text)
	_pips = _Pips.new()
	_pips.custom_minimum_size = Vector2(200, 22)
	tl.add_child(_pips)
	_gold_box = UiKit.hbox(18)
	tl.add_child(_gold_box)
	_gold_box.add_child(_icon_label(_Coin.new(), UiKit.GOLD))
	_dirhams = _gold_box.get_child(0).get_child(1) as Label
	var ash_box := _icon_label(_AshIcon.new(), Color(0.85, 0.85, 0.95))
	_gold_box.add_child(ash_box)
	_ash = ash_box.get_child(1) as Label

	# --- правый верх: комната/биом, оружие, кюй
	var tr := UiKit.vbox(2)
	tr.anchor_left = 1.0
	tr.anchor_right = 1.0
	tr.offset_left = -520
	tr.offset_right = -28
	tr.offset_top = 22
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tr)
	_room = UiKit.label("", 22, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	tr.add_child(_room)
	_weapon = UiKit.label("", 19, UiKit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	tr.add_child(_weapon)
	_kui = UiKit.label("", 17, UiKit.TEAL, HORIZONTAL_ALIGNMENT_RIGHT)
	tr.add_child(_kui)

	# --- центр верх: волна
	_wave = UiKit.label("", 22, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_wave.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wave.offset_left = -200
	_wave.offset_right = 200
	_wave.offset_top = 20
	_root.add_child(_wave)

	# --- тосты
	_toasts = UiKit.vbox(6)
	_toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toasts.offset_left = -400
	_toasts.offset_right = 400
	_toasts.offset_top = 120
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)

	# --- левый низ: дары
	_boon_row = UiKit.hbox(6)
	_boon_row.anchor_top = 1.0
	_boon_row.anchor_bottom = 1.0
	_boon_row.offset_left = 28
	_boon_row.offset_top = -78
	_boon_row.offset_bottom = -24
	_boon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_boon_row)

	# --- панель даров (Tab)
	_boon_panel = UiKit.panel(Vector2(620, 0))
	_boon_panel.anchor_left = 0.0
	_boon_panel.anchor_top = 0.0
	_boon_panel.position = Vector2(28, 170)
	_boon_panel.visible = false
	_root.add_child(_boon_panel)
	var bv := UiKit.vbox(8)
	_boon_panel.add_child(bv)
	bv.add_child(UiKit.title("Дары духов", 28))
	bv.add_child(UiKit.ornament())
	_boon_list = UiKit.vbox(8)
	bv.add_child(_boon_list)

	# --- вспышка, смерть
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	_root.add_child(_flash)
	_death = ColorRect.new()
	_death.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death.color = Color(0.06, 0.02, 0.02, 0.0)
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.visible = false
	_root.add_child(_death)
	_death_label = UiKit.title("Корни возвращают тебя…", 52, UiKit.GOLD)
	_death_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death.add_child(_death_label)

	_build_pause()


func _icon_label(icon: Control, color: Color) -> HBoxContainer:
	var h := UiKit.hbox(6)
	icon.custom_minimum_size = Vector2(24, 24)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var l := UiKit.label("0", 22, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(l)
	return h


func _build_pause() -> void:
	_pause = Control.new()
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	_root.add_child(_pause)
	_pause.add_child(UiKit.dim(0.65))
	var p := UiKit.panel(Vector2(420, 0))
	var v := UiKit.vbox(14)
	p.add_child(v)
	v.add_child(UiKit.title("Пауза", 40))
	v.add_child(UiKit.ornament())
	var resume := UiKit.button("Продолжить", close_pause)
	resume.name = "Resume"
	v.add_child(resume)
	var give_up := UiKit.button("Сдаться и вернуться в Стойбище", _surrender)
	give_up.name = "Surrender"
	v.add_child(give_up)
	v.add_child(UiKit.button("В главное меню", _to_title))
	_pause.add_child(UiKit.center(p))


# ================================================================ обновления
func _refresh_all() -> void:
	_on_hp(Run.hp, Run.max_hp())
	_dirhams.text = str(Run.dirhams)
	_ash.text = str(Meta.ash)
	_gold_box.get_child(0).visible = Run.active
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("max_dash_charges"):
		_on_dash(int(p.get("dash_charges")), p.max_dash_charges())
	else:
		var mx := int(Run.stat("dash_charges"))
		_on_dash(mx, mx)
	_refresh_weapon()
	_refresh_room()
	_refresh_boons()


func _on_hp(hp: float, max_hp: float) -> void:
	_hp_bar.set_value(hp, max_hp)
	_hp_text.text = "%d / %d" % [ceili(hp), int(max_hp)]
	var low := max_hp > 0.0 and hp / max_hp < 0.25 and hp > 0.0
	_vignette.set_meta("low", low)


func _on_dash(charges: int, max_charges: int) -> void:
	_pips.charges = charges
	_pips.max_charges = max_charges
	_pips.queue_redraw()


func _refresh_weapon() -> void:
	var id := Run.weapon if Run.active else Meta.equipped_weapon
	var a := Run.aspect if Run.active else Meta.equipped_aspect
	_weapon.text = weapon_title(id, a)
	if Run.active and Run.kui != "" and Run.KUIS.has(Run.kui):
		_kui.text = "♪ Кюй «%s»: %s" % [Run.KUIS[Run.kui]["title"], Run.KUIS[Run.kui]["desc"]]
	elif not Run.active and Meta.kui_prepared != "" and Run.KUIS.has(Meta.kui_prepared):
		_kui.text = "♪ Готов кюй «%s»" % Run.KUIS[Meta.kui_prepared]["title"]
	else:
		_kui.text = ""


func _refresh_room() -> void:
	_gold_box.get_child(0).visible = Run.active
	if not Run.active:
		_room.text = "Стойбище Предков"
		return
	var biome: String = BIOMES[clampi(Run.biome, 0, BIOMES.size() - 1)]
	var t := str(Run.current_room.get("type", "combat"))
	_room.text = "%s · Комната %d" % [biome, Run.depth + 1]
	if ROOM_TYPES.has(t) and t != "combat":
		_room.text += " · " + ROOM_TYPES[t]


func _on_wave(index: int, total: int) -> void:
	_wave.text = "Волна %d / %d" % [clampi(index, 1, total), total]   # index с 1 (WaveDirector шлёт i + 1)
	_pop(_wave)


func _refresh_boons() -> void:
	for c in _boon_row.get_children():
		c.queue_free()
	for c in _boon_list.get_children():
		c.queue_free()
	var owned: Array = []
	if Run.boons and Run.boons.has_method("owned"):
		owned = Run.boons.owned()
	for b in owned:
		if not (b is Dictionary):
			continue
		var id := str(b.get("id", ""))
		var lvl := int(b.get("level", 1))
		var info := boon_info(id)
		var rarity = b.get("rarity", info.get("rarity", "common"))
		var icon := _BoonIcon.new()
		icon.color = UiKit.god_color(str(info.get("god", "")))
		icon.letter = str(info.get("title", id)).substr(0, 1).to_upper()
		icon.level = lvl
		icon.rarity_color = _rarity_color(rarity)
		icon.custom_minimum_size = Vector2(48, 48)
		icon.tooltip_text = "%s (ур. %d)\n%s" % [info.get("title", id), lvl, info.get("desc", "")]
		_boon_row.add_child(icon)
		# строка в панели
		var row := UiKit.hbox(12)
		var icon2 := _BoonIcon.new()
		icon2.color = icon.color
		icon2.letter = icon.letter
		icon2.level = lvl
		icon2.rarity_color = icon.rarity_color
		icon2.custom_minimum_size = Vector2(44, 44)
		icon2.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(icon2)
		var col := UiKit.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var god := str(info.get("god", ""))
		var head := "%s  · ур. %d" % [info.get("title", id), lvl]
		if UiKit.GOD_TITLES.has(god):
			head += "  · " + UiKit.GOD_TITLES[god]
		var slot := str(info.get("slot", ""))
		if slot != "":
			head += "  · " + {"attack": "Обычная", "special": "Особая", "dash": "Рывок", "passive": "Пассив"}.get(slot, slot)
		col.add_child(UiKit.label(head, 20, icon.rarity_color))
		var desc := str(info.get("desc", ""))
		if desc != "":
			col.add_child(UiKit.label(desc, 17, UiKit.MUTED))
		row.add_child(col)
		_boon_list.add_child(row)
	if owned.is_empty():
		_boon_list.add_child(UiKit.label("Пока ни один дух не одарил тебя.", 18, UiKit.MUTED))


func _rarity_color(r) -> Color:
	if r is int:
		return [RARITY_COLORS["common"], RARITY_COLORS["rare"], RARITY_COLORS["epic"], RARITY_COLORS["legendary"]][clampi(r, 0, 3)]
	return RARITY_COLORS.get(str(r), RARITY_COLORS["common"])


# ================================================================ данные даров/оружия (безопасно)
static func boon_info(id: String, level := 1) -> Dictionary:
	var key := "%s#%d" % [id, level]
	if _boon_cache.has(key):
		return _boon_cache[key]
	var info := {"title": id, "desc": "", "god": "", "slot": ""}
	for g in UiKit.GOD_COLORS:
		if id.begins_with(g):
			info["god"] = g
	if ResourceLoader.exists(BOON_DATA):
		var scr = load(BOON_DATA)
		if scr is Script:
			var consts: Dictionary = (scr as Script).get_script_constant_map()
			for cname in ["BOONS", "DATA", "ALL"]:
				var d = consts.get(cname, null)
				if d is Dictionary and d.has(id) and d[id] is Dictionary:
					var e: Dictionary = d[id]
					for k in ["title", "name"]:
						if e.has(k):
							info["title"] = str(e[k])
							break
					for k in ["desc", "description"]:
						if e.has(k):
							info["desc"] = str(e[k])
							break
					for k in ["god", "spirit"]:
						if e.has(k):
							info["god"] = str(e[k])
							break
					if e.has("slot"):
						info["slot"] = str(e["slot"])
					if e.has("rarity"):
						info["rarity"] = e["rarity"]
					break
			for m in (scr as Script).get_script_method_list():
				var mname := str(m.get("name", ""))
				if mname in ["describe", "description"] and (int(m.get("flags", 0)) & METHOD_FLAG_STATIC) != 0:
					var nargs: int = (m.get("args", []) as Array).size()
					var r = null
					if nargs >= 2:
						r = scr.call(mname, id, level)
					elif nargs == 1:
						r = scr.call(mname, id)
					if r is String and r != "":
						info["desc"] = r
					elif r is Dictionary:
						for k in r:
							info[k] = r[k]
					break
	_boon_cache[key] = info
	return info


static func weapon_title(id: String, a: int) -> String:
	var t: String = WEAPON_NAMES.get(id, id)
	var at := ""
	if ResourceLoader.exists(WEAPON_DATA):
		var scr = load(WEAPON_DATA)
		if scr is Script:
			var ws = (scr as Script).get_script_constant_map().get("WEAPONS", {})
			if ws is Dictionary and ws.has(id) and ws[id] is Dictionary:
				t = str(ws[id].get("title", t))
				var asp = ws[id].get("aspects", [])
				if asp is Array and a >= 0 and a < asp.size() and asp[a] is Dictionary:
					at = str(asp[a].get("title", ""))
	if at == "":
		at = "Аспект %d" % (a + 1)
	if at == t:   # базовый аспект часто называется как само оружие
		return "⚔ %s" % t
	return "⚔ %s · %s" % [t, at]


# ================================================================ события
func toast(text: String, color := Color(1, 0.93, 0.75)) -> void:
	var l := UiKit.title(text, 30, color)
	l.modulate.a = 0.0
	_toasts.add_child(l)
	while _toasts.get_child_count() > 4:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


func _on_damage_number(pos: Vector3, amount: float, kind: String) -> void:
	var parent: Node = get_tree().current_scene
	var p := get_tree().get_first_node_in_group("player")
	if p and p.get_parent():
		parent = p.get_parent()
	if parent == null or not (parent is Node3D or parent is Node):
		return
	var col: Color = NUMBER_COLORS.get(kind, Color.WHITE)
	var size := 46
	var text := str(int(round(amount)))
	match kind:
		"crit":
			size = 66
			text += "!"
		"heal":
			text = "+" + text
		"dot":
			size = 36
		"armor":
			size = 38
		"player":
			size = 52
			text = "-" + text
		"special":
			size = 52
	if amount > 0.0 and amount < 1.0:
		text = text.replace("0", "1")
	Fx3D.number(parent, pos, text, col, size)


func _on_player_damaged(_amount: float, _src: Node) -> void:
	_flash.color = Color(1, 0.1, 0.05, 0.22)
	var tw := _flash.create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.25)


func _on_died() -> void:
	_death.visible = true
	_death.color.a = 0.0
	_death_label.modulate.a = 0.0
	var tw := _death.create_tween()
	tw.tween_property(_death, "color:a", 0.88, 0.9)
	tw.parallel().tween_property(_death_label, "modulate:a", 1.0, 0.7).set_delay(0.3)


func _on_revived(left: int) -> void:
	_flash.color = Color(0.6, 1.0, 0.5, 0.65)
	var tw := _flash.create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.8)
	toast("Клятва Жизни! Корни вернули тебя (осталось: %d)" % left, Color(0.6, 1.0, 0.55))


func _pop(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(1.25, 1.25)
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ================================================================ пауза, Tab
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if DialogueBox.is_open():
			return
		if _pause.visible:
			close_pause()
		else:
			open_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_boons") and not _pause.visible:
		_boon_panel.visible = not _boon_panel.visible
		if _boon_panel.visible:
			_refresh_boons()
		get_viewport().set_input_as_handled()


func open_pause() -> void:
	if _pause.visible or _death.visible:
		return
	if get_tree().paused:
		return   # другое окно уже держит паузу
	_pause.visible = true
	(_pause.find_child("Surrender", true, false) as Button).visible = Run.active
	get_tree().paused = true
	_paused_by_me = true
	(_pause.find_child("Resume", true, false) as Button).grab_focus.call_deferred()


func close_pause() -> void:
	if not _pause.visible:
		return
	_pause.visible = false
	if _paused_by_me:
		get_tree().paused = false
	_paused_by_me = false


func _surrender() -> void:
	close_pause()
	if Run.active:
		Run.end_run(true, "surrender")


func _to_title() -> void:
	close_pause()
	Run.goto_title()


func set_visible_hud(on: bool) -> void:
	_root.visible = on


func _exit_tree() -> void:
	if _paused_by_me and is_inside_tree():
		get_tree().paused = false


func _process(delta: float) -> void:
	# пульсация виньетки при низком здоровье
	if _vignette.get_meta("low", false):
		var t := Time.get_ticks_msec() / 1000.0
		_vignette.modulate.a = 0.35 + 0.2 * sin(t * 5.0)
	else:
		_vignette.modulate.a = move_toward(_vignette.modulate.a, 0.0, delta * 2.0)


# ================================================================ виджеты
class _Bar extends Control:
	var value := 100.0
	var max_value := 100.0
	var trail := 100.0
	var _tw: Tween

	func set_value(v: float, mx: float) -> void:
		var old := value
		value = v
		max_value = maxf(1.0, mx)
		if v < old:
			if _tw and _tw.is_valid():
				_tw.kill()
			_tw = create_tween()
			_tw.tween_interval(0.35)
			_tw.tween_property(self, "trail", v, 0.4)
		else:
			trail = v
		queue_redraw()

	func _process(_d: float) -> void:
		if trail > value + 0.01:
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(3), Color(0.05, 0.03, 0.02, 0.85))
		draw_rect(r, Color(0.2, 0.06, 0.05, 0.95))
		var k := clampf(value / max_value, 0.0, 1.0)
		var kt := clampf(trail / max_value, 0.0, 1.0)
		draw_rect(Rect2(r.position, Vector2(r.size.x * kt, r.size.y)), Color(1, 0.9, 0.75, 0.85))
		var fill := Color(0.82, 0.16, 0.14).lerp(Color(0.95, 0.35, 0.18), 0.3)
		draw_rect(Rect2(r.position, Vector2(r.size.x * k, r.size.y)), fill)
		draw_rect(Rect2(r.position, Vector2(r.size.x * k, r.size.y * 0.35)), Color(1, 1, 1, 0.12))
		draw_rect(r, Color(0.88, 0.72, 0.36), false, 2.0)
		# засечки орнамента
		for i in range(1, 10):
			var x := r.size.x * i / 10.0
			draw_line(Vector2(x, r.size.y - 5), Vector2(x, r.size.y), Color(0.88, 0.72, 0.36, 0.5), 1.0)


class _Pips extends Control:
	var charges := 1
	var max_charges := 1

	func _draw() -> void:
		for i in max_charges:
			var c := Vector2(11 + i * 26, size.y * 0.5)
			var pts := PackedVector2Array([c + Vector2(0, -10), c + Vector2(10, 0), c + Vector2(0, 10), c + Vector2(-10, 0)])
			draw_colored_polygon(pts, Color(0.05, 0.04, 0.04, 0.8))
			if i < charges:
				var inner := PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 0), c + Vector2(0, 7), c + Vector2(-7, 0)])
				draw_colored_polygon(inner, Color(0.33, 0.85, 0.8))
			pts.append(pts[0])
			draw_polyline(pts, Color(0.88, 0.72, 0.36), 1.5)


class _Coin extends Control:
	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 10.0, Color(0.88, 0.7, 0.25))
		draw_circle(c, 7.0, Color(1.0, 0.85, 0.4))
		draw_rect(Rect2(c - Vector2(2.5, 2.5), Vector2(5, 5)), Color(0.55, 0.38, 0.1))


class _AshIcon extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var pts := PackedVector2Array()
		for i in 8:
			var a := TAU * i / 8.0 - PI / 2.0
			var r := 11.0 if i % 2 == 0 else 4.5
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, Color(0.8, 0.82, 0.95))


class _BoonIcon extends Control:
	var color := Color.WHITE
	var rarity_color := Color.WHITE
	var letter := "?"
	var level := 1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_circle(c, r + 2.0, rarity_color)
		draw_circle(c, r, Color(0.1, 0.06, 0.05))
		draw_circle(c, r - 3.0, Color(color, 0.35))
		var f := UiKit.bold()
		var fs := int(r * 1.1)
		var ts := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, c + Vector2(-ts.x * 0.5, fs * 0.36), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		if level > 1:
			draw_string(f, c + Vector2(r * 0.3, r), str(level), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.8))
