class_name WeaponBase
extends Node3D
## ЗАГЛУШКА-КОНТРАКТ (модуль B заменит реализацию, сохранив API из ARCHITECTURE.md).

var player: Player = null
var id := ""
var aspect := 0

func setup(p_player: Player, p_aspect: int) -> void:
	player = p_player
	aspect = p_aspect
func attack_pressed() -> void: pass
func attack_released() -> void: pass
func special_pressed() -> void: pass
func special_released() -> void: pass
func tick(_delta: float) -> void: pass
func is_busy() -> bool: return false
func cancel() -> void: pass
func move_mult() -> float: return 1.0
func air_special() -> void: pass
