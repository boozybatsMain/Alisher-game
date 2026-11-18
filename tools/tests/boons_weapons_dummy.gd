extends Node3D
## Манекен-цель для boons_weapons_test: бессмертный, считает урон по тегам/видам.

var hit_radius := 0.5
var statuses := {}
var facing := Vector3(0, 0, 1)
var total := 0.0
var by_kind := {}
var by_tag := {}
var hits := 0
var launched := false


func _ready() -> void:
	add_to_group("hurtable_enemy")
	add_to_group("enemies")


func take_hit(hit: Hit) -> void:
	total += hit.amount
	hits += 1
	by_kind[hit.kind] = float(by_kind.get(hit.kind, 0.0)) + hit.amount
	for t in hit.tags:
		by_tag[t] = float(by_tag.get(t, 0.0)) + hit.amount
	if hit.launch:
		launched = true
	for s in hit.statuses:
		apply_status(String(s.get("id", "")), s)
	Bus.hit_landed.emit(hit, self)
	Bus.damage_number.emit(global_position + Vector3(0, 1.8, 0), hit.amount, "crit" if hit.is_crit else hit.kind)


func apply_status(id: String, params: Dictionary) -> void:
	statuses[id] = params.duplicate()


func knock(_v: Vector3) -> void:
	pass


func get_facing() -> Vector3:
	return facing


func is_dead() -> bool:
	return false


func reset_stats() -> void:
	total = 0.0
	hits = 0
	by_kind.clear()
	by_tag.clear()
	statuses.clear()
	launched = false
