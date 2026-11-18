class_name RoomMerchant
extends Node3D
## Лавка Караванщика (модуль D): караванщик под пологом, 3 товара на прилавках, Колодец Обмена.
## Товары (Interactable с ценой в дирхемах): случайный Дар (окно выбора BoonChoice), Яство (лечение 35%),
## Улучшение имеющегося дара (+1 уровень). Цены ~80/40/120 и растут с глубиной (RoomRewards.price).
## Колодец Обмена: окно со списком даров → remove_boon(id) → дирхемы.
##
## API: RoomMerchant.create(parent, arena, depth, rng) -> RoomMerchant; goods: Array[ShopItem]; well: ExchangeWell

var goods: Array = []
var well: Node3D
var depth := 0
var rng: RandomNumberGenerator
var _arena: ArenaBuilder


static func create(parent: Node, arena: ArenaBuilder, p_depth: int, p_rng: RandomNumberGenerator) -> RoomMerchant:
	var m := RoomMerchant.new()
	m.name = "Merchant"
	m.depth = p_depth
	m.rng = p_rng
	m._arena = arena
	parent.add_child(m)
	m._build()
	return m


func _build() -> void:
	var mp: Vector3 = _arena.extra_points.get("merchant", Vector3(0, 0, -2.5))
	_build_stall(mp)
	var spots: Array = _arena.extra_points.get("goods", [Vector3(-4, 0, 0.5), Vector3(0, 0, 0.5), Vector3(4, 0, 0.5)])
	var god := String(RoomUtil.GODS[rng.randi_range(0, RoomUtil.GODS.size() - 1)])
	var kinds := ["boon", "food", "upgrade"]
	for i in mini(3, spots.size()):
		var it := ShopItem.new()
		it.kind = kinds[i]
		it.god = god
		it.price = RoomRewards.price(String(kinds[i]) if kinds[i] != "food" else "food", depth)
		add_child(it)
		it.global_position = spots[i]
		goods.append(it)
	var wp: Vector3 = _arena.extra_points.get("well", Vector3(6.5, 0, 3.5))
	var w := ExchangeWell.new()
	add_child(w)
	w.global_position = wp
	well = w


