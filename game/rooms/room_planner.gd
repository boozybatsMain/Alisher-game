class_name RoomPlanner
extends RefCounted
## Структура забега (модуль D). 3 биома × (6 обычных комнат + босс). depth — сквозной номер комнаты (0..20).
## Внутри биома: local = depth % ROOMS_PER_BIOME; local 6 — босс, local 5 — часто Лавка Караванщика,
## из local 5 ведёт одна дверь — к боссу. После босса биома 2 забег заканчивается победой (это делает room.gd).
##
## Контракт: first_room() -> Dictionary, make_choices(current_room, rng) -> Array (1–2 двери).
## Формат комнаты (ARCHITECTURE.md) + доп. поля: "hp_mult", "dmg_mult" (масштаб сложности), "local" (номер в биоме).
##
## Сверх контракта (static):
##   RoomPlanner.biome_of(depth), local_of(depth), is_boss_depth(depth), difficulty(depth) -> {hp_mult, dmg_mult}
##   RoomPlanner.validate(room) -> String  ("" — комната корректна; иначе текст ошибки, для тестов)

const ROOMS_PER_BIOME := 7          ## 6 обычных + босс
const BIOMES := 3
const LAST_DEPTH := ROOMS_PER_BIOME * BIOMES - 1
const GODS := ["tengri", "ai_mergen", "umai", "zher_su", "erlik", "kokbori"]
const TYPES := ["combat", "elite", "boss", "merchant", "duel", "rest", "secret"]
const REWARDS := ["boon", "ash", "gold", "merchant", "upgrade", "heal", "kui"]

const DUEL_CHANCE := 0.08
const SEAL_CHANCE := 0.2
const ELITE_CHANCE := 0.25
const MERCHANT_BEFORE_BOSS := 0.7
const REST_CHANCE := 0.05
## Шанс, что в боевой комнате есть треснувшая плита стены с тайным ходом (room["secret"] = true).
## За ней — комната-испытание «secret» (без врагов) с «Забытой нотой». Видимых дверей с нотой больше нет.
const SECRET_CHANCE := 0.15

## Веса наград для обычной двери.
const REWARD_WEIGHTS := {"boon": 50.0, "ash": 15.0, "gold": 12.0, "merchant": 8.0, "upgrade": 8.0, "heal": 6.0}


static func biome_of(depth: int) -> int:
	return clampi(depth / ROOMS_PER_BIOME, 0, BIOMES - 1)


static func local_of(depth: int) -> int:
	return depth % ROOMS_PER_BIOME


static func is_boss_depth(depth: int) -> bool:
	return local_of(depth) == ROOMS_PER_BIOME - 1


## Масштаб сложности врагов по глубине.
static func difficulty(depth: int) -> Dictionary:
	var b := biome_of(depth)
	return {"hp_mult": 1.0 + 0.07 * depth + 0.15 * b, "dmg_mult": 1.0 + 0.045 * depth + 0.1 * b}


func first_room() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return _make(0, "combat", "boon", GODS[rng.randi_range(0, GODS.size() - 1)], rng)


## Двери после зачистки текущей комнаты: 1 (перед боссом) или 2. Пусто — забег закончен (финальный босс).
func make_choices(current: Dictionary, rng: RandomNumberGenerator) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var d := int(current.get("depth", 0)) + 1
	if d > LAST_DEPTH:
		return []
	var loc := local_of(d)
	if loc == ROOMS_PER_BIOME - 1:
		return [_make(d, "boss", "ash", "", rng)]
	var out := []
	var cur_type := String(current.get("type", ""))
	var cur_reward := String(current.get("reward", ""))
	# --- «Спор Духов»
	if d >= 2 and loc < ROOMS_PER_BIOME - 2 and cur_type != "duel" and rng.randf() < DUEL_CHANCE:
		var g1 := _god(rng, [])
		var duel := _make(d, "duel", "boon", g1, rng)
		duel["god2"] = _god(rng, [g1])
		out.append(duel)
	# --- перед боссом — часто торговец
	if loc == ROOMS_PER_BIOME - 2 and cur_type != "merchant" and rng.randf() < MERCHANT_BEFORE_BOSS:
		out.append(_make(d, "merchant", "merchant", "", rng))
	# --- привал
	if out.size() < 2 and loc >= 2 and loc <= 4 and rng.randf() < REST_CHANCE:
		out.append(_make(d, "rest", "heal", "", rng))
	while out.size() < 2:
		var used_rewards := []
		var used_gods := []
		for r in out:
			used_rewards.append(String(r["reward"]))
			if String(r.get("god", "")) != "":
				used_gods.append(String(r["god"]))
			if String(r.get("god2", "")) != "":
				used_gods.append(String(r["god2"]))
		var reward := _pick_reward(rng, used_rewards, d, cur_type, cur_reward)
		if reward == "merchant":
			out.append(_make(d, "merchant", "merchant", "", rng))
		elif reward == "boon":
			out.append(_combat(d, "boon", _god(rng, used_gods), rng))
		else:
			out.append(_combat(d, reward, "", rng))
	return out


