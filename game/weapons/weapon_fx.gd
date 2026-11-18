class_name WeaponFx
extends RefCounted
## Простые 3D-эффекты оружия и Даров: дуги удара, вспышки, кольца, молнии.
## Всё создаётся процедурно, само гаснет и удаляется. Работает и в headless (меши просто не рисуются).

const TEX_SPARK := "res://assets/fx/spark.png"
const TEX_SOFT := "res://assets/fx/soft.png"
const TEX_RING := "res://assets/fx/shockwave.png"

static var _tex_cache := {}


static func _tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex_cache[path] = t
	return t


## Узел, куда класть эффекты: текущая сцена (или корень).
static func host(from: Node) -> Node:
	if from == null or not from.is_inside_tree():
		return null
	var sc := from.get_tree().current_scene
	return sc if sc != null else from.get_tree().root


static func add_mat(color: Color, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.disable_receive_shadows = true
	if tex:
		m.albedo_texture = tex
	return m


static func _fade_free(node: Node3D, mat: StandardMaterial3D, time: float, grow := 1.0) -> void:
	var tw := node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	if grow != 1.0:
		tw.tween_property(node, "scale", node.scale * grow, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.chain().tween_callback(node.queue_free)


## Дуга-полумесяц удара (лента треугольников в плоскости XZ).
static func slash_arc(from: Node, center: Vector3, dir: Vector3, radius: float, angle_deg: float, color: Color, time := 0.18, width := 0.55) -> void:
	var h := host(from)
	if h == null:
		return
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var segs := maxi(6, int(angle_deg / 10.0))
	var base_ang := atan2(dir.x, dir.z)
	var half := deg_to_rad(angle_deg) * 0.5
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in segs + 1:
		var t := float(i) / float(segs)
		var a := base_ang - half + t * half * 2.0
		var fade := sin(t * PI)
		var w := width * (0.3 + 0.7 * fade)
		var o := Vector3(sin(a), 0, cos(a))
		im.surface_set_color(Color(color.r, color.g, color.b, 0.0))
		im.surface_add_vertex(o * (radius - w))
		im.surface_set_color(Color(color.r * 1.4, color.g * 1.4, color.b * 1.4, fade))
		im.surface_add_vertex(o * radius)
	im.surface_end()
	mi.mesh = im
	var mat := add_mat(Color(1, 1, 1, 1))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.add_child(mi)
	mi.global_position = center
	_fade_free(mi, mat, time, 1.12)


## Вспышка-искра (билборд).
static func flash(from: Node, pos: Vector3, color: Color, size := 1.0, time := 0.16, tex_path := TEX_SPARK) -> void:
	var h := host(from)
	if h == null:
		return
	var s := Sprite3D.new()
	s.texture = _tex(tex_path)
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.pixel_size = 0.012 * size
	s.modulate = color
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.no_depth_test = false
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	h.add_child(s)
	s.global_position = pos
	s.rotation.z = randf() * TAU
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "modulate:a", 0.0, time)
	tw.tween_property(s, "scale", Vector3.ONE * 1.6, time)
	tw.chain().tween_callback(s.queue_free)
	if s.texture == null:
		s.queue_free()


## Кольцо-ударная волна на земле.
static func ring(from: Node, pos: Vector3, radius: float, color: Color, time := 0.3) -> void:
	var h := host(from)
	if h == null:
		return
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	mi.mesh = pm
	var tex := _tex(TEX_RING)
	var mat := add_mat(color, tex)
	mat.vertex_color_use_as_albedo = false
	if tex == null:
		mi.mesh = TorusMesh.new()
		(mi.mesh as TorusMesh).inner_radius = 0.85
		(mi.mesh as TorusMesh).outer_radius = 1.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.06, 0)
	mi.scale = Vector3.ONE * radius * 0.35
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## Молния от a к b — ломаная лента, видимая с камеры сверху-сбоку.
static func bolt(from: Node, a: Vector3, b: Vector3, color: Color, time := 0.22, width := 0.12) -> void:
	var h := host(from)
	if h == null:
		return
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var pts: Array[Vector3] = [a]
	var n := maxi(3, int(a.distance_to(b) / 0.7))
	var d := b - a
	var side := d.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	for i in range(1, n):
		var t := float(i) / float(n)
		pts.append(a + d * t + side * randf_range(-0.35, 0.35) + Vector3(0, randf_range(-0.25, 0.25), 0))
	pts.append(b)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size() - 1:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var seg := p1 - p0
		var off := seg.cross(Vector3(0.3, 1, 0.3)).normalized() * width
		var c := Color(color.r * 1.5, color.g * 1.5, color.b * 1.5, 1.0)
		for v in [p0 - off, p0 + off, p1 + off, p0 - off, p1 + off, p1 - off]:
			im.surface_set_color(c)
			im.surface_add_vertex(v)
	im.surface_end()
	mi.mesh = im
	var mat := add_mat(Color(1, 1, 1, 1))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.add_child(mi)
	mi.global_position = Vector3.ZERO
	_fade_free(mi, mat, time)
	flash(from, b, color, 1.2, time)


## Кратковременный цветной свет (вспышка освещения на арене).
static func light_pop(from: Node, pos: Vector3, color: Color, energy := 2.5, range_m := 4.0, time := 0.2) -> void:
	var h := host(from)
	if h == null:
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = false
	h.add_child(l)
	l.global_position = pos + Vector3(0, 0.8, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time)
	tw.tween_callback(l.queue_free)


## Простой эмиссионный материал для моделей.
static func solid(color: Color, emission := Color.BLACK, emission_energy := 0.0, metallic := 0.0, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m
