class_name EnemyFactory
extends RefCounted
## ЗАГЛУШКА (модуль C).
static func spawn(type_id: String, parent: Node, pos: Vector3, _mods := {}) -> EnemyBase:
	var e := EnemyBase.new()
	e.type_id = type_id
	parent.add_child(e)
	e.global_position = pos
	return e
