class_name EnemyTelegraph
extends RefCounted
## Телеграфия атак врагов «как в Hades»: красная зона на земле. Контур виден сразу, заливка растёт
## за time секунд, в момент удара — яркая вспышка и исчезновение. Своя реализация (не зависит от game/fx).
##
## API (все функции возвращают Node3D или null, узлы удаляют себя сами):
##   EnemyTelegraph.circle(parent, pos, radius, time := 0.5, color := RED)
##   EnemyTelegraph.cone(parent, pos, dir, radius, angle_deg, time := 0.5, color := RED)
##   EnemyTelegraph.line(parent, a, b, width, time := 0.5, color := RED)
##   EnemyTelegraph.ring(parent, pos, r_in, r_out, time := 0.5, color := RED)   — кольцо (волна по земле)
##   EnemyTelegraph.cancel(node)  — снять досрочно (враг прерван)

const RED := Color(1.0, 0.12, 0.08)
const Y_LIFT := 0.04


static func _ok(parent: Node) -> bool:
	return parent != null and is_instance_valid(parent) and parent.is_inside_tree()


static func _mat(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.render_priority = 2
	return m


## Сектор/круг в плоскости XZ, ось 0° = +X. r_in > 0 — кольцо.
static func sector_mesh(r_in: float, r_out: float, a0: float, a1: float, seg := 40) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var t0 := a0 + (a1 - a0) * float(i) / seg
		var t1 := a0 + (a1 - a0) * float(i + 1) / seg
		var o0 := Vector3(cos(t0), 0, -sin(t0))
		var o1 := Vector3(cos(t1), 0, -sin(t1))
		if r_in <= 0.001:
			st.add_vertex(Vector3.ZERO)
			st.add_vertex(o0 * r_out)
			st.add_vertex(o1 * r_out)
		else:
			st.add_vertex(o0 * r_in)
			st.add_vertex(o0 * r_out)
			st.add_vertex(o1 * r_out)
			st.add_vertex(o0 * r_in)
			st.add_vertex(o1 * r_out)
			st.add_vertex(o1 * r_in)
	return st.commit()


static func rect_mesh(length: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := width * 0.5
	for v in [Vector3(0, 0, -w), Vector3(length, 0, -w), Vector3(length, 0, w), Vector3(0, 0, -w), Vector3(length, 0, w), Vector3(0, 0, w)]:
		st.add_vertex(v)
	return st.commit()


static func _node(parent: Node, pos: Vector3, dir: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Telegraph"
	parent.add_child(root)
	root.global_position = pos + Vector3(0, Y_LIFT, 0)
	if dir.length_squared() > 0.0001:
		root.rotation.y = atan2(-dir.z, dir.x)
	root.add_to_group("enemy_telegraph")
	return root


static func _mi(root: Node3D, mesh: Mesh, color: Color, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color, alpha)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


static func _animate(root: Node3D, outline: MeshInstance3D, fill: MeshInstance3D, time: float, grow_x_only: bool) -> void:
	fill.scale = Vector3(0.02, 1, 1) if grow_x_only else Vector3(0.02, 1, 0.02)
	var tw := root.create_tween()
	tw.tween_property(fill, "scale", Vector3.ONE, maxf(time, 0.05)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		(fill.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.75, 0.6, 0.85)
		(outline.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.9, 0.8, 0.7))
	tw.tween_property(root, "scale", Vector3(1.06, 1, 1.06), 0.06)
	tw.tween_property(fill, "transparency", 1.0, 0.14)
	tw.parallel().tween_property(outline, "transparency", 1.0, 0.14)
	tw.tween_callback(root.queue_free)


static func circle(parent: Node, pos: Vector3, radius: float, time := 0.5, color := RED) -> Node3D:
	if not _ok(parent):
		return null
	var root := _node(parent, pos, Vector3.ZERO)
	var outline := _mi(root, sector_mesh(maxf(radius - 0.12, 0.0), radius, 0, TAU, 48), color, 0.85)
	var bg := _mi(root, sector_mesh(0.0, radius, 0, TAU, 48), color, 0.13)
	bg.name = "Bg"
	var fill := _mi(root, sector_mesh(0.0, radius, 0, TAU, 48), color, 0.42)
	_animate(root, outline, fill, time, false)
	return root


static func ring(parent: Node, pos: Vector3, r_in: float, r_out: float, time := 0.5, color := RED) -> Node3D:
	if not _ok(parent):
		return null
	var root := _node(parent, pos, Vector3.ZERO)
	var outline := _mi(root, sector_mesh(r_in, r_out, 0, TAU, 56), color, 0.35)
	var fill := _mi(root, sector_mesh(r_in, r_out, 0, TAU, 56), color, 0.45)
	_animate(root, outline, fill, time, false)
	fill.scale = Vector3.ONE
	return root


static func cone(parent: Node, pos: Vector3, dir: Vector3, radius: float, angle_deg: float, time := 0.5, color := RED) -> Node3D:
	if not _ok(parent):
		return null
	var root := _node(parent, pos, dir)
	var h := deg_to_rad(angle_deg) * 0.5
	var outline := _mi(root, sector_mesh(maxf(radius - 0.12, 0.0), radius, -h, h, 32), color, 0.85)
	_mi(root, sector_mesh(0.0, radius, -h, h, 32), color, 0.13)
	var fill := _mi(root, sector_mesh(0.0, radius, -h, h, 32), color, 0.42)
	_animate(root, outline, fill, time, false)
	return root


static func line(parent: Node, a: Vector3, b: Vector3, width: float, time := 0.5, color := RED) -> Node3D:
	if not _ok(parent):
		return null
	var d := b - a
	d.y = 0.0
	var ln := maxf(d.length(), 0.1)
	var root := _node(parent, a, d)
	var outline := _mi(root, rect_mesh(ln, width), color, 0.16)
	var fill := _mi(root, rect_mesh(ln, width * 0.55), color, 0.5)
	_animate(root, outline, fill, time, true)
	return root


static func cancel(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
