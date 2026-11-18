class_name WeaponModel
extends RefCounted
## Процедурные 3D-модели оружия (клинок, копьё, щит-диск с орнаментом, лук, перчатки).
## Модель смотрит вдоль -Z (как Node3D.look_at). В meta модели:
##   "glow" — Array[StandardMaterial3D] светящихся частей (цвет аспекта),
##   "string" — MeshInstance3D тетивы лука (для вспышки идеального натяжения).

const C_STEEL := Color(0.78, 0.8, 0.82)
const C_WOOD := Color(0.42, 0.26, 0.14)
const C_GOLD := Color(0.86, 0.66, 0.26)
const C_FELT := Color(0.62, 0.18, 0.14)
const C_LEATHER := Color(0.35, 0.22, 0.13)
const C_OCHRE := Color(0.78, 0.55, 0.25)


static func build(id: String, glow: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var glows: Array = []
	root.set_meta("glow", glows)
	match id:
		"sword": _sword(root, glow, glows)
		"spear": _spear(root, glow, glows)
		"shield": _shield(root, glow, glows)
		"bow": _bow(root, glow, glows)
		"gauntlets": _gauntlets(root, glow, glows)
		_: _sword(root, glow, glows)
	return root


static func set_glow(model: Node3D, color: Color, energy := 2.2) -> void:
	if model == null or not model.has_meta("glow"):
		return
	for m in model.get_meta("glow"):
		var sm := m as StandardMaterial3D
		sm.emission = color
		sm.emission_energy_multiplier = energy
		sm.albedo_color = color.lerp(Color.WHITE, 0.35)


static func _glow_mat(c: Color, glows: Array) -> StandardMaterial3D:
	var m := WeaponFx.solid(c.lerp(Color.WHITE, 0.35), c, 2.2, 0.2, 0.3)
	glows.append(m)
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, segs := 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## Меч: рукоять, гарда-полумесяц, клинок с светящейся кромкой.
static func _sword(root: Node3D, glow: Color, glows: Array) -> void:
	var steel := WeaponFx.solid(C_STEEL, Color.BLACK, 0.0, 0.8, 0.25)
	var gold := WeaponFx.solid(C_GOLD, Color.BLACK, 0.0, 0.7, 0.35)
	var leather := WeaponFx.solid(C_LEATHER)
	_cyl(root, 0.035, 0.035, 0.22, Vector3(0, 0, 0.05), leather, Vector3(PI / 2, 0, 0), 8)
	_cyl(root, 0.05, 0.05, 0.05, Vector3(0, 0, 0.17), gold, Vector3(PI / 2, 0, 0), 8)
	_box(root, Vector3(0.28, 0.05, 0.05), Vector3(0, 0, -0.07), gold)
	_box(root, Vector3(0.07, 0.035, 0.05), Vector3(0.15, 0, -0.1), gold, Vector3(0, 0.5, 0))
	_box(root, Vector3(0.07, 0.035, 0.05), Vector3(-0.15, 0, -0.1), gold, Vector3(0, -0.5, 0))
	_box(root, Vector3(0.075, 0.018, 0.86), Vector3(0, 0, -0.52), steel)
	_box(root, Vector3(0.02, 0.022, 0.82), Vector3(0.042, 0, -0.52), _glow_mat(glow, glows))
	var tip := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.075, 0.14, 0.018)
	tip.mesh = pm
	tip.material_override = steel
	tip.position = Vector3(0, 0, -1.01)
	tip.rotation = Vector3(-PI / 2, 0, 0)
	root.add_child(tip)


## Копьё (найза): древко, листовидный наконечник, красная кисть.
static func _spear(root: Node3D, glow: Color, glows: Array) -> void:
	var wood := WeaponFx.solid(C_WOOD)
	var felt := WeaponFx.solid(C_FELT)
	_cyl(root, 0.03, 0.03, 2.0, Vector3(0, 0, -0.4), wood, Vector3(PI / 2, 0, 0), 8)
	_cyl(root, 0.045, 0.045, 0.08, Vector3(0, 0, -1.38), WeaponFx.solid(C_GOLD, Color.BLACK, 0.0, 0.7, 0.35), Vector3(PI / 2, 0, 0), 8)
	var head := _cyl(root, 0.0, 0.075, 0.42, Vector3(0, 0, -1.62), _glow_mat(glow, glows), Vector3(-PI / 2, 0, 0), 4)
	head.scale = Vector3(1, 1, 0.35)
	_box(root, Vector3(0.09, 0.14, 0.09), Vector3(0, -0.07, -1.3), felt)


