class_name HubProps
extends RefCounted
## Процедурная геометрия Хаба: материалы степи и помощники-меши (короб, цилиндр, сфера, конус, тор, коллизии).

const OCHRE := Color(0.72, 0.52, 0.30)
const SAND := Color(0.80, 0.66, 0.44)
const GRASS := Color(0.47, 0.50, 0.27)
const FELT_WHITE := Color(0.86, 0.80, 0.68)
const FELT_RED := Color(0.62, 0.16, 0.13)
const FELT_BROWN := Color(0.45, 0.28, 0.18)
const WOOD := Color(0.42, 0.27, 0.15)
const WOOD_DARK := Color(0.26, 0.16, 0.09)
const STONE := Color(0.30, 0.29, 0.31)
const TURQ := Color(0.20, 0.66, 0.64)
const GOLD := Color(0.86, 0.66, 0.26)
const IRON := Color(0.33, 0.33, 0.36)

static var _mats := {}


static func mat(c: Color, rough := 0.9, metal := 0.0, emission := Color(0, 0, 0), e_energy := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%s|%.2f" % [c.to_html(), rough, metal, emission.to_html(), e_energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if e_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = e_energy
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


static func glow_mat(c: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _mi(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material, rot := Vector3.ZERO, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, pos: Vector3, c, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _mi(parent, bm, pos, _m(c), rot)


static func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, c, rot := Vector3.ZERO, segs := 16) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	return _mi(parent, cm, pos, _m(c), rot)


static func sphere(parent: Node3D, r: float, pos: Vector3, c, scale := Vector3.ONE, segs := 16) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = segs
	sm.rings = maxi(4, segs / 2)
	var mi := _mi(parent, sm, pos, _m(c))
	mi.scale = scale
	return mi


static func capsule(parent: Node3D, r: float, h: float, pos: Vector3, c, rot := Vector3.ZERO) -> MeshInstance3D:
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = maxf(h, r * 2.0)
	cm.radial_segments = 10
	cm.rings = 4
	return _mi(parent, cm, pos, _m(c), rot)


static func torus(parent: Node3D, r_in: float, r_out: float, pos: Vector3, c, rot := Vector3.ZERO) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = r_in
	tm.outer_radius = r_out
	tm.rings = 24
	tm.ring_segments = 8
	return _mi(parent, tm, pos, _m(c), rot)


static func prism(parent: Node3D, size: Vector3, pos: Vector3, c, rot := Vector3.ZERO) -> MeshInstance3D:
	var pm := PrismMesh.new()
	pm.size = size
	return _mi(parent, pm, pos, _m(c), rot)


static func _m(c) -> Material:
	if c is Material:
		return c
	return mat(c as Color)


## Статическая коллизия-короб (слой мира).
static func solid_box(parent: Node3D, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = Combat.LAYER_WORLD
	sb.collision_mask = 0
	sb.position = pos
	sb.rotation_degrees = rot
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	parent.add_child(sb)
	return sb


static func solid_cyl(parent: Node3D, r: float, h: float, pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = Combat.LAYER_WORLD
	sb.collision_mask = 0
	sb.position = pos
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	sb.add_child(cs)
	parent.add_child(sb)
	return sb


static func label(parent: Node3D, text: String, pos: Vector3, color := Color(1, 0.92, 0.72), size := 40) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = size
	l.outline_size = 10
	l.pixel_size = 0.0055
	l.modulate = color
	l.outline_modulate = Color(0.08, 0.04, 0.03)
	l.no_depth_test = false
	l.render_priority = 4
	parent.add_child(l)
	return l


## Плоская спрайт-картинка (для задников, травы).
static func sprite(parent: Node3D, path: String, pos: Vector3, px := 0.01, billboard := false, tint := Color(1, 1, 1)) -> Sprite3D:
	if not ResourceLoader.exists(path):
		return null
	var s := Sprite3D.new()
	s.texture = load(path)
	s.position = pos
	s.pixel_size = px
	s.modulate = tint
	s.shaded = false
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	if billboard:
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	parent.add_child(s)
	return s


## Огонь: частицы пламени и искр + мерцающий свет. Возвращает узел-корень (у него meta "light").
static func fire(parent: Node3D, pos: Vector3, scale := 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Fire"
	root.position = pos
	parent.add_child(root)
	var tex: Texture2D = load("res://assets/fx/soft.png") if ResourceLoader.exists("res://assets/fx/soft.png") else null
	var flame := CPUParticles3D.new()
	flame.amount = 34
	flame.lifetime = 0.9
	flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flame.emission_sphere_radius = 0.35 * scale
	flame.direction = Vector3.UP
	flame.spread = 12.0
	flame.gravity = Vector3(0, 2.2, 0)
	flame.initial_velocity_min = 0.6
	flame.initial_velocity_max = 1.4
	flame.scale_amount_min = 0.6 * scale
	flame.scale_amount_max = 1.2 * scale
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1, 0.0))
	flame.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.45, 0.8))
	grad.set_color(1, Color(0.8, 0.12, 0.02, 0.0))
	grad.add_point(0.4, Color(1.0, 0.45, 0.1, 0.7))
	flame.color_ramp = grad
	var qm := QuadMesh.new()
	qm.size = Vector2(0.55, 0.55)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.vertex_color_use_as_albedo = true
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.albedo_texture = tex
	qm.material = fm
	flame.mesh = qm
	flame.position = Vector3(0, 0.25, 0)
	root.add_child(flame)
	var sparks := CPUParticles3D.new()
	sparks.amount = 18
	sparks.lifetime = 1.8
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.3 * scale
	sparks.direction = Vector3.UP
	sparks.spread = 25.0
	sparks.gravity = Vector3(0.3, 0.8, 0)
	sparks.initial_velocity_min = 1.2
	sparks.initial_velocity_max = 2.6
	sparks.scale_amount_min = 0.05
	sparks.scale_amount_max = 0.1
	var sg := Gradient.new()
	sg.set_color(0, Color(1, 0.8, 0.3, 1))
	sg.set_color(1, Color(1, 0.3, 0.05, 0))
	sparks.color_ramp = sg
	var sq := QuadMesh.new()
	sq.size = Vector2(0.5, 0.5)
	sq.material = fm
	sparks.mesh = sq
	sparks.position = Vector3(0, 0.5, 0)
	root.add_child(sparks)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.28)
	light.light_energy = 2.6
	light.omni_range = 9.0 * scale
	light.omni_attenuation = 1.3
	light.shadow_enabled = true
	light.position = Vector3(0, 1.0, 0)
	root.add_child(light)
	root.set_meta("light", light)
	root.set_meta("flame", flame)
	return root
