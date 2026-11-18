class_name RewardPickup
extends Interactable
## Награда комнаты (модуль D): постамент с вращающимся символом. interact → эффект награды → сигнал taken.
## kind: "ash" (кучка Пепла Тамыра), "gold" (сундук дирхемов), "upgrade" (Камень Силы — +1 уровень случайного дара),
##       "heal" (яство, +30% HP), "kui" (Забытая нота — открыть неоткрытый кюй), "spring" (родник привала, +50% HP),
##       "boon" (fallback тотема духа: окно выбора или прямой дар), "ash_boss" (пепел босса).
##
## API: RewardPickup.make(kind, amount := 0, god := "") -> RewardPickup; сигнал taken(kind, info: Dictionary)

signal taken(kind: String, info: Dictionary)

var kind := "ash"
var amount := 0
var god := ""
var used := false
var _icon: Node3D
var _light: OmniLight3D
var _label: Label3D


static func make(p_kind: String, p_amount := 0, p_god := "") -> RewardPickup:
	var r := RewardPickup.new()
	r.kind = p_kind
	r.amount = p_amount
	r.god = p_god
	r.name = "Reward_" + p_kind
	return r


func _ready() -> void:
	radius = 1.8
	prompt = _prompt()
	super._ready()
	_build()


func _title() -> String:
	match kind:
		"ash", "ash_boss": return "Пепел Тамыра ×%d" % amount
		"gold": return "Сундук: %d дирхемов" % amount
		"upgrade": return "Камень Силы"
		"heal": return "Яство"
		"spring": return "Целебный родник"
		"kui": return "Забытая нота"
		"boon": return "Дар: " + RoomUtil.god_name(god)
	return kind


func _prompt() -> String:
	match kind:
		"ash", "ash_boss", "gold", "kui": return "E — забрать"
		"upgrade": return "E — коснуться Камня Силы"
		"heal": return "E — отведать"
		"spring": return "E — испить"
		"boon": return "E — принять дар"
	return "E — взять"


func _color() -> Color:
	match kind:
		"ash", "ash_boss": return RoomRewards.COLORS["ash"]
		"gold": return RoomRewards.COLORS["gold"]
		"upgrade": return RoomRewards.COLORS["upgrade"]
		"heal": return RoomRewards.COLORS["heal"]
		"spring": return RoomRewards.COLORS["rest"]
		"kui": return RoomRewards.COLORS["kui"]
		"boon": return RoomUtil.god_color(god)
	return Color(1, 0.9, 0.7)


func _icon_id() -> String:
	match kind:
		"ash_boss": return "ash"
		"spring": return "rest"
	return kind


func _build() -> void:
	var col := _color()
	var stone := RoomUtil.mat(Color(0.32, 0.29, 0.27), 0.9)
	if kind == "gold":
		# сундук-сандык с золотой окантовкой
		var wood := RoomUtil.mat(Color(0.45, 0.25, 0.14), 0.8)
		var gold := RoomUtil.mat(Color(1.0, 0.78, 0.3), 0.3, Color(1, 0.7, 0.2), 0.5, 0.8)
		RoomUtil.mesh(self, RoomUtil.box_mesh(Vector3(1.3, 0.7, 0.85)), Vector3(0, 0.35, 0), wood)
		RoomUtil.mesh(self, RoomUtil.box_mesh(Vector3(1.34, 0.3, 0.89)), Vector3(0, 0.85, 0), wood)
		for sx: float in [-0.5, 0.0, 0.5]:
			RoomUtil.mesh(self, RoomUtil.box_mesh(Vector3(0.08, 1.02, 0.92)), Vector3(sx, 0.5, 0), gold, false)
	elif kind == "spring":
		RoomUtil.mesh(self, RoomUtil.cyl_mesh(1.2, 1.35, 0.5, 16), Vector3(0, 0.25, 0), stone)
		RoomUtil.mesh(self, RoomUtil.cyl_mesh(1.0, 1.0, 0.05, 16), Vector3(0, 0.48, 0), RoomUtil.mat(Color(0.3, 0.65, 0.9, 0.85), 0.05, Color(0.3, 0.7, 1.0), 1.2), false)
	else:
		RoomUtil.mesh(self, RoomUtil.cyl_mesh(0.55, 0.7, 0.45, 10), Vector3(0, 0.22, 0), stone)
		RoomUtil.mesh(self, RoomUtil.cyl_mesh(0.58, 0.58, 0.05, 10), Vector3(0, 0.46, 0), RoomUtil.mat(col.darkened(0.3), 0.6, col, 1.2), false)
	_icon = RoomRewards.make_icon(_icon_id(), col, god)
	_icon.position = Vector3(0, 1.45 if kind != "spring" else 1.3, 0)
	_icon.scale = Vector3.ONE * 1.4
	add_child(_icon)
	_light = OmniLight3D.new()
	_light.light_color = col
	_light.light_energy = 1.8
	_light.omni_range = 4.5
	_light.position = Vector3(0, 1.6, 0)
	add_child(_light)
	_label = RoomUtil.label3d(_title(), col.lerp(Color.WHITE, 0.4), 40, 0.006)
	_label.position = Vector3(0, 2.5, 0)
	add_child(_label)
	# появление
	scale = Vector3.ONE * 0.01
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func can_activate(_player: Node) -> bool:
	return enabled and not used