func _build_stall(p: Vector3) -> void:
	var felt := RoomUtil.mat(Color(0.6, 0.2, 0.14), 1.0)
	var felt2 := RoomUtil.mat(Color(0.9, 0.78, 0.55), 1.0)
	var wood := RoomUtil.mat(Color(0.4, 0.26, 0.16), 0.85)
	# полог-навес: полосатый
	var root := Node3D.new()
	root.position = p
	add_child(root)
	for sx: float in [-6.0, 6.0]:
		for sz: float in [-1.0, 2.6]:
			RoomUtil.solid_box(root, Vector3(sx, 1.6, sz), Vector3(0.25, 3.2, 0.25), wood)
	for i in 8:
		var m := felt if i % 2 == 0 else felt2
		var stripe := RoomUtil.mesh(root, RoomUtil.box_mesh(Vector3(1.55, 0.08, 4.0)), Vector3(-5.4 + i * 1.55, 3.35, 0.8), m)
		stripe.rotation.x = -0.18
	# прилавки
	for gx: float in [-4.0, 0.0, 4.0]:
		RoomUtil.solid_box(root, Vector3(gx, 0.45, 3.0), Vector3(2.2, 0.9, 0.9), wood)
		RoomUtil.mesh(root, RoomUtil.box_mesh(Vector3(2.3, 0.05, 1.0)), Vector3(gx, 0.92, 3.0), RoomUtil.mat(Color(0.25, 0.6, 0.58), 0.9), false)
	# караванщик: силуэт в халате, тюбетейке и с бородой
	var npc := Node3D.new()
	npc.position = Vector3(0, 0, 0.6)
	root.add_child(npc)
	RoomUtil.mesh(npc, RoomUtil.cyl_mesh(0.32, 0.55, 1.4, 10), Vector3(0, 0.7, 0), RoomUtil.mat(Color(0.2, 0.32, 0.5), 0.9))
	RoomUtil.mesh(npc, RoomUtil.cyl_mesh(0.34, 0.34, 0.12, 10), Vector3(0, 1.0, 0), RoomUtil.mat(Color(0.85, 0.65, 0.25), 0.6))
	var head := RoomUtil.mesh(npc, RoomRewards._sphere(0.24), Vector3(0, 1.65, 0), RoomUtil.mat(Color(0.78, 0.58, 0.42), 0.8))
	head.scale = Vector3(1, 1.05, 1)
	RoomUtil.mesh(npc, RoomUtil.cyl_mesh(0.2, 0.26, 0.22, 10), Vector3(0, 1.88, 0), RoomUtil.mat(Color(0.12, 0.1, 0.1), 0.8))
	RoomUtil.mesh(npc, RoomUtil.cyl_mesh(0.1, 0.02, 0.32, 6), Vector3(0, 1.38, 0.15), RoomUtil.mat(Color(0.9, 0.9, 0.88), 1.0))
	var lbl := RoomUtil.label3d("Караванщик", Color(1, 0.85, 0.55), 40, 0.006)
	lbl.position = Vector3(0, 2.5, 0)
	npc.add_child(lbl)
	# мешки, ящики, кувшины вокруг
	for i in 6:
		var x := rng.randf_range(-5.5, 5.5)
		var z := rng.randf_range(-0.8, 0.2)
		if absf(x) < 1.2:
			continue
		if rng.randf() < 0.5:
			var s := RoomUtil.mesh(root, RoomRewards._sphere(0.35), Vector3(x, 0.3, z), RoomUtil.mat(Color(0.55, 0.42, 0.28), 1.0))
			s.scale = Vector3(1, 0.85, 0.9)
		else:
			var b := RoomUtil.mesh(root, RoomUtil.box_mesh(Vector3(0.7, 0.6, 0.6)), Vector3(x, 0.3, z), wood)
			b.rotation.y = rng.randf() * 0.5
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.45)
	l.light_energy = 1.8
	l.omni_range = 9.0
	l.position = Vector3(0, 2.8, 1.5)
	root.add_child(l)
	var carpet := RoomUtil.mesh(root, RoomUtil.box_mesh(Vector3(7.0, 0.03, 3.0)), Vector3(0, 0.015, 5.0), RoomUtil.mat(Color(0.55, 0.16, 0.12), 1.0), false)
	RoomUtil.mesh(carpet, RoomUtil.box_mesh(Vector3(6.4, 0.035, 2.4)), Vector3.ZERO, RoomUtil.mat(Color(0.85, 0.65, 0.3), 1.0), false)
	RoomUtil.mesh(carpet, RoomUtil.box_mesh(Vector3(5.8, 0.04, 1.8)), Vector3.ZERO, RoomUtil.mat(Color(0.5, 0.14, 0.1), 1.0), false)


