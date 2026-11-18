class_name Player
extends CharacterBody3D
## ЗАГЛУШКА-КОНТРАКТ (модуль A заменит реализацию, сохранив API из ARCHITECTURE.md).

var facing := Vector3(0, 0, 1)
var airborne := false
var wall_kick_time := -100.0
var move_lock := 0.0
var blocking := false
var block_dir := Vector3.ZERO
var weapon: WeaponBase = null
var sprite: AnimatedSprite3D = null
var hit_radius := 0.45

func aim_dir() -> Vector3: return facing
func lunge(_dir: Vector3, _speed: float, _time: float) -> void: pass
func play_anim(_name: String, _speed := 1.0) -> void: pass
func invulnerable() -> bool: return false
func teleport_to(pos: Vector3) -> void: global_position = pos
func take_hit(_hit: Hit) -> void: pass
func get_facing() -> Vector3: return facing
func is_dead() -> bool: return false
