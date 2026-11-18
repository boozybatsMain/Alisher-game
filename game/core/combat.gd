class_name Combat
extends RefCounted
## Помощники для боя: поиск целей в радиусе/конусе, применение удара.

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4
const LAYER_PROJECTILE := 8
const LAYER_INTERACT := 16
const LAYER_DESTRUCTIBLE := 32


## Все узлы группы `group` (по умолчанию "hurtable_enemy"), чьи центры в сфере. Без учёта стен.
static func in_radius(tree: SceneTree, center: Vector3, radius: float, group := "hurtable_enemy", max_dy := 2.5) -> Array:
	var out := []
	for n in tree.get_nodes_in_group(group):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var p: Vector3 = (n as Node3D).global_position
		if absf(p.y - center.y) > max_dy:
			continue
		var d := Vector2(p.x - center.x, p.z - center.z).length()
		if d <= radius + _radius_of(n):
			out.append(n)
	return out


## Цели в секторе: angle_deg — полный угол раствора, dir — направление (XZ).
static func in_cone(tree: SceneTree, center: Vector3, dir: Vector3, radius: float, angle_deg: float, group := "hurtable_enemy", max_dy := 2.5) -> Array:
	var out := []
	var d2 := Vector2(dir.x, dir.z).normalized()
	var half := deg_to_rad(angle_deg * 0.5)
	for n in in_radius(tree, center, radius, group, max_dy):
		var p: Vector3 = (n as Node3D).global_position
		var v := Vector2(p.x - center.x, p.z - center.z)
		if v.length() < 0.6 + _radius_of(n):
			out.append(n)
			continue
		if absf(d2.angle_to(v)) <= half:
			out.append(n)
	return out


## Цели вдоль отрезка (для выпадов копья, полёта стрел).
static func along_line(tree: SceneTree, a: Vector3, b: Vector3, width: float, group := "hurtable_enemy", max_dy := 2.5) -> Array:
	var out := []
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	for n in tree.get_nodes_in_group(group):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var p: Vector3 = (n as Node3D).global_position
		if absf(p.y - a.y) > max_dy:
			continue
		var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), a2, b2)
		if q.distance_to(Vector2(p.x, p.z)) <= width + _radius_of(n):
			out.append(n)
	return out


static func _radius_of(n: Node) -> float:
	var r = n.get("hit_radius")
	return float(r) if r != null else 0.5


## Ближайшая цель группы (для самонаведения).
static func nearest(tree: SceneTree, from: Vector3, max_dist := 30.0, group := "hurtable_enemy", exclude: Array = []) -> Node3D:
	var best: Node3D = null
	var bd := max_dist
	for n in tree.get_nodes_in_group(group):
		if n in exclude or not is_instance_valid(n) or not (n is Node3D):
			continue
		if n.has_method("is_dead") and n.is_dead():
			continue
		var d := from.distance_to((n as Node3D).global_position)
		if d < bd:
			bd = d
			best = n
	return best


## Удар от героя: прогоняет через Дары/апгрейды (Run.modify_outgoing) и отдаёт цели.
static func player_hit(target: Node, hit: Hit) -> void:
	if not is_instance_valid(target) or not target.has_method("take_hit"):
		return
	if not hit.no_boons:
		Run.modify_outgoing(hit, target)
	target.take_hit(hit)


## Есть ли стена между точками (луч по слою мира).
static func blocked(world: World3D, a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, LAYER_WORLD)
	return not world.direct_space_state.intersect_ray(q).is_empty()