func activate(player: Node) -> void:
	if not can_activate(player):
		return
	activated.emit(player)
	if kind == "boon":
		enabled = false
		var host: Node = get_tree().current_scene if get_tree().current_scene else get_parent()
		RoomUtil.open_boon_choice(host, god, func(c: Dictionary): _finish({"choice": c}))
		return
	_finish(apply())


## Применить награду (без анимации). Возвращает сведения для тоста/теста.
func apply() -> Dictionary:
	var info := {}
	match kind:
		"ash", "ash_boss":
			Run.add_ash(amount)
			Sfx.play("gift_take")
			RoomUtil.toast("+%d Пепла Тамыра" % amount, RoomRewards.COLORS["ash"])
			info["ash"] = amount
		"gold":
			Run.add_dirhams(amount)
			Sfx.play("chest")
			Sfx.play("buy", -6.0)
			RoomUtil.toast("+%d дирхемов" % amount, RoomUtil.GOLD)
			info["dirhams"] = amount
		"heal", "spring":
			var frac := 0.3 if kind == "heal" else 0.5
			var n := Run.max_hp() * frac
			Run.heal(n)
			Sfx.play("revive", -6.0)
			Bus.damage_number.emit(global_position + Vector3(0, 2.0, 0), n, "heal")
			RoomUtil.toast("Силы возвращаются (+%d)" % int(n), RoomRewards.COLORS["heal"])
			info["heal"] = n
		"upgrade":
			info = level_up_random_boon()
		"kui":
			info = unlock_random_kui()
	return info


## Улучшить случайный дар (Камень Силы). Если улучшать нечего — +50 дирхемов.
static func level_up_random_boon() -> Dictionary:
	var ids := []
	if Run.boons:
		if Run.boons.has_method("upgradable"):
			ids = Run.boons.upgradable()
		elif Run.boons.has_method("owned"):
			for b in Run.boons.owned():
				ids.append(b["id"])
	if ids.is_empty() or not Run.boons.has_method("level_up"):
		Run.add_dirhams(50)
		RoomUtil.toast("Камень Силы безмолвен — +50 дирхемов", RoomUtil.GOLD)
		return {"dirhams": 50}
	var id := String(ids[randi() % ids.size()])
	Run.boons.level_up(id)
	var lvl: int = Run.boons.level_of(id) if Run.boons.has_method("level_of") else 0
	Sfx.play("gift_take")
	RoomUtil.toast("Камень Силы: %s — ур. %d" % [RoomUtil.boon_title(id), lvl], RoomRewards.COLORS["upgrade"])
	return {"upgraded": id, "level": lvl}


## Открыть случайный неоткрытый кюй (Забытая нота). Если все открыты — +25 пепла.
static func unlock_random_kui() -> Dictionary:
	var locked := []
	for k in Run.KUIS:
		if not (k in Meta.kuis_unlocked):
			locked.append(k)
	Sfx.play("dombra")
	if locked.is_empty():
		Run.add_ash(25)
		RoomUtil.toast("Все ноты уже звучат в тебе — +25 Пепла", RoomRewards.COLORS["ash"])
		return {"ash": 25}
	var id := String(locked[randi() % locked.size()])
	Meta.unlock_kui(id)
	RoomUtil.toast("Забытая нота: кюй «%s» — сыграй его у костра" % String(Run.KUIS[id]["title"]), RoomRewards.COLORS["kui"])
	return {"kui": id}


func _finish(info: Dictionary) -> void:
	used = true
	enabled = false
	var parent := get_parent()
	if parent and is_inside_tree():
		Fx3D.burst(parent, global_position + Vector3(0, 1.4, 0), _color(), 18, 4.0)
		Fx3D.flash_light(parent, global_position + Vector3(0, 1.5, 0), _color(), 4.0, 5.0, 0.3)
	taken.emit(kind, info)
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_property(_icon, "scale", Vector3.ONE * 0.01, 0.35)
		tw.parallel().tween_property(_light, "light_energy", 0.0, 0.5)
		tw.parallel().tween_property(_label, "modulate:a", 0.0, 0.5)
		if kind != "spring" and kind != "gold":
			tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.3)
			tw.tween_callback(queue_free)
