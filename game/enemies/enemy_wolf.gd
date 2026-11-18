extends EnemyBase
## Көк-қасқыр скверны: быстрый, обходит с флангов, прыжок-укус с телеграфом-конусом, перепрыгивает между ярусами.

const BITE_RANGE := 3.4
const BITE_ANGLE := 70.0


func _setup() -> void:
	pref_dist = 2.6
	attack_cd_range = Vector2(1.3, 2.2) if not elite else Vector2(0.9, 1.5)


func _try_attack(_pl: Node3D, dist: float, dy: float) -> bool:
	if dist > BITE_RANGE + 0.6 or absf(dy) > 1.0 or not is_on_floor():
		return false
	var dir := facing
	var origin := global_position
	begin_attack("bite", 0.5, func(): _bite(origin, dir), 0.55)
	tele_cone(dir, BITE_RANGE, BITE_ANGLE)
	return true


func _bite(origin: Vector3, dir: Vector3) -> void:
	# короткий прыжок вперёд и укус по зоне телеграфа
	velocity = dir * 9.0 + Vector3(0, 4.0, 0)
	Sfx.play("swing_enemy", -4.0)
	strike_cone(origin, dir, BITE_RANGE, BITE_ANGLE, damage, {"knock": 5.0})
	if elite:
		# элитный волк — двойной укус
		var o2 := origin + dir * 1.5
		chain_attack("bite2", 0.45, func(): strike_cone(o2, dir, BITE_RANGE, BITE_ANGLE, damage * 0.8, {"knock": 5.0}), 0.6)
		tele_cone(dir, BITE_RANGE, BITE_ANGLE)
