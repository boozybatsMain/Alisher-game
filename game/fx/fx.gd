class_name Fx3D
extends RefCounted
## Общие 3D-эффекты (статические помощники). Все функции безопасны в headless и при parent == null
## (тогда ничего не делают и возвращают null). Узлы эффектов удаляют себя сами.
##
## API:
##   Fx3D.burst(parent, pos, color, count := 12, speed := 4.0, size := 0.18) -> Node3D
##       — разлёт искр (спрайты spark.png, аддитивно), гаснут за ~0.4 с.
##   Fx3D.ring(parent, pos, radius, color, time := 0.35, width := 0.25) -> Node3D
##       — кольцо-волна на земле: растёт от 0 до radius и тает.
##   Fx3D.flash_sprite(sprite: SpriteBase3D, color := Color(3,3,3), time := 0.12)
##       — вспышка спрайта (modulate → color → исходный).
##   Fx3D.slash_arc(parent, pos, dir, radius, angle_deg := 140.0, color := Color(1,0.9,0.6), time := 0.15, height := 0.9) -> Node3D
##       — видимая дуга удара (полупрозрачный сектор-полоса над землёй), тает за time.
##   Fx3D.lightning(parent, a, b, color := Color(0.6,0.8,1), time := 0.2) -> Node3D
##       — ломаная молния от a к b.
##   Fx3D.telegraph_circle(parent, pos, radius, time := 0.5, color := Color(1,0.15,0.1)) -> Node3D
##       — красная зона на земле: контур сразу, заливка растёт от центра за time, затем вспышка и исчезает.
##   Fx3D.telegraph_cone(parent, pos, dir, radius, angle_deg, time := 0.5, color := ...) -> Node3D
##       — то же для сектора (конуса) с вершиной в pos, направлением dir (XZ).
##   Fx3D.telegraph_line(parent, a, b, width, time := 0.5, color := ...) -> Node3D
##       — то же для прямоугольной полосы от a к b (рывки, выстрелы).
##   Fx3D.flash_light(parent, pos, color, energy := 4.0, range := 5.0, time := 0.2) -> OmniLight3D
##       — короткая цветная вспышка света.
##   Fx3D.puff(parent, pos, color := Color(0.85,0.8,0.7,0.8), count := 6) -> Node3D — облачко пыли (приземление, рывок).
##   Fx3D.number(parent, pos, text, color, size := 48, rise := 1.2, time := 0.9) -> Label3D — всплывающий текст.
##   Fx3D.cancel(node) — досрочно убрать эффект (например, если враг прерван — телеграф снимается).
## Высота y у зон на земле берётся из pos (+0.03, чтобы не мерцало с полом).

const TEX_SPARK := "res://assets/fx/spark.png"
const TEX_PUFF := "res://assets/fx/puff.png"
const TEX_SOFT := "res://assets/fx/soft.png"

static var _tex_cache := {}


static func _tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex_cache[path] = t
	return t


static func _ok(parent: Node) -> bool:
	return parent != null and is_instance_valid(parent) and parent.is_inside_tree()


