class_name WeaponRack
extends Interactable
## Стойка оружия в оружейном шатре. На стойке — процедурная модель оружия (WeaponModel, модуль B) в цвете аспекта.
## activate → окно ArmoryWindow (описание, «Взять», «Открыть за N пепла», аспекты).

const WEAPON_DATA := "res://game/weapons/weapon_data.gd"
const WEAPON_MODEL := "res://game/weapons/weapon_model.gd"

const FALLBACK := {
	"sword": {"title": "Меч Батыра", "desc": "Серия из 3 рубящих ударов. Особая — круговой вихрь 360°, отбивающий снаряды, или выпад.", "range": "Ближняя", "tempo": "Средний",
		"aspects": [{"title": "Меч Батыра", "desc": "Базовый облик.", "color": "#9fe3ff"}, {"title": "Аспект Алпамыса", "desc": "Волна клинка на третьем ударе.", "color": "#ffd36a"}, {"title": "Аспект Қобыланды", "desc": "Бесконечный вихрь при удержании.", "color": "#ff5a4a"}, {"title": "Аспект Ер Тарғына", "desc": "Контрудар после идеального уклонения.", "color": "#e8f0ff"}]},
	"spear": {"title": "Найза", "desc": "Длинные быстрые выпады. Особая — бросок сквозь строй, повторное нажатие возвращает копьё.", "range": "Средняя", "tempo": "Быстрый",
		"aspects": [{"title": "Найза", "desc": "Базовый облик.", "color": "#7fe0c8"}, {"title": "Аспект Наурызбая", "desc": "Длинные выпады.", "color": "#6ab8ff"}, {"title": "Аспект Томирис", "desc": "Телепорт к воткнутому копью со взрывом.", "color": "#ffb347"}, {"title": "Аспект Райымбека", "desc": "Выпады пускают кровь.", "color": "#ff4466"}]},
	"shield": {"title": "Қалқан", "desc": "Тяжёлый удар с отталкиванием, удержание — блок. Особая — бросок рикошетом до 4 целей.", "range": "Ближняя", "tempo": "Медленный",
		"aspects": [{"title": "Қалқан", "desc": "Базовый облик.", "color": "#5fd3c4"}, {"title": "Аспект Абылай хана", "desc": "Блок отражает снаряды.", "color": "#ffcf4a"}, {"title": "Аспект Бөгенбая", "desc": "Щит-жернов.", "color": "#b07bff"}, {"title": "Аспект Ер Жәнібека", "desc": "Ответная волна с блока.", "color": "#9cff8a"}]},
	"bow": {"title": "Садақ", "desc": "Выстрел с натяжением, идеальный тайминг пробивает сильнее. Особая — веер 5 стрел.", "range": "Дальняя", "tempo": "Медленный",
		"aspects": [{"title": "Садақ", "desc": "Базовый облик.", "color": "#c9f27a"}, {"title": "Аспект Ай-Мергена", "desc": "Самонаводящийся веер.", "color": "#c9b3ff"}, {"title": "Аспект Ер Төстіка", "desc": "Раскалывающаяся стрела.", "color": "#ff8a3d"}, {"title": "Аспект Құламергена", "desc": "Луч, пробивающий всех на линии.", "color": "#fff27a"}]},
	"gauntlets": {"title": "Темір қолғап", "desc": "Серия из 5 быстрых ударов. Особая — апперкот, подбрасывающий врага.", "range": "Ближняя", "tempo": "Очень быстрый",
		"aspects": [{"title": "Темір қолғап", "desc": "Базовый облик.", "color": "#ffb070"}, {"title": "Аспект Қажымұқана", "desc": "Бросок борца.", "color": "#e04848"}, {"title": "Аспект Балуана Шолака", "desc": "Стаки ярости.", "color": "#8cc8ff"}, {"title": "Аспект Қамбара", "desc": "Ударная волна апперкота.", "color": "#ff6040"}]},
}

@export var weapon_id := "sword"
var model: Node3D = null
var _lock_label: Label3D
var _title_label: Label3D
var _glow_light: OmniLight3D


static func weapon_info(id: String) -> Dictionary:
	if ResourceLoader.exists(WEAPON_DATA):
		var scr = load(WEAPON_DATA)
		if scr is Script:
			var ws = (scr as Script).get_script_constant_map().get("WEAPONS", {})
			if ws is Dictionary and ws.has(id):
				return ws[id]
	return FALLBACK.get(id, FALLBACK["sword"])


static func aspect_color(id: String, a: int) -> Color:
	var asp = weapon_info(id).get("aspects", [])
	if asp is Array and a < asp.size() and asp[a] is Dictionary:
		var c = asp[a].get("color", null)
		if c is Color:
			return c
		if c is String and Color.html_is_valid(c):
			return Color.html(c)
	return Color(1.0, 0.75, 0.35)


