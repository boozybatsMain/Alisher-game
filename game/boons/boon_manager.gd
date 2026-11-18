class_name BoonManager
extends Node
## ЗАГЛУШКА-КОНТРАКТ (модуль B).
func reset() -> void: pass
func add_boon(_id: String) -> void: pass
func has_boon(_id: String) -> bool: return false
func level_of(_id: String) -> int: return 0
func level_up(_id: String) -> void: pass
func remove_boon(_id: String) -> int: return 0
func owned() -> Array: return []
func roll_choices(_god: String, _count := 3) -> Array: return []
func stat_bonus(_key: String) -> float: return 0.0
func modify_outgoing(_hit: Hit, _target: Node) -> void: pass
func modify_incoming(amount: float, _source: Node) -> float: return amount
