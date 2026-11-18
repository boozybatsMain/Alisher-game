class_name SpiritTotem
extends Interactable
## Тотем духа: резной столб-балбал с чашей огня цвета духа. Взаимодействие → окно выбора дара (BoonChoice).
## После выбора — сигнал taken(choice) и тотем гаснет. Комната ставит его после зачистки.

signal taken(choice: Dictionary)

@export var god := "tengri"

var used := false
var _light: OmniLight3D
var _flames: Array[Node3D] = []
var _label: Label3D
var _t := 0.0
var _choice_open := false


func _ready() -> void:
	if prompt == "Взаимодействовать":
		prompt = "E — принять дар"
	super._ready()
	_build()


func set_god(g: String) -> void:
	god = g
	if is_inside_tree():
		for c in get_children():
			if c.name == "Visual":
				c.queue_free()
		_flames.clear()
		_build()


func _build() -> void:
	var col := BoonData.god_color(god)
	var vis := Node3D.new()
	vis.name = "Visual"
	add_child(vis)
	var stone := WeaponFx.solid(Color(0.36, 0.33, 0.3), Color.BLACK, 0.0, 0.0, 0.9)
	var dark := WeaponFx.solid(Color(0.2, 0.18, 0.17), Color.BLACK, 0.0, 0.0, 0.95)
	var carve := WeaponFx.solid(col.darkened(0.3), col, 1.6)
	# постамент
	_mesh(vis, _cyl(0.75, 0.85, 0.3, 8), Vector3(0, 0.15, 0), dark)
	# столб-балбал
	var pillar := _mesh(vis, _box(Vector3(0.62, 1.9, 0.5)), Vector3(0, 1.25, 0), stone)
	pillar.rotation.y = 0.15
	# резное лицо: брови, глаза, усы, руки с чашей (смотрит на +Z, к камере)
	var face := Node3D.new()
	face.position = Vector3(0, 1.75, 0.26)
	face.rotation.y = 0.15
	vis.add_child(face)
	_mesh(face, _box(Vector3(0.44, 0.06, 0.05)), Vector3(0, 0.18, 0), dark)
	_mesh(face, _box(Vector3(0.1, 0.06, 0.05)), Vector3(-0.12, 0.08, 0.01), carve)
	_mesh(face, _box(Vector3(0.1, 0.06, 0.05)), Vector3(0.12, 0.08, 0.01), carve)
	_mesh(face, _box(Vector3(0.06, 0.2, 0.05)), Vector3(0, 0.0, 0.01), dark)
	_mesh(face, _box(Vector3(0.3, 0.05, 0.05)), Vector3(0, -0.14, 0.01), dark)
	_mesh(face, _box(Vector3(0.5, 0.06, 0.05)), Vector3(0, -0.55, 0.0), dark)
	_mesh(face, _box(Vector3(0.18, 0.14, 0.12)), Vector3(0.0, -0.66, 0.06), carve)
	# орнамент-пояс
	_mesh(vis, _box(Vector3(0.66, 0.08, 0.54)), Vector3(0, 0.55, 0), carve).rotation.y = 0.15
	# чаша огня
	_mesh(vis, _cyl(0.42, 0.22, 0.22, 12), Vector3(0, 2.32, 0), dark)
	_mesh(vis, _cyl(0.36, 0.36, 0.04, 12), Vector3(0, 2.43, 0), WeaponFx.solid(col, col, 3.0))
	# пламя: несколько билбордов мягкого света
	var soft: Texture2D = load(WeaponFx.TEX_SOFT) if ResourceLoader.exists(WeaponFx.TEX_SOFT) else null
	for i in 4:
		var s := Sprite3D.new()
		s.texture = soft
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.pixel_size = 0.01 - 0.0015 * i
		s.modulate = col.lerp(Color(1, 1, 0.85), 0.15 * i)
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.position = Vector3(0, 2.6 + 0.18 * i, 0)
		var m := StandardMaterial3D.new()
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = soft
		m.albedo_color = s.modulate
		s.material_override = m
		vis.add_child(s)
		_flames.append(s)
	_light = OmniLight3D.new()
	_light.light_color = col
	_light.light_energy = 2.2
	_light.omni_range = 6.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 2.8, 0)
	vis.add_child(_light)
	_label = Label3D.new()
	_label.text = BoonData.god_name(god)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = col.lerp(Color.WHITE, 0.3)
	_label.outline_modulate = Color(0.05, 0.03, 0.02)
	_label.outline_size = 10
	_label.font_size = 56
	_label.pixel_size = 0.006
	_label.position = Vector3(0, 3.55, 0)
	_label.no_depth_test = true
	vis.add_child(_label)
	if used:
		_extinguish(true)


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(top: float, bottom: float, h: float, segs: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	return c


func _process(delta: float) -> void:
	if used:
		return
	_t += delta
	for i in _flames.size():
		var f := _flames[i]
		var k := 1.0 + 0.18 * sin(_t * (7.0 + i * 2.3) + i)
		f.scale = Vector3(k * (1.0 - 0.1 * i), k * (1.1 + 0.1 * i), 1.0)
		f.position.y = 2.6 + 0.18 * i + 0.05 * sin(_t * 5.0 + i)
	if _light:
		_light.light_energy = 2.0 + 0.4 * sin(_t * 9.0) + 0.2 * sin(_t * 23.0)


func can_activate(_player: Node) -> bool:
	return enabled and not used and not _choice_open


func activate(player: Node) -> void:
	if not can_activate(player):
		return
	activated.emit(player)
	_choice_open = true
	Sfx.play("gift_open", -6.0)
	var host: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	var w := BoonChoice.open(host, god, _on_chosen)
	if w == null:
		_choice_open = false


func _on_chosen(choice: Dictionary) -> void:
	_choice_open = false
	used = true
	enabled = false
	taken.emit(choice)
	_extinguish(false)


func _extinguish(instant: bool) -> void:
	if instant:
		for f in _flames:
			f.visible = false
		if _light:
			_light.light_energy = 0.0
		if _label:
			_label.modulate.a = 0.35
		return
	var tw := create_tween()
	tw.set_parallel(true)
	for f in _flames:
		tw.tween_property(f, "scale", Vector3(0.05, 0.05, 1.0), 0.8)
	if _light:
		tw.tween_property(_light, "light_energy", 0.0, 1.0)
	if _label:
		tw.tween_property(_label, "modulate:a", 0.35, 1.0)
	if _light:
		WeaponFx.flash(self, _light.global_position, _light.light_color, 3.0, 0.4, WeaponFx.TEX_SOFT)
