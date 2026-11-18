class_name EnemyData
extends RefCounted
## Данные врагов: характеристики, спрайты, ИИ-скрипты, пулы по биомам, боссы.
##
## Поля типа:
##   name — отображаемое имя; script — путь к скрипту-наследнику EnemyBase;
##   sprite — папка assets/sprites/<sprite>; pixel — pixel_size; scale — масштаб узла;
##   tint — цвет modulate; hp, dmg, speed (м/с), radius (hit_radius), height (м, для полос);
##   armor — базовая броня (без элиты); dirhams — [min, max]; flying, agile — подвижность;
##   anims — сопоставление логических анимаций с именами в SpriteFrames;
##   weight — частота в пуле; boss — true для боссов.

const SPRITES := "res://assets/sprites/%s/%s_frames.tres"

const TYPES := {
	"wolf": {
		"name": "Көк-қасқыр скверны", "script": "res://game/enemies/enemy_wolf.gd",
		"sprite": "wolf", "pixel": 0.0068, "scale": 1.0, "tint": Color(1, 1, 1),
		"hp": 34.0, "dmg": 9.0, "speed": 6.4, "radius": 0.55, "height": 1.3, "armor": 0.0,
		"dirhams": [2, 5], "flying": false, "agile": true,
		"anims": {"idle": "idle", "move": "run", "attack": "attack", "hurt": "hurt", "stun": "stun", "death": "death"},
	},
	"spirit": {
		"name": "Обезумевший дух", "script": "res://game/enemies/enemy_spirit.gd",
		"sprite": "spirit", "pixel": 0.0065, "scale": 1.0, "tint": Color(1, 1, 1, 0.92),
		"hp": 26.0, "dmg": 8.0, "speed": 4.2, "radius": 0.5, "height": 1.6, "armor": 0.0,
		"dirhams": [2, 4], "flying": true, "agile": true,
		"anims": {"idle": "float", "move": "float", "attack": "attack", "hurt": "hurt", "stun": "stun", "death": "death"},
	},
	"balbal": {
		"name": "Балбал-страж", "script": "res://game/enemies/enemy_balbal.gd",
		"sprite": "balbal", "pixel": 0.0068, "scale": 1.2, "tint": Color(1, 1, 1),
		"hp": 80.0, "dmg": 16.0, "speed": 2.2, "radius": 0.75, "height": 2.2, "armor": 40.0,
		"dirhams": [5, 9], "flying": false, "agile": false,
		"anims": {"idle": "idle", "move": "walk", "attack": "attack", "hurt": "hurt", "stun": "stun", "death": "crumble"},
	},
	"archer": {
		"name": "Аруақ-мерген", "script": "res://game/enemies/enemy_archer.gd",
		"sprite": "archer", "pixel": 0.0068, "scale": 1.0, "tint": Color(1, 1, 1),
		"hp": 28.0, "dmg": 9.0, "speed": 4.0, "radius": 0.5, "height": 1.7, "armor": 0.0,
		"dirhams": [3, 6], "flying": false, "agile": true,
		"anims": {"idle": "idle", "move": "walk", "attack": "attack", "hurt": "hurt", "stun": "stun", "death": "death"},
	},
	"shaman": {
		"name": "Бақсы Мглы", "script": "res://game/enemies/enemy_shaman.gd",
		"sprite": "shaman", "pixel": 0.0068, "scale": 1.0, "tint": Color(1, 1, 1),
		"hp": 40.0, "dmg": 10.0, "speed": 3.0, "radius": 0.55, "height": 1.8, "armor": 0.0,
		"dirhams": [5, 9], "flying": false, "agile": false,
		"anims": {"idle": "idle", "move": "walk", "attack": "attack", "hurt": "hurt", "stun": "hurt", "death": "death", "teleport": "teleport"},
	},
	"acrobat": {
		"name": "Ловкач Мглы", "script": "res://game/enemies/enemy_acrobat.gd",
		"sprite": "zhest", "pixel": 0.0052, "scale": 1.0, "tint": Color(0.55, 0.75, 0.95),
		"hp": 38.0, "dmg": 11.0, "speed": 6.0, "radius": 0.5, "height": 1.8, "armor": 0.0,
		"dirhams": [4, 7], "flying": false, "agile": true,
		"anims": {"idle": "idle", "move": "walk", "attack": "attack", "leap": "leap", "hurt": "hurt", "stun": "stun", "death": "death"},
	},
	# ------------------------------------------------------------ боссы
	"zhest": {
		"name": "Жезтырнақ", "script": "res://game/enemies/boss_zhest.gd", "boss": true,
		"sprite": "zhest", "pixel": 0.0072, "scale": 1.15, "tint": Color(1, 1, 1),
		"hp": 900.0, "dmg": 16.0, "speed": 5.5, "radius": 0.9, "height": 3.0, "armor": 0.0,
		"dirhams": [40, 60], "flying": false, "agile": true,
		"anims": {"idle": "idle", "move": "walk", "attack": "attack", "leap": "leap", "summon": "summon", "hurt": "hurt", "stun": "stun", "death": "death"},
	},
	"shoyyn": {
		"name": "Шойынқұлақ", "script": "res://game/enemies/boss_shoyyn.gd", "boss": true,
		"sprite": "shoyyn", "pixel": 0.0068, "scale": 1.0, "tint": Color(1, 1, 1),
		"hp": 1500.0, "dmg": 22.0, "speed": 3.2, "radius": 1.3, "height": 3.9, "armor": 260.0,
		"dirhams": [60, 90], "flying": false, "agile": false,
		"anims": {"idle": "idle", "move": "walk", "smash": "smash", "sweep": "sweep", "stomp": "stomp", "roar": "roar", "attack": "smash", "hurt": "hurt", "stun": "stun", "death": "death"},
	},
	"khan": {
		"name": "Первый хан рода — Тень бессмертия", "script": "res://game/enemies/boss_khan.gd", "boss": true,
		"sprite": "batyr", "pixel": 0.0072, "scale": 1.65, "tint": Color(0.42, 0.3, 0.55),
		"hp": 2200.0, "dmg": 24.0, "speed": 5.0, "radius": 1.0, "height": 3.6, "armor": 300.0,
		"dirhams": [0, 0], "flying": false, "agile": true,
		"anims": {"idle": "idle", "move": "run", "attack": "attack1", "attack2": "attack2", "attack3": "attack3", "dash": "dash", "roll": "roll", "block": "block", "hurt": "hurt", "stun": "hurt", "death": "death"},
	},
}

