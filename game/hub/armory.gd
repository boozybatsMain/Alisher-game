class_name Armory
extends Node3D
## Оружейный шатёр: открытый навес на столбах с войлочной кровлей, 5 стоек (WeaponRack) полукругом у задней стены
## и «Чучело батыра» (TrainingDummy) в центре. Локальные оси: стойки — на -Z, вход открыт к +Z.

const ORDER := ["sword", "spear", "shield", "bow", "gauntlets"]

var racks: Array = []
var dummy: TrainingDummy
var roof: Array = []           ## меши кровли — Хаб делает их прозрачными, когда они закрывают героя


func _ready() -> void:
	_build()


func _build() -> void:
	# настил из досок
	HubProps.box(self, Vector3(9.0, 0.12, 7.0), Vector3(0, 0.06, -0.5), HubProps.WOOD_DARK)
	for i in 9:
		HubProps.box(self, Vector3(0.9, 0.02, 6.9), Vector3(-4.0 + i, 0.13, -0.5), HubProps.WOOD if i % 2 == 0 else HubProps.WOOD.darkened(0.12))
	# столбы с золотыми навершиями
	for p in [Vector3(-4.3, 0, -3.8), Vector3(4.3, 0, -3.8), Vector3(-4.3, 0, 2.8), Vector3(4.3, 0, 2.8), Vector3(0, 0, -3.8)]:
		HubProps.cyl(self, 0.14, 0.17, 3.6, p + Vector3(0, 1.8, 0), HubProps.WOOD)
		HubProps.sphere(self, 0.18, p + Vector3(0, 3.65, 0), HubProps.GOLD)
		HubProps.solid_cyl(self, 0.18, 3.6, p + Vector3(0, 1.8, 0))
	# кровля: два ската из войлока + красная кайма с орнаментом
	var roof_c := Color(0.74, 0.62, 0.46)
	roof.append(HubProps.box(self, Vector3(9.6, 0.12, 4.2), Vector3(0, 3.95, -1.85), roof_c, Vector3(-14, 0, 0)))
	roof.append(HubProps.box(self, Vector3(9.6, 0.12, 3.2), Vector3(0, 3.95, 2.0), roof_c.darkened(0.08), Vector3(12, 0, 0)))
	roof.append(HubProps.box(self, Vector3(9.7, 0.25, 0.08), Vector3(0, 3.45, 3.55), HubProps.FELT_RED))
	for i in 12:
		roof.append(HubProps.prism(self, Vector3(0.45, 0.32, 0.06), Vector3(-4.4 + i * 0.8, 3.2, 3.58), HubProps.GOLD, Vector3(0, 0, 180)))
	# задняя стенка-ширма из войлока (низкая, чтобы камера видела стойки)
	HubProps.box(self, Vector3(8.8, 1.2, 0.12), Vector3(0, 0.6, -4.0), HubProps.FELT_BROWN)
	HubProps.box(self, Vector3(8.8, 0.12, 0.14), Vector3(0, 1.15, -4.0), HubProps.FELT_RED)
	HubProps.solid_box(self, Vector3(8.8, 2.0, 0.3), Vector3(0, 1.0, -4.0))
	# стойки полукругом
	for i in ORDER.size():
		var r := WeaponRack.new()
		r.weapon_id = ORDER[i]
		r.name = "Rack_" + ORDER[i]
		var ang := lerpf(-0.75, 0.75, i / 4.0)
		r.position = Vector3(sin(ang) * 3.4, 0.12, -3.0 + (1.0 - cos(ang)) * 3.4)
		r.rotation.y = -ang * 0.8
		add_child(r)
		racks.append(r)
	# манекен в центре
	dummy = TrainingDummy.new()
	dummy.name = "TrainingDummy"
	dummy.position = Vector3(0, 0.12, 0.6)
	add_child(dummy)
	# фонари
	for x in [-4.3, 4.3]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.7, 0.4)
		l.light_energy = 1.4
		l.omni_range = 6.0
		l.position = Vector3(x * 0.9, 3.0, 2.6)
		add_child(l)
		HubProps.sphere(self, 0.16, Vector3(x * 0.95, 3.0, 2.8), HubProps.glow_mat(Color(1.0, 0.7, 0.35), 3.0))
	HubProps.label(self, "Оружейный шатёр", Vector3(0, 4.7, 3.0), Color(1, 0.85, 0.5), 52)