static func _mat(color: Color, additive := true, unshaded := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	return m


static func _root(parent: Node, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = "Fx"
	parent.add_child(n)
	n.global_position = pos
	return n


static func _free_after(n: Node, secs: float) -> void:
	if not is_instance_valid(n) or not n.is_inside_tree():
		return
	var tw := n.create_tween()
	tw.tween_interval(secs)
	tw.tween_callback(n.queue_free)


# ================================================================ искры
static func burst(parent: Node, pos: Vector3, color: Color, count := 12, speed := 4.0, size := 0.18) -> Node3D:
	if not _ok(parent):
		return null
	var root := _root(parent, pos)
	var tex := _tex(TEX_SOFT)
	for i in count:
		var s := Sprite3D.new()
		s.texture = tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		s.modulate = color
		s.render_priority = 2
		var px := size / (float(tex.get_width()) if tex else 1.0)
		s.pixel_size = px * randf_range(0.6, 1.4)
		var mat := _mat(color)
		mat.albedo_texture = tex
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		s.material_override = mat
		root.add_child(s)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)).normalized()
		var dist := speed * randf_range(0.05, 0.12)
		var life := randf_range(0.25, 0.45)
		var tw := s.create_tween().set_parallel(true)
		tw.tween_property(s, "position", dir * dist * 3.0, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(s, "modulate:a", 0.0, life)
		tw.tween_property(mat, "albedo_color:a", 0.0, life)
	_free_after(root, 0.5)
	return root


static func puff(parent: Node, pos: Vector3, color := Color(0.85, 0.8, 0.7, 0.8), count := 6) -> Node3D:
	if not _ok(parent):
		return null
	var root := _root(parent, pos)
	var tex := _tex(TEX_PUFF)
	for i in count:
		var s := Sprite3D.new()
		s.texture = tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.modulate = color
		s.pixel_size = 0.6 / maxf(1.0, float(tex.get_width()) if tex else 1.0)
		root.add_child(s)
		var a := TAU * float(i) / float(count) + randf() * 0.5
		var d := Vector3(cos(a), 0.15, sin(a))
		s.position = d * 0.2
		s.scale = Vector3.ONE * 0.5
		var tw := s.create_tween().set_parallel(true)
		tw.tween_property(s, "position", d * randf_range(0.6, 1.0) + Vector3(0, 0.25, 0), 0.45).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "scale", Vector3.ONE * 1.2, 0.45)
		tw.tween_property(s, "modulate:a", 0.0, 0.45)
	_free_after(root, 0.5)
	return root


# ================================================================ кольца/зоны на земле
## Плоская кольцевая сетка (ArrayMesh) в плоскости XZ.
static func _ring_mesh(r_in: float, r_out: float, a0 := 0.0, a1 := TAU, seg := 48) -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for i in seg:
		var t0 := lerpf(a0, a1, float(i) / seg)
		var t1 := lerpf(a0, a1, float(i + 1) / seg)
		var p0i := Vector3(cos(t0) * r_in, 0, sin(t0) * r_in)
		var p0o := Vector3(cos(t0) * r_out, 0, sin(t0) * r_out)
		var p1i := Vector3(cos(t1) * r_in, 0, sin(t1) * r_in)
		var p1o := Vector3(cos(t1) * r_out, 0, sin(t1) * r_out)
		verts.append_array([p0i, p0o, p1o, p0i, p1o, p1i])
		for k in 6:
			cols.append(Color.WHITE)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Сектор (заливка) с вершиной в 0, ось +X, раствор a0..a1.
static func _sector_mesh(r: float, a0: float, a1: float, seg := 32) -> ArrayMesh:
	return _ring_mesh(0.0, r, a0, a1, seg)


static func _rect_mesh(length: float, width: float, x0 := 0.0) -> ArrayMesh:
	var h := width * 0.5
	var verts := PackedVector3Array([
		Vector3(x0, 0, -h), Vector3(length, 0, -h), Vector3(length, 0, h),
		Vector3(x0, 0, -h), Vector3(length, 0, h), Vector3(x0, 0, h)])
	var cols := PackedColorArray()
	for k in 6:
		cols.append(Color.WHITE)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _mesh_node(root: Node3D, mesh: Mesh, color: Color, additive := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _mat(color, additive)
	root.add_child(mi)
	return mi


static func ring(parent: Node, pos: Vector3, radius: float, color: Color, time := 0.35, width := 0.25) -> Node3D:
	if not _ok(parent):
		return null
	var root := _root(parent, pos + Vector3(0, 0.04, 0))
	var mi := _mesh_node(root, _ring_mesh(maxf(0.0, 1.0 - width / maxf(radius, 0.01)), 1.0), color)
	mi.scale = Vector3.ONE * 0.05
	var mat := mi.material_override as StandardMaterial3D
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 1, radius), time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	_free_after(root, time + 0.05)
	return root