## Боссы по биомам (индекс = биом).
const BOSSES := ["zhest", "shoyyn", "khan"]

## Обычные враги по биомам: [{id, weight}].
const POOLS := [
	[{"id": "wolf", "weight": 4}, {"id": "spirit", "weight": 3}, {"id": "archer", "weight": 2}, {"id": "acrobat", "weight": 1}, {"id": "balbal", "weight": 1}],
	[{"id": "wolf", "weight": 2}, {"id": "spirit", "weight": 2}, {"id": "archer", "weight": 3}, {"id": "balbal", "weight": 2}, {"id": "shaman", "weight": 2}, {"id": "acrobat", "weight": 2}],
	[{"id": "wolf", "weight": 2}, {"id": "spirit", "weight": 2}, {"id": "archer", "weight": 2}, {"id": "balbal", "weight": 3}, {"id": "shaman", "weight": 3}, {"id": "acrobat", "weight": 3}],
]

## Цвета стихий (модификатор mods.element — враг гневного духа).
const ELEMENT_COLORS := {
	"tengri": Color("#8cc8ff"), "ai_mergen": Color("#c9b3ff"), "umai": Color("#ff8a3d"),
	"zher_su": Color("#5fd3c4"), "erlik": Color("#9b4dff"), "kokbori": Color("#e04848"),
}

## Цвета статусов (подсветка спрайта).
const STATUS_COLORS := {
	"burn": Color(1.0, 0.55, 0.25), "poison": Color(0.6, 1.0, 0.35), "bleed": Color(1.0, 0.3, 0.3),
	"slow": Color(0.6, 0.8, 1.0), "freeze": Color(0.55, 0.9, 1.0), "stun": Color(1.0, 1.0, 0.55),
	"curse": Color(0.75, 0.45, 1.0), "shock": Color(0.75, 0.9, 1.0),
}


## Кто водится в биоме: [{id, weight}] (веса для случайного выбора).
static func pool(biome: int) -> Array:
	return (POOLS[clampi(biome, 0, POOLS.size() - 1)] as Array).duplicate(true)


## Случайный тип из пула биома с учётом весов.
static func pick(biome: int, rng: RandomNumberGenerator = null) -> String:
	var p := pool(biome)
	var total := 0.0
	for e in p:
		total += float(e["weight"])
	var r := (rng.randf() if rng else randf()) * total
	for e in p:
		r -= float(e["weight"])
		if r <= 0.0:
			return String(e["id"])
	return String(p[0]["id"])


static func boss_for(biome: int) -> String:
	return BOSSES[clampi(biome, 0, BOSSES.size() - 1)]


static func display_name(id: String) -> String:
	if TYPES.has(id):
		return String(TYPES[id]["name"])
	return id


static func is_boss(id: String) -> bool:
	return TYPES.has(id) and bool(TYPES[id].get("boss", false))


static func data(id: String) -> Dictionary:
	return TYPES.get(id, TYPES["wolf"])