# ================================================================ товар
class ShopItem extends Interactable:
	var kind := "food"            ## boon / food / upgrade
	var price := 40
	var god := "tengri"
	var sold := false
	var target_boon := ""         ## для улучшения
	var _label: Label3D
	var _price: Label3D
	var _icon: Node3D

	func _ready() -> void:
		radius = 1.5
		if kind == "upgrade":
			_retarget()
			Bus.boons_changed.connect(_on_boons_changed)
		prompt = _prompt_text()
		super._ready()
		var col := _color()
		_icon = RoomRewards.make_icon(_icon_id(), col, god)
		_icon.position = Vector3(0, 1.55, 0)
		_icon.scale = Vector3.ONE * 1.1
		add_child(_icon)
		_label = RoomUtil.label3d(_title(), col.lerp(Color.WHITE, 0.4), 34, 0.0055)
		_label.position = Vector3(0, 2.45, 0)
		add_child(_label)
		_price = RoomUtil.label3d("%d дирхемов" % price, RoomUtil.GOLD, 32, 0.0055)
		_price.position = Vector3(0, 2.15, 0)
		add_child(_price)
		Bus.dirhams_changed.connect(_refresh_price)
		_refresh_price(Run.dirhams)

	## Цель улучшения: оставить текущую, если её ещё можно улучшить, иначе выбрать заново из Run.boons.upgradable().
	func _retarget() -> void:
		if target_boon != "" and _target_valid():
			return
		target_boon = ""
		var ids := []
		if Run.boons and Run.boons.has_method("upgradable"):
			ids = Run.boons.upgradable()
		if not ids.is_empty():
			target_boon = String(ids[randi() % ids.size()])

	func _target_valid() -> bool:
		if target_boon == "" or Run.boons == null:
			return false
		if Run.boons.has_method("can_level_up"):
			return Run.boons.can_level_up(target_boon)
		return Run.boons.has_method("has_boon") and Run.boons.has_boon(target_boon)

	func _on_boons_changed() -> void:
		if sold or kind != "upgrade":
			return
		_retarget()
		prompt = _prompt_text()
		if _label:
			_label.text = _title()

	func _icon_id() -> String:
		return {"boon": "boon", "food": "heal", "upgrade": "upgrade"}.get(kind, "heal")

	func _color() -> Color:
		match kind:
			"boon": return RoomUtil.god_color(god)
			"upgrade": return RoomRewards.COLORS["upgrade"]
		return RoomRewards.COLORS["heal"]

	func _title() -> String:
		match kind:
			"boon": return "Дар: " + RoomUtil.god_name(god)
			"upgrade": return ("Улучшить: " + RoomUtil.boon_title(target_boon)) if target_boon != "" else "Нечего улучшать"
		return "Яство (+35% здоровья)"

	func _prompt_text() -> String:
		return "Купить: %s — %d дирхемов" % [_title(), price]

	func _refresh_price(v: int) -> void:
		if _price and not sold:
			_price.modulate = RoomUtil.GOLD if v >= price else Color(0.85, 0.35, 0.3)

	func can_activate(_p: Node) -> bool:
		if kind == "upgrade" and not _target_valid():
			_on_boons_changed()
		return enabled and not sold and not (kind == "upgrade" and not _target_valid())

	func activate(p: Node) -> void:
		if not can_activate(p):
			if kind == "upgrade" and not sold and target_boon == "":
				RoomUtil.toast("Нечего улучшать", Color(0.85, 0.6, 0.4))
			return
		if not Run.spend_dirhams(price):
			Sfx.play("ui_click")
			RoomUtil.toast("Не хватает дирхемов (%d / %d)" % [Run.dirhams, price], Color(0.95, 0.4, 0.35))
			return
		activated.emit(p)
		Sfx.play("buy")
		match kind:
			"boon":
				enabled = false
				var host: Node = get_tree().current_scene if get_tree().current_scene else get_parent()
				RoomUtil.open_boon_choice(host, god, func(_c: Dictionary): _sold(), 3)
				return
			"food":
				var n := Run.max_hp() * 0.35
				Run.heal(n)
				Bus.damage_number.emit(global_position + Vector3(0, 2, 0), n, "heal")
				RoomUtil.toast("Сытная шурпа (+%d)" % int(n), RoomRewards.COLORS["heal"])
			"upgrade":
				if Run.boons and Run.boons.has_method("level_up"):
					Run.boons.level_up(target_boon)
					RoomUtil.toast("%s — уровень %d" % [RoomUtil.boon_title(target_boon), Run.boons.level_of(target_boon)], RoomRewards.COLORS["upgrade"])
		_sold()

	func _sold() -> void:
		sold = true
		enabled = false
		if is_inside_tree():
			Fx3D.burst(get_parent(), global_position + Vector3(0, 1.5, 0), _color(), 14, 3.0)
		if _icon:
			_icon.visible = false
		if _price:
			_price.text = "продано"
			_price.modulate = Color(0.6, 0.55, 0.5)