static func _telegraph(root: Node3D, outline: Mesh, fill_mesh: Mesh, time: float, color: Color, fill_from_center: bool) -> void:
	var out := _mesh_node(root, outline, Color(color.r, color.g, color.b, 0.85), false)
	var base := _mesh_node(root, fill_mesh, Color(color.r, color.g, color.b, 0.16), false)
	var fill := _mesh_node(root, fill_mesh, Color(color.r * 1.2, color.g, color.b, 0.45), false)
	base.position.y = -0.005
	fill.position.y = 0.005
	out.position.y = 0.01
	fill.scale = Vector3(0.02, 1, 0.02) if fill_from_center else Vector3(0.02, 1, 1)
	var fmat := fill.material_override as StandardMaterial3D
	var omat := out.material_override as StandardMaterial3D
	var bmat := base.material_override as StandardMaterial3D
	var tw := root.create_tween()
	tw.tween_property(fill, "scale", Vector3.ONE, maxf(time, 0.01))
	# вспышка в момент удара
	tw.tween_callback(func():
		fmat.albedo_color = Color(1.0, 0.85, 0.7, 0.85)
		omat.albedo_color = Color(1, 1, 1, 1))
	tw.set_parallel(true)
	tw.tween_property(fmat, "albedo_color:a", 0.0, 0.18)
	tw.tween_property(omat, "albedo_color:a", 0.0, 0.18)
	tw.tween_property(bmat, "albedo_color:a", 0.0, 0.18)
	tw.set_parallel(false)
	tw.tween_callback(root.queue_free)


static func telegraph_circle(parent: Node, pos: Vector3, radius: float, time := 0.5, color := Color(1, 0.15, 0.1)) -> Node3D:
	if not _ok(parent):
		return null
	var root := _root(parent, pos + Vector3(0, 0.03, 0))
	root.name = "Telegraph"
	_telegraph(root, _ring_mesh(maxf(0.0, radius - 0.08), radius), _sector_mesh(radius, 0.0, TAU, 40), time, color, true)
	return root


static func telegraph_cone(parent: Node, pos: Vector3, dir: Vector3, radius: float, angle_deg: float, time := 0.5, color := Color(1, 0.15, 0.1)) -> Node3D:
	if not _ok(parent):
		return null
	var root := _root(parent, pos + Vector3(0, 0.03, 0))
	root.name = "Telegraph"
	var half := deg_to_rad(angle_deg * 0.5)
	var d := Vector2(dir.x, dir.z)
	if d.length_squared() < 0.0001:
		d = Vector2(0, 1)
	# сетки строятся вокруг +X; поворачиваем узел к dir (угол в XZ: atan2(z, x), вращение вокруг Y — минус)
	root.rotation.y = -atan2(d.y, d.x)
	_telegraph(root, _ring_mesh(maxf(0.0, radius - 0.08), radius, -half, half, 24), _sector_mesh(radius, -half, half, 24), time, color, true)
	return root


static func telegraph_line(parent: Node, a: Vector3, b: Vector3, width: float, time := 0.5, color := Color(1, 0.15, 0.1)) -> Node3D:
	if not _ok(parent):
		return null
	var root := _root(parent, a + Vector3(0, 0.03, 0))
	root.name = "Telegraph"
	var d := Vector2(b.x - a.x, b.z - a.z)
	var length := maxf(0.1, d.length())
	root.rotation.y = -atan2(d.y, d.x)
	var outline := _rect_mesh(length, width)
	_telegraph(root, outline, _rect_mesh(length, width * 0.92), time, color, false)
	# контур — тонкая полупрозрачная рамка (используем ту же полосу, но ниже альфа уже в _telegraph)
	return root


