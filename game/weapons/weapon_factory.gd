class_name WeaponFactory
extends RefCounted
## ЗАГЛУШКА (модуль B).
static func create(p_id: String, _aspect := 0) -> WeaponBase:
	var w := WeaponBase.new()
	w.id = p_id
	return w
