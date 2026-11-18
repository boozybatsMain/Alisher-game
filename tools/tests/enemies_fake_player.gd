extends CharacterBody3D
## Фейковый герой для enemies_test: стоит на месте, считает полученный урон.

var hit_radius := 0.45
var sliding := false
var facing := Vector3(0, 0, 1)
var damage_taken := 0.0
var hits := 0
var by_source := {}
var invuln := false
var hold_pos := true


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)


func _physics_process(delta: float) -> void:
	velocity.y -= 30.0 * delta
	if hold_pos:
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()


func take_hit(hit: Hit) -> void:
	if invuln:
		return
	hits += 1
	damage_taken += hit.amount
	var t := "?"
	if hit.source != null and is_instance_valid(hit.source):
		var tid = hit.source.get("type_id")
		t = String(tid) if tid != null else "?"
	by_source[t] = by_source.get(t, 0.0) + hit.amount


func invulnerable() -> bool:
	return invuln


func is_dead() -> bool:
	return false


func get_facing() -> Vector3:
	return facing