static func cancel(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()


# ================================================================ дуга удара
static func slash_arc(parent: Node, pos: Vector3, dir: Vector3, radius: float, angle_deg := 140.0, color := Color(1, 0.9, 0.6), time := 0.15, height := 0.9) -> Node3D:
	if not _ok(parent):
		return null
	var root := _root(parent, pos + Vector3(0, height, 0))
	var d := Vector2(dir.x, dir.z)
	if d.length_squared() < 0.0001:
		d = Vector2(0, 1)
	root.rotation.y = -atan2(d.y, d.x)
	var half := deg_to_rad(angle_deg * 0.5)
	# полоса-серп: внутренний радиус 55%, с градиентом альфы по углу (ярче к концу удара)
	var seg := 28
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for i in seg:
		var t0 := float(i) / seg
		var t1 := float(i + 1) / seg
		var a0 := lerpf(-half, half, t0)
		var a1 := lerpf(-half, half, t1)
		var ri0 := radius * lerpf(0.85, 0.5, sin(t0 * PI))
		var ri1 := radius * lerpf(0.85, 0.5, sin(t1 * PI))
		var p0i := Vector3(cos(a0) * ri0, 0, sin(a0) * ri0)
		var p0o := Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var p1i := Vector3(cos(a1) * ri1, 0, sin(a1) * ri1)
		var p1o := Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var c0 := Color(1, 1, 1, t0 * 0.9 + 0.1)
		var c1 := Color(1, 1, 1, t1 * 0.9 + 0.1)
		verts.append_array([p0i, p0o, p1o, p0i, p1o, p1i])
		cols.append_array([Color(c0, c0.a * 0.3), c0, c1, Color(c0, c0.a * 0.3), c1, Color(c1, c1.a * 0.3)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := _mesh_node(root, m, color)
	var mat := mi.material_override as StandardMaterial3D
	mi.scale = Vector3(0.8, 1, 0.8)
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.08, 1, 1.08), time).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	_free_after(root, time + 0.05)
	return root


# ================================================================ молния
static func lightning(parent: Node, a: Vector3, b: Vector3, color := Color(0.6, 0.8, 1.0), time := 0.2) -> Node3D:
	if not _ok(parent):
		return null
	var root := _root(parent, Vector3.ZERO)
	root.global_position = Vector3.ZERO
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := _mat(Color(color.r * 2.0, color.g * 2.0, color.b * 2.0, 1.0))
	mi.material_override = mat
	root.add_child(mi)
	var pts: Array[Vector3] = [a]
	var n := maxi(4, int(a.distance_to(b) * 2.0))
	var side := (b - a).cross(Vector3.UP).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	for i in range(1, n):
		var t := float(i) / n
		var p := a.lerp(b, t) + side * randf_range(-0.35, 0.35) + Vector3(0, randf_range(-0.25, 0.25), 0)
		pts.append(p)
	pts.append(b)
	# лента шириной w, повёрнутая «к верху» (и к боку) — две перекрещенные ленты для объёма
	var w := 0.09
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in [Vector3.UP, side]:
		for i in pts.size() - 1:
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[i + 1]
			var o: Vector3 = axis * w
			im.surface_set_color(Color.WHITE)
			im.surface_add_vertex(p0 - o)
			im.surface_add_vertex(p0 + o)
			im.surface_add_vertex(p1 + o)
			im.surface_add_vertex(p0 - o)
			im.surface_add_vertex(p1 + o)
			im.surface_add_vertex(p1 - o)
	im.surface_end()
	var tw := root.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, time)
	tw.tween_callback(root.queue_free)
	flash_light(parent, b, color, 3.0, 4.0, time)
	return root


static func flash_light(parent: Node, pos: Vector3, color: Color, energy := 4.0, range := 5.0, time := 0.2) -> OmniLight3D:
	if not _ok(parent):
		return null
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = pos + Vector3(0, 0.6, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time)
	tw.tween_callback(l.queue_free)
	return l


# ================================================================ спрайты и текст
static func flash_sprite(sprite: SpriteBase3D, color := Color(3, 3, 3), time := 0.12) -> void:
	if sprite == null or not is_instance_valid(sprite) or not sprite.is_inside_tree():
		return
	var base: Color = sprite.get_meta("fx_base_modulate", sprite.modulate)
	sprite.set_meta("fx_base_modulate", base)
	sprite.modulate = color
	var tw := sprite.create_tween()
	tw.tween_property(sprite, "modulate", base, time)


static func number(parent: Node, pos: Vector3, text: String, color: Color, size := 48, rise := 1.2, time := 0.9) -> Label3D:
	if not _ok(parent):
		return null
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0.06, 0.03, 0.02, 0.9)
	l.font_size = size
	l.outline_size = maxi(6, size / 6)
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.render_priority = 10
	l.outline_render_priority = 9
	l.double_sided = true
	parent.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.25, 0.25), 0, randf_range(-0.15, 0.15))
	l.scale = Vector3.ONE * 0.6
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector3.ONE * 1.15, 0.08).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector3.ONE, 0.1)
	var tw2 := l.create_tween().set_parallel(true)
	tw2.tween_property(l, "position:y", l.position.y + rise, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw2.tween_property(l, "modulate:a", 0.0, time * 0.45).set_delay(time * 0.55)
	tw2.tween_property(l, "outline_modulate:a", 0.0, time * 0.45).set_delay(time * 0.55)
	_free_after(l, time + 0.05)
	return l
