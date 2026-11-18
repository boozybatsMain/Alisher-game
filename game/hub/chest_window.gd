class_name ChestWindow
extends HubWindow
## Окно Сундука Предков: 5 постоянных улучшений из Meta.CHEST за Пепел Тамыра.

const ICONS := {"reflexes": "Көкбөрі", "blood": "Қан", "oath": "Ант", "shadow": "Көлеңке", "blessing": "Бата"}


func _accent() -> Color:
	return Color(0.55, 0.75, 1.0)


func _panel_width() -> float:
	return 900.0


func _fill() -> void:
	body.add_child(k_title("Сундук Предков", 40))
	body.add_child(k_label("Пепел Тамыра не сгорает со смертью. Вложи его в силу рода.", 19, C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	body.add_child(ash_line())
	body.add_child(sep())
	for key in Meta.CHEST_ORDER:
		body.add_child(_row(key))


func _row(key: String) -> Control:
	var d: Dictionary = Meta.CHEST[key]
	var lvl: int = Meta.chest[key]
	var costs: Array = d["costs"]
	var maxed := lvl >= costs.size()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	head.add_child(nowrap(k_label(str(d["title"]), 23, C_GOLD)))
	head.add_child(nowrap(k_label("  ур. %d / %d" % [lvl, costs.size()], 19, C_TEAL)))
	v.add_child(head)
	v.add_child(k_label(str(d["desc"]), 18))
	# полоска уровней
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 4)
	for i in costs.size():
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(22, 8)
		r.color = C_TEAL if i < lvl else Color(0.3, 0.25, 0.2)
		pips.add_child(r)
	v.add_child(pips)
	h.add_child(v)
	var b: Button
	if maxed:
		b = k_button("Предел", Callable(), 210)
		b.disabled = true
	else:
		var c := Meta.chest_cost(key)
		b = k_button("Купить · %d" % c, _buy.bind(key), 210)
		b.disabled = Meta.ash < c
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	return h


func _buy(key: String) -> void:
	if Meta.buy_chest(key):
		Sfx.play("buy")
		Bus.toast.emit("%s — уровень %d" % [str(Meta.CHEST[key]["title"]), int(Meta.chest[key])], Color(0.55, 0.85, 1.0))
		# новое здоровье сразу видно в HUD
		Run.set_hp(Run.max_hp())
		Bus.dash_charges_changed.emit(int(Run.stat("dash_charges")), int(Run.stat("dash_charges")))
	refresh()
