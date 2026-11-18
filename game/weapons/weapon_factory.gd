class_name WeaponFactory
extends RefCounted
## Создаёт оружие по id: sword / spear / shield / bow / gauntlets.

const SCRIPTS := {
	"sword": "res://game/weapons/sword.gd",
	"spear": "res://game/weapons/spear.gd",
	"shield": "res://game/weapons/shield.gd",
	"bow": "res://game/weapons/bow.gd",
	"gauntlets": "res://game/weapons/gauntlets.gd",
}


static func create(p_id: String, aspect := 0) -> WeaponBase:
	var path: String = SCRIPTS.get(p_id, SCRIPTS["sword"])
	var w: WeaponBase = (load(path) as GDScript).new()
	w.id = p_id if SCRIPTS.has(p_id) else "sword"
	w.aspect = clampi(aspect, 0, Meta.ASPECT_COSTS.size() - 1)
	w.name = "Weapon"
	return w
