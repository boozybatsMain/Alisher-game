class_name EnemyBase
extends CharacterBody3D
## ЗАГЛУШКА-КОНТРАКТ (модуль C заменит реализацию, сохранив API из ARCHITECTURE.md).
signal died(enemy: EnemyBase)

var type_id := ""
var hp := 30.0
var max_hp := 30.0
var armor := 0.0
var max_armor := 0.0
var elite := false
var statuses := {}
var hit_radius := 0.5
var facing := Vector3(0, 0, 1)

func take_hit(_hit: Hit) -> void: pass
func apply_status(_id: String, _params: Dictionary) -> void: pass
func knock(_v: Vector3) -> void: pass
func get_facing() -> Vector3: return facing
func is_dead() -> bool: return hp <= 0.0
