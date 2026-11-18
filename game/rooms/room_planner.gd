class_name RoomPlanner
extends RefCounted
## ЗАГЛУШКА (модуль D).
func first_room() -> Dictionary:
	return {"type": "combat", "reward": "boon", "god": "tengri", "depth": 0, "biome": 0, "seed": 1}
func make_choices(current: Dictionary, rng: RandomNumberGenerator) -> Array:
	var d := int(current.get("depth", 0)) + 1
	return [{"type": "combat", "reward": "boon", "god": "umai", "depth": d, "biome": 0, "seed": rng.randi()},
		{"type": "combat", "reward": "ash", "god": "", "depth": d, "biome": 0, "seed": rng.randi()}]