func _ready() -> void:
	radius = 1.3
	super._ready()
	_build()
	refresh()
	Bus.weapon_changed.connect(func(_i: String, _a: int): refresh())
	Bus.ash_changed.connect(func(_v: int): refresh())


func _build() -> void:
	# стойка: две жерди + перекладина + каменное основание
	HubProps.box(self, Vector3(1.1, 0.16, 0.5), Vector3(0, 0.08, 0), HubProps.STONE)
	for x in [-0.42, 0.42]:
		HubProps.cyl(self, 0.05, 0.06, 1.9, Vector3(x, 1.0, 0), HubProps.WOOD)
		HubProps.sphere(self, 0.07, Vector3(x, 1.97, 0), HubProps.GOLD)
	HubProps.cyl(self, 0.04, 0.04, 0.95, Vector3(0, 1.75, 0), HubProps.WOOD_DARK, Vector3(0, 0, 90))
	HubProps.box(self, Vector3(0.9, 0.04, 0.12), Vector3(0, 0.65, 0.0), HubProps.WOOD_DARK)
	# флажок-тумар с цветом аспекта
	_title_label = HubProps.label(self, "", Vector3(0, 2.35, 0), Color(1, 0.9, 0.65), 34)
	_lock_label = HubProps.label(self, "", Vector3(0, 0.45, 0.45), Color(0.75, 0.85, 1.0), 28)
	_glow_light = OmniLight3D.new()
	_glow_light.omni_range = 2.2
	_glow_light.light_energy = 0.8
	_glow_light.position = Vector3(0, 1.2, 0.5)
	add_child(_glow_light)
	HubProps.solid_box(self, Vector3(1.1, 2.0, 0.5), Vector3(0, 1.0, 0))
	prompt = "Осмотреть оружие"


func _make_model(color: Color) -> void:
	if model and is_instance_valid(model):
		model.queue_free()
		model = null
	if ResourceLoader.exists(WEAPON_MODEL):
		var scr = load(WEAPON_MODEL)
		if scr is GDScript and (scr as GDScript).can_instantiate():
			var m = scr.build(weapon_id, color)
			if m is Node3D:
				model = m
	if model == null:
		model = Node3D.new()
		HubProps.box(model, Vector3(0.08, 0.08, 1.2), Vector3(0, 0, -0.4), HubProps.mat(Color(0.8, 0.8, 0.85), 0.3, 0.8))
	add_child(model)
	# модель смотрит вдоль -Z: ставим оружие вертикально на стойку (остриём вверх), чуть к зрителю
	model.position = Vector3(0, 0.75, 0.12)
	model.rotation_degrees = Vector3(90, 0, 0)
	match weapon_id:
		"shield":
			model.position = Vector3(0, 1.15, 0.15)
			model.rotation_degrees = Vector3(0, 0, 0)
		"gauntlets":
			model.position = Vector3(0, 1.2, 0.15)
			model.rotation_degrees = Vector3(0, 0, 0)
		"bow":
			model.position = Vector3(0, 1.15, 0.12)
			model.rotation_degrees = Vector3(0, 90, 0)
	model.scale = Vector3.ONE * 1.25


func refresh() -> void:
	var unlocked: bool = Meta.weapons_unlocked.get(weapon_id, false)
	var a := Meta.equipped_aspect if Meta.equipped_weapon == weapon_id else 0
	var c := aspect_color(weapon_id, a)
	if model == null or not is_instance_valid(model) or get_meta("model_color", Color(0, 0, 0, 0)) != c:
		_make_model(c if unlocked else Color(0.25, 0.25, 0.3))
		set_meta("model_color", c)
	if model:
		model.visible = true
		_set_dim(model, not unlocked)
	var info := weapon_info(weapon_id)
	var mark := "★ " if Meta.equipped_weapon == weapon_id else ""
	_title_label.text = mark + str(info.get("title", weapon_id))
	_title_label.modulate = Color(1, 0.88, 0.5) if Meta.equipped_weapon == weapon_id else Color(0.92, 0.86, 0.76)
	if unlocked:
		_lock_label.text = ""
	else:
		_lock_label.text = "Закрыто · %d пепла" % int(Meta.WEAPON_UNLOCK_COST.get(weapon_id, 0))
	_glow_light.light_color = c
	_glow_light.light_energy = 1.1 if unlocked else 0.0


func _set_dim(n: Node, dim: bool) -> void:
	for ch in n.get_children():
		if ch is GeometryInstance3D:
			(ch as GeometryInstance3D).transparency = 0.55 if dim else 0.0
		_set_dim(ch, dim)


func activate(player: Node) -> void:
	if not can_activate(player):
		return
	activated.emit(player)
	Sfx.play("ui_click", -4.0)
	var w := ArmoryWindow.new()
	w.weapon_id = weapon_id
	w.open_on(get_tree().current_scene if get_tree().current_scene else get_tree().root, player)
