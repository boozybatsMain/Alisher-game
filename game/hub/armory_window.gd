class_name ArmoryWindow
extends HubWindow
## Окно стойки оружия: описание (WeaponData модуля B или запасной текст), «Взять» (Meta.equip → Bus.weapon_changed,
## герой меняет оружие мгновенно), «Открыть за N пепла» (Meta.unlock_weapon), три аспекта: открыть за Пепел / выбрать.

var weapon_id := "sword"


func _accent() -> Color:
	return WeaponRack.aspect_color(weapon_id, Meta.equipped_aspect if Meta.equipped_weapon == weapon_id else 0)


func _fill() -> void:
	var info := WeaponRack.weapon_info(weapon_id)
	var unlocked: bool = Meta.weapons_unlocked.get(weapon_id, false)
	body.add_child(k_title(str(info.get("title", weapon_id)), 38))
	body.add_child(ash_line())
	body.add_child(sep())
	body.add_child(k_label(str(info.get("desc", "")), 21))
	var meta_line := "Дистанция: %s     Темп: %s" % [str(info.get("range", "—")), str(info.get("tempo", "—"))]
	body.add_child(k_label(meta_line, 19, C_MUTED))
	if info.has("attack_desc"):
		body.add_child(k_label("ЛКМ — " + str(info["attack_desc"]), 19))
	if info.has("special_desc"):
		body.add_child(k_label("ПКМ — " + str(info["special_desc"]), 19))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	body.add_child(row)
	if unlocked:
		var equipped := Meta.equipped_weapon == weapon_id
		var b := k_button("В руках" if equipped else "Взять", _take, 260)
		b.disabled = equipped
		row.add_child(b)
	else:
		var cost := int(Meta.WEAPON_UNLOCK_COST.get(weapon_id, 0))
		var ub := k_button("Открыть за %d пепла" % cost, _unlock, 320)
		ub.disabled = Meta.ash < cost
		row.add_child(ub)
	body.add_child(sep())
	body.add_child(k_label("Аспекты", 26, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var aspects = info.get("aspects", [])
	for i in Meta.ASPECT_COSTS.size():
		var a: Dictionary = aspects[i] if aspects is Array and i < aspects.size() and aspects[i] is Dictionary else {"title": "Аспект %d" % (i + 1), "desc": ""}
		body.add_child(_aspect_row(i, a, unlocked))


func _aspect_row(i: int, a: Dictionary, weapon_open: bool) -> Control:
	var col := WeaponRack.aspect_color(weapon_id, i)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var swatch := ColorRect.new()
	swatch.color = col
	swatch.custom_minimum_size = Vector2(14, 56)
	h.add_child(swatch)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	v.add_child(k_label(str(a.get("title", "")), 22, col))
	v.add_child(k_label(str(a.get("desc", "")), 18, C_TEXT))
	h.add_child(v)
	var opened: bool = i in Meta.aspects_unlocked.get(weapon_id, [0])
	var selected: bool = Meta.equipped_weapon == weapon_id and Meta.equipped_aspect == i
	var b: Button
	if selected:
		b = k_button("Выбран", Callable(), 200)
		b.disabled = true
	elif opened:
		b = k_button("Выбрать", _choose.bind(i), 200)
		b.disabled = not weapon_open
	else:
		var cost: int = Meta.ASPECT_COSTS[i]
		b = k_button("Открыть · %d" % cost, _unlock_aspect.bind(i), 200)
		b.disabled = not weapon_open or Meta.ash < cost
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	return h


func _take() -> void:
	var a := 0
	if Meta.equipped_weapon == weapon_id:
		a = Meta.equipped_aspect
	Meta.equip(weapon_id, a)
	Sfx.play("swing_heavy", -4.0)
	refresh()


func _unlock() -> void:
	if Meta.unlock_weapon(weapon_id):
		Sfx.play("buy")
		Bus.toast.emit("Открыто: %s" % str(WeaponRack.weapon_info(weapon_id).get("title", weapon_id)), C_GOLD)
		Meta.equip(weapon_id, 0)
	refresh()


func _unlock_aspect(i: int) -> void:
	if Meta.unlock_aspect(weapon_id, i):
		Sfx.play("buy")
		Meta.equip(weapon_id, i)
	refresh()


func _choose(i: int) -> void:
	Meta.equip(weapon_id, i)
	Sfx.play("swing", -4.0)
	refresh()