## Щит (қалқан): диск войлок+кожа, светящийся обод, умбон и орнамент «қошқар мүйіз».
static func _shield(root: Node3D, glow: Color, glows: Array) -> void:
	var felt := WeaponFx.solid(C_FELT)
	var gold := WeaponFx.solid(C_GOLD, Color.BLACK, 0.0, 0.7, 0.35)
	var g := _glow_mat(glow, glows)
	var disc := _cyl(root, 0.46, 0.46, 0.06, Vector3.ZERO, felt, Vector3(PI / 2, 0, 0), 24)
	disc.name = "Disc"
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.5
	tm.rings = 24
	rim.mesh = tm
	rim.material_override = g
	rim.rotation = Vector3(PI / 2, 0, 0)
	root.add_child(rim)
	var boss := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.12
	boss.mesh = sm
	boss.material_override = gold
	boss.position = Vector3(0, 0, -0.04)
	root.add_child(boss)
	# орнамент: четыре «рога барана» по кругу
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI / 4.0
		var p := Vector3(cos(a) * 0.26, sin(a) * 0.26, -0.04)
		_box(root, Vector3(0.16, 0.035, 0.02), p, g, Vector3(0, 0, a + PI / 2))
		_box(root, Vector3(0.06, 0.035, 0.02), p + Vector3(cos(a + 0.9) * 0.08, sin(a + 0.9) * 0.08, 0), g, Vector3(0, 0, a))
		_box(root, Vector3(0.06, 0.035, 0.02), p + Vector3(cos(a - 0.9) * 0.08, sin(a - 0.9) * 0.08, 0), g, Vector3(0, 0, a))


## Лук (садақ): изогнутые плечи из сегментов + тетива.
static func _bow(root: Node3D, glow: Color, glows: Array) -> void:
	var wood := WeaponFx.solid(C_WOOD.lerp(C_OCHRE, 0.3))
	var gold := WeaponFx.solid(C_GOLD, Color.BLACK, 0.0, 0.7, 0.35)
	var g := _glow_mat(glow, glows)
	var n := 9
	var pts: Array[Vector3] = []
	for i in n + 1:
		var t := float(i) / float(n) * 2.0 - 1.0     # -1..1 по высоте
		var y := t * 0.62
		var z := -0.22 * (1.0 - t * t) + 0.06 * absf(t * t * t)  # выгнут вперёд, кончики загнуты
		pts.append(Vector3(0, y, z))
	for i in n:
		var a := pts[i]
		var b := pts[i + 1]
		var mid := (a + b) * 0.5
		var seg_len := a.distance_to(b)
		var mi := _box(root, Vector3(0.045, seg_len + 0.02, 0.05), mid, wood if i != 4 else gold)
		mi.rotation.x = -atan2(b.z - a.z, b.y - a.y)
	var top := pts[n]
	var bot := pts[0]
	var s := _box(root, Vector3(0.012, top.y - bot.y, 0.012), Vector3(0, 0, top.z), g)
	s.name = "String"
	root.set_meta("string", s)


## Железные перчатки: два кулака с светящимися костяшками.
static func _gauntlets(root: Node3D, glow: Color, glows: Array) -> void:
	var iron := WeaponFx.solid(Color(0.32, 0.33, 0.36), Color.BLACK, 0.0, 0.85, 0.35)
	var leather := WeaponFx.solid(C_LEATHER)
	var g := _glow_mat(glow, glows)
	for side in [-1.0, 1.0]:
		var fist := Node3D.new()
		fist.name = "FistL" if side < 0 else "FistR"
		fist.position = Vector3(0.2 * side, 0, 0)
		root.add_child(fist)
		_box(fist, Vector3(0.15, 0.13, 0.17), Vector3(0, 0, -0.05), iron)
		_box(fist, Vector3(0.13, 0.12, 0.16), Vector3(0, 0, 0.11), leather)
		_box(fist, Vector3(0.16, 0.04, 0.04), Vector3(0, 0.04, -0.15), g)
		_box(fist, Vector3(0.04, 0.04, 0.12), Vector3(0, 0.08, 0.0), g)
