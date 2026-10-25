extends RefCounted
## Окна: итог забега, пауза, сундук (вечная прокачка), очаг (подношения и статистика), управление.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Gifts := preload("res://scripts/data/gifts.gd")

const CONTROLS := """A / D или ← / →  — бег
J или левая кнопка мыши  — удар (три удара подряд — комбо, третий тяжёлый и пробивает броню)
Shift или Пробел  — кувырок: неуязвимость, перезарядка 1 с
J во время кувырка  — рывок-удар насквозь
K или правая кнопка мыши  — щит в любой момент и в любую сторону: нажатие ставит его на 0.5 с, зажатый держится; −75% урона
Щит ничего не принял — перезарядка 0.6 с; принял удар — можно ставить сразу снова
«!» над врагом: жёлтый — удар можно блокировать, красный — только кувырок
Удар в первые 0.2 с щита  — идеальный блок: урона нет, враг оглушён
E  — взаимодействовать,  Esc  — пауза"""


static func _layer(owner: Node, z := 25, pause := true) -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.layer = z
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	owner.add_child(cl)
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme()
	cl.add_child(root)
	UI.dim(root, 0.62)
	if pause:
		owner.get_tree().paused = true
	return cl


static func _panel(cl: CanvasLayer, size: Vector2) -> VBoxContainer:
	var root: Control = cl.get_node("Root")
	var p := UI.panel(size)
	p.position = (Vector2(1280, 720) - size) * 0.5
	root.add_child(p)
	var v := VBoxContainer.new()
	v.position = Vector2(70, 56)
	v.size = size - Vector2(140, 112)
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	return v


static func _title(v: VBoxContainer, text: String, color := Color(1, 0.86, 0.5)) -> void:
	var t := UI.label(text, 38, color, HORIZONTAL_ALIGNMENT_CENTER)
	t.add_theme_font_override("font", UI.bold())
	v.add_child(t)


static func _close(cl: CanvasLayer, unpause := true) -> void:
	if unpause:
		cl.get_tree().paused = false
	cl.queue_free()


# ------------------------------------------------------------------ итог забега
static func result(owner: Node, title: String, sub: String, lines: Array, buttons: Array, color := Color(1, 0.86, 0.5)) -> CanvasLayer:
	var cl := _layer(owner, 30, true)
	var v := _panel(cl, Vector2(760, 520))
	_title(v, title, color)
	var s := UI.label(sub, 22, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(s)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	v.add_child(spacer)
	for line in lines:
		v.add_child(UI.label(line, 22, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grow)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 24)
	v.add_child(hb)
	var first: Button = null
	for b in buttons:
		var cb: Callable = b[1]
		var btn := UI.button(b[0], func(): _close(cl); cb.call(), 260)
		hb.add_child(btn)
		if first == null:
			first = btn
	if first:
		first.call_deferred("grab_focus")
	return cl


# ------------------------------------------------------------------ пауза
static func pause(owner: Node, to_title: Callable) -> CanvasLayer:
	var cl := _layer(owner, 40, true)
	var v := _panel(cl, Vector2(720, 560))
	_title(v, "Пауза")
	var ctl := UI.label(CONTROLS, 17, UI.TEXT)
	ctl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(ctl)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grow)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 24)
	v.add_child(hb)
	var cont := UI.button("Продолжить", func(): _close(cl))
	hb.add_child(cont)
	hb.add_child(UI.button("В главное меню", func(): _close(cl); to_title.call()))
	cont.call_deferred("grab_focus")
	cl.set_meta("is_pause", true)
	return cl