# ================================================================ Колодец Обмена
class ExchangeWell extends Interactable:
	var _win: RoomUi = null
	var sold_count := 0

	func _ready() -> void:
		radius = 1.8
		prompt = "Колодец Обмена — продать дар"
		super._ready()
		var stone := RoomUtil.mat(Color(0.35, 0.32, 0.3), 0.9)
		RoomUtil.solid_box(self, Vector3(0, 0.4, 0), Vector3(1.6, 0.8, 1.6), stone, 1, false)
		RoomUtil.mesh(self, RoomUtil.cyl_mesh(0.85, 1.0, 0.8, 14), Vector3(0, 0.4, 0), stone)
		RoomUtil.mesh(self, RoomUtil.cyl_mesh(0.7, 0.7, 0.05, 14), Vector3(0, 0.78, 0), RoomUtil.mat(Color(0.25, 0.55, 0.8, 0.9), 0.05, Color(0.4, 0.75, 1.0), 1.5), false)
		# ритуальная чаша над колодцем на треноге
		for k in 3:
			var a := TAU * k / 3.0
			var leg := RoomUtil.mesh(self, RoomUtil.cyl_mesh(0.04, 0.05, 2.2, 5), Vector3(cos(a) * 0.75, 1.1, sin(a) * 0.75), RoomUtil.mat(Color(0.35, 0.24, 0.15)), true)
			leg.rotation = Vector3(sin(a) * 0.3, 0, -cos(a) * 0.3)
		RoomUtil.mesh(self, RoomUtil.cyl_mesh(0.35, 0.15, 0.2, 10), Vector3(0, 2.25, 0), RoomUtil.mat(Color(0.8, 0.6, 0.25), 0.3, Color(1, 0.7, 0.3), 0.4, 0.7))
		var f := RoomUtil.flame_sprite(Color(0.5, 0.8, 1.0), 0.006)
		f.position = Vector3(0, 2.5, 0)
		add_child(f)
		var l := OmniLight3D.new()
		l.light_color = Color(0.5, 0.8, 1.0)
		l.light_energy = 1.4
		l.omni_range = 5.0
		l.position = Vector3(0, 2.3, 0)
		add_child(l)
		var lbl := RoomUtil.label3d("Колодец Обмена", Color(0.6, 0.85, 1.0), 36, 0.0055)
		lbl.position = Vector3(0, 3.1, 0)
		add_child(lbl)

	func can_activate(_p: Node) -> bool:
		return enabled and _win == null

	func activate(p: Node) -> void:
		if not can_activate(p):
			return
		activated.emit(p)
		open_window()

	func open_window() -> RoomUi:
		var host: Node = get_tree().current_scene if get_tree().current_scene else get_parent()
		_win = RoomUi.open_window(host, "Колодец Обмена", Color(0.5, 0.8, 1.0))
		if _win == null:
			return null
		_win.closed.connect(func(): _win = null)
		_fill()
		return _win

	func _fill() -> void:
		_win.clear_body()
		_win.add_text("Опусти дар в воду предков — духи вернут его ценность дирхемами.")
		var owned := RoomUtil.owned_boons()
		if owned.is_empty():
			_win.add_text("У тебя нет даров.", Color(0.7, 0.62, 0.52))
			return
		for b in owned:
			var id := String(b["id"])
			var rar := String(b.get("rarity", "common"))
			var lvl := int(b.get("level", 1))
			var price := 0
			if Run.boons.has_method("sell_price"):
				price = Run.boons.sell_price(id)
			var gcol := RoomUtil.god_color(RoomUtil.boon_god(id))
			_win.add_row("%s (ур. %d)\n%s" % [RoomUtil.boon_title(id), lvl, RoomUtil.boon_desc(id, lvl, rar)],
				"Продать: %d" % price, _sell.bind(id), true, RoomUtil.boon_icon(id, rar), gcol.lerp(Color.WHITE, 0.5))

	## Продать дар (и из окна, и для тестов). Возвращает полученные дирхемы.
	func sell(id: String) -> int:
		if Run.boons == null or not Run.boons.has_method("remove_boon"):
			return 0
		var got: int = Run.boons.remove_boon(id)
		if got > 0:
			Run.add_dirhams(got)
			sold_count += 1
			Sfx.play("buy")
			RoomUtil.toast("%s продан: +%d дирхемов" % [RoomUtil.boon_title(id), got], RoomUtil.GOLD)
		return got

	func _sell(id: String) -> void:
		sell(id)
		if _win:
			_fill()
