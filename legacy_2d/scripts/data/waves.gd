extends RefCounted
## Забег: две стадии по три волны. Третья волна каждой стадии — босс.
## Спавн: [вид врага, сторона (1 — справа, −1 — слева/сзади), задержка в секундах от начала волны].

const STAGES := [
	{
		"name": "Степной Курган", "theme": "day",
		"waves": [
			{"title": "Разведка", "spawns": [["balbal", 1, 0.0], ["balbal", -1, 1.2], ["spirit", 1, 3.0]]},
			{"title": "Натиск с двух флангов", "spawns": [
				["wolf", 1, 0.0], ["wolf", 1, 0.9], ["balbal", -1, 3.0], ["spirit", -1, 5.0], ["archer", 1, 6.5], ["wolf", -1, 9.0]]},
			{"title": "Жезтырнак — Медный Коготь", "boss": true, "spawns": [["zhest", 1, 0.8]]},
		],
	},
	{
		"name": "Сердце Кургана", "theme": "night",
		"waves": [
			{"title": "Стрелы аруаков", "spawns": [
				["archer", 1, 0.0], ["archer", -1, 0.6], ["wolf", 1, 1.8], ["wolf", -1, 2.4], ["spirit", 1, 4.0], ["balbal", -1, 5.0]]},
			{"title": "Шёпот бақсы", "spawns": [
				["shaman", 1, 0.0], ["balbal", -1, 0.8], ["wolf", 1, 2.0], ["archer", -1, 3.0], ["shaman", -1, 5.0], ["spirit", 1, 5.5]]},
			{"title": "Шойынқұлақ — Чугунное Ухо", "boss": true, "spawns": [["shoyyn", 1, 0.8]]},
		],
	},
]

## С каждым кругом враги крепче и их больше.
static func hp_mult(cycle: int) -> float:
	return 1.0 + 0.4 * (cycle - 1)


static func dmg_mult(cycle: int) -> float:
	return 1.0 + 0.25 * (cycle - 1)


static func extra_spawns(cycle: int, wave: Dictionary) -> Array:
	if wave.get("boss", false) or cycle <= 1:
		return []
	var out := []
	var pool := ["balbal", "wolf", "spirit", "archer"]
	for i in cycle - 1:
		out.append([pool[i % pool.size()], 1 if i % 2 == 0 else -1, 6.0 + i * 1.5])
	return out