# ------------------------------------------------------------------ сундук: вечная прокачка
static func chest(owner: Node, on_close: Callable) -> CanvasLayer:
	var cl := _layer(owner, 25, false)
	var v := _panel(cl, Vector2(820, 560))
	_title(v, "Алтын Сандық — вечная прокачка")
	var have := UI.label("", 22, Color(1, 0.9, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(have)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	v.add_child(rows)
	# лямбды захватывают переменные по значению — держим ссылку на себя в словаре
	var fn := {}
	fn.refresh = func():
		have.text = "Асыков: %d" % GameState.asyks
		for c in rows.get_children():
			c.queue_free()
		for key in GameState.UPGRADE_ORDER:
			var u: Dictionary = GameState.UPGRADES[key]
			var lvl: int = GameState.upgrades[key]
			var cost := GameState.upgrade_cost(key)
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 16)
			var info := VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var nm := UI.label("%s   %s" % [u["title"], "◆".repeat(lvl) + "◇".repeat(u["costs"].size() - lvl)], 24, Color(1, 0.88, 0.6))
			nm.add_theme_font_override("font", UI.bold())
			info.add_child(nm)
			info.add_child(UI.label(u["desc"], 18, UI.MUTED))
			hb.add_child(info)
			var btn := UI.button("Максимум" if cost < 0 else "Купить · %d" % cost, func():
				if GameState.buy_upgrade(key):
					Sfx.play("buy")
				fn.refresh.call(), 200)
			btn.disabled = cost < 0 or GameState.asyks < cost
			hb.add_child(btn)
			rows.add_child(hb)
	fn.refresh.call()
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grow)
	var close := UI.button("Закрыть", func(): _close(cl, false); on_close.call())
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(close)
	close.call_deferred("grab_focus")
	return cl


# ------------------------------------------------------------------ очаг От-Ана
static func hearth(owner: Node, on_close: Callable) -> CanvasLayer:
	var cl := _layer(owner, 25, false)
	var v := _panel(cl, Vector2(860, 600))
	_title(v, "Священный очаг От-Ана")
	var st: Dictionary = GameState.stats
	var best := "Круг %d · %s · волна %d" % [st["best_cycle"], ["Степной Курган", "Сердце Кургана"][clampi(st["best_stage"], 0, 1)], st["best_wave"]] \
		if int(st["best_cycle"]) > 0 else "ещё нет"
	var lines := [
		"Вылазок: %d   ·   Побед: %d   ·   Смертей: %d" % [st["runs"], st["victories"], st["deaths"]],
		"Повержено врагов: %d   ·   Собрано асыков: %d" % [st["kills"], st["asyks_total"]],
		"Лучший результат: " + best,
	]
	var last: Dictionary = st.get("last_run", {})
	if not last.is_empty():
		lines.append("Прошлая вылазка: %s, волна %d, врагов %d, асыков %d" % [
			"пал в бою" if last.get("died", true) else "победа", int(last.get("wave", 0)), int(last.get("kills", 0)), int(last.get("asyks", 0))])
	for l in lines:
		v.add_child(UI.label(l, 19, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var sep := UI.label("— Подношения перед вылазкой —", 22, Color(1, 0.75, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(sep)
	var status := UI.label("Асыков: %d" % GameState.asyks, 20, Color(1, 0.9, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(status)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	v.add_child(hb)
	var ui := {}   # кнопки и функция обновления — в словаре: лямбды захватывают его по ссылке
	ui.upd = func():
		status.text = "Асыков: %d" % GameState.asyks
		ui.gift.disabled = GameState.offered_gift or GameState.asyks < GameState.OFFER_GIFT_COST
		ui.amulet.disabled = GameState.amulet or GameState.asyks < GameState.OFFER_AMULET_COST
		ui.gift.text = "Дар уже получен" if GameState.offered_gift else "Стартовый Дар · %d" % GameState.OFFER_GIFT_COST
		ui.amulet.text = "Тұмар уже с тобой" if GameState.amulet else "Тұмар-оберег · %d" % GameState.OFFER_AMULET_COST
	ui.gift = UI.button("", func():
		var god := GameState.offer_starting_gift()
		ui.upd.call()
		if god != "":
			Sfx.play("gift_take")
			status.text = "От-Ана дарует: %s" % Gifts.gift_name(god, 0), 300)
	ui.amulet = UI.button("", func():
		if GameState.offer_amulet():
			Sfx.play("buy")
		ui.upd.call(), 300)
	hb.add_child(ui.gift)
	hb.add_child(ui.amulet)
	v.add_child(UI.label("Дар ляжет в первый ромб; Тұмар один раз спасёт от смерти в этой вылазке.", 16, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	ui.upd.call()
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grow)
	var close := UI.button("Закрыть", func(): _close(cl, false); on_close.call())
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(close)
	close.call_deferred("grab_focus")
	return cl