func _combat(d: int, reward: String, god: String, rng: RandomNumberGenerator) -> Dictionary:
	var t := "combat"
	if d >= 3 and rng.randf() < ELITE_CHANCE:
		t = "elite"
	var r := _make(d, t, reward, god, rng)
	r["seal"] = rng.randf() < SEAL_CHANCE
	r["secret"] = rng.randf() < SECRET_CHANCE and d >= 1 and not _locked_kuis().is_empty()
	return r


## Тайная комната за разрушенной плитой: та же глубина (после неё двери ведут дальше как обычно),
## награда — «Забытая нота» (если все кюи открыты — Пепел).
static func secret_room(from: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var d := int(from.get("depth", 0))
	var diff := difficulty(d)
	return {"type": "secret", "reward": "kui" if not _locked_kuis().is_empty() else "ash", "god": "", "god2": "",
		"depth": d, "biome": biome_of(d), "local": local_of(d), "seed": rng.randi(), "seal": false, "secret": false,
		"hp_mult": diff["hp_mult"], "dmg_mult": diff["dmg_mult"]}


func _make(d: int, type: String, reward: String, god: String, rng: RandomNumberGenerator) -> Dictionary:
	var diff := difficulty(d)
	return {"type": type, "reward": reward, "god": god, "god2": "", "depth": d, "biome": biome_of(d),
		"local": local_of(d), "seed": rng.randi(), "seal": false,
		"hp_mult": diff["hp_mult"], "dmg_mult": diff["dmg_mult"]}


func _god(rng: RandomNumberGenerator, exclude: Array) -> String:
	var pool := []
	for g in GODS:
		if not (g in exclude):
			pool.append(g)
	if pool.is_empty():
		pool = GODS.duplicate()
	return String(pool[rng.randi_range(0, pool.size() - 1)])


func _pick_reward(rng: RandomNumberGenerator, used: Array, d: int, cur_type: String, cur_reward: String) -> String:
	var w := REWARD_WEIGHTS.duplicate()
	# торговец не подряд и не в самом начале
	if d < 2 or cur_type == "merchant" or local_of(d) == 0:
		w.erase("merchant")
	# улучшение — только если есть что улучшать
	if not _has_upgradable():
		w.erase("upgrade")
	# лечение — чаще, если герой ранен
	if w.has("heal") and Run.active and Run.hp < Run.max_hp() * 0.5:
		w["heal"] = 18.0
	if cur_reward == "heal":
		w.erase("heal")
	var total := 0.0
	for k in w:
		# разные награды у двух дверей (кроме «дух vs дух» — допускается, но реже)
		var f := 1.0
		if k in used:
			f = 0.35 if k == "boon" else 0.0
		total += float(w[k]) * f
	var r := rng.randf() * total
	for k in w:
		var f := 1.0
		if k in used:
			f = 0.35 if k == "boon" else 0.0
		r -= float(w[k]) * f
		if r <= 0.0 and float(w[k]) * f > 0.0:
			return String(k)
	return "boon"


func _has_upgradable() -> bool:
	if Run.boons == null:
		return false
	if Run.boons.has_method("upgradable"):
		return not (Run.boons.upgradable() as Array).is_empty()
	if Run.boons.has_method("owned"):
		return not (Run.boons.owned() as Array).is_empty()
	return false


static func _locked_kuis() -> Array:
	var out := []
	for k in Run.KUIS:
		if not (k in Meta.kuis_unlocked):
			out.append(k)
	return out


## Проверка корректности словаря комнаты. "" — ок.
static func validate(room: Dictionary) -> String:
	for k in ["type", "reward", "god", "depth", "biome", "seed", "seal"]:
		if not room.has(k):
			return "нет поля " + k
	var t := String(room["type"])
	if not (t in TYPES):
		return "тип " + t
	if not (String(room["reward"]) in REWARDS):
		return "награда " + String(room["reward"])
	var d := int(room["depth"])
	if d < 0 or d > LAST_DEPTH:
		return "глубина %d" % d
	if int(room["biome"]) != biome_of(d):
		return "биом не совпадает с глубиной"
	if t == "boss" and not is_boss_depth(d):
		return "босс не в конце биома"
	if is_boss_depth(d) and t != "boss":
		return "в конце биома не босс"
	if String(room["reward"]) == "boon" and not (String(room["god"]) in GODS):
		return "дар без духа"
	if t == "duel":
		if not (String(room.get("god2", "")) in GODS) or room["god2"] == room["god"]:
			return "duel без второго духа"
	if t == "secret" and not (String(room["reward"]) in ["kui", "ash"]):
		return "тайная комната с наградой " + String(room["reward"])
	if t == "merchant" and String(room["reward"]) != "merchant":
		return "торговец с наградой " + String(room["reward"])
	if bool(room["seal"]) and not (t in ["combat", "elite"]):
		return "печать не на боевой комнате"
	return ""
