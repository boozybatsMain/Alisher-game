class_name AncestorChest
extends Interactable
## Сундук Предков (Сандык): окованный сундук у входа в юрту. activate → окно с 5 улучшениями Meta.CHEST
## (уровень, цена, описание, «Купить» → Meta.buy_chest), текущий пепел. Звук chest / buy.

var _lid: Node3D
var _glow: OmniLight3D


func _ready() -> void:
	radius = 1.4
	prompt = "Открыть Сандык"
	super._ready()
	_build()


func _build() -> void:
	var wood := Color(0.48, 0.2, 0.12)
	var iron := HubProps.mat(Color(0.75, 0.6, 0.3), 0.35, 0.8)
	# ножки и корпус
	for p in [Vector3(-0.55, 0.06, -0.3), Vector3(0.55, 0.06, -0.3), Vector3(-0.55, 0.06, 0.3), Vector3(0.55, 0.06, 0.3)]:
		HubProps.box(self, Vector3(0.14, 0.12, 0.14), p, HubProps.WOOD_DARK)
	HubProps.box(self, Vector3(1.3, 0.62, 0.78), Vector3(0, 0.43, 0), wood)
	# окованные полосы и орнамент «қошқар мүйіз»
	for x in [-0.5, 0.0, 0.5]:
		HubProps.box(self, Vector3(0.08, 0.64, 0.8), Vector3(x, 0.43, 0), iron)
	HubProps.box(self, Vector3(1.32, 0.06, 0.8), Vector3(0, 0.2, 0), iron)
	for s in [-1.0, 1.0]:
		HubProps.torus(self, 0.08, 0.12, Vector3(0.25 * s, 0.45, 0.4), iron, Vector3(90, 0, 0))
	# крышка на шарнире (задний край)
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.74, -0.39)
	add_child(_lid)
	HubProps.box(_lid, Vector3(1.32, 0.16, 0.8), Vector3(0, 0.08, 0.39), wood.darkened(0.1))
	HubProps.box(_lid, Vector3(1.34, 0.05, 0.82), Vector3(0, 0.17, 0.39), iron)
	HubProps.box(_lid, Vector3(0.16, 0.2, 0.06), Vector3(0, 0.0, 0.8), iron)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(0.5, 0.75, 1.0)
	_glow.light_energy = 0.0
	_glow.omni_range = 3.0
	_glow.position = Vector3(0, 1.0, 0)
	add_child(_glow)
	HubProps.solid_box(self, Vector3(1.3, 0.9, 0.8), Vector3(0, 0.45, 0))
	HubProps.label(self, "Сандык", Vector3(0, 1.45, 0), Color(0.75, 0.85, 1.0), 34)


func set_open(open: bool) -> void:
	if _lid == null:
		return
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_lid, "rotation_degrees:x", -70.0 if open else 0.0, 0.35)
	tw.parallel().tween_property(_glow, "light_energy", 2.2 if open else 0.0, 0.3)


func activate(player: Node) -> void:
	if not can_activate(player):
		return
	activated.emit(player)
	Sfx.play("chest")
	set_open(true)
	var w := ChestWindow.new()
	w.closed.connect(set_open.bind(false))
	w.open_on(get_tree().current_scene if get_tree().current_scene else get_tree().root, player)
