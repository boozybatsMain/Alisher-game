extends Node
## Глобальное состояние: асыки, вечная прокачка (Алтын Сандық),
## статистика забегов и данные текущего забега (Дары, оберег).

signal asyks_changed(value: int)
signal gifts_changed

const Gifts := preload("res://scripts/data/gifts.gd")
const SAVE_PATH := "user://batyr_save.json"

## Вечная прокачка в сундуке: стоимость каждого следующего уровня.
const UPGRADES := {
	"max_hp": {"title": "Сила Батыра", "desc": "+15 к максимальному здоровью", "costs": [10, 20, 35, 55, 80]},
	"breath": {"title": "Дыхание степи", "desc": "−8% к перезарядке кувырка и щита", "costs": [10, 20, 35, 55, 80]},
	"damage": {"title": "Закалка сабли", "desc": "+3 к базовому урону сабли", "costs": [15, 25, 40, 60, 90]},
}
const UPGRADE_ORDER := ["max_hp", "breath", "damage"]

## Подношения священному очагу (От-Ана) перед забегом.
const OFFER_GIFT_COST := 15
const OFFER_AMULET_COST := 20

var asyks := 0
var upgrades := {"max_hp": 0, "breath": 0, "damage": 0}
var stats := {
	"runs": 0, "deaths": 0, "victories": 0, "best_cycle": 0, "best_stage": 0, "best_wave": 0,
	"kills": 0, "asyks_total": 0, "last_run": {},
}

# --- текущий забег ---
var gifts: Array = [null, null, null]  # {"god": String, "level": int} или null
var amulet := false        # Тұмар: одно воскрешение
var offered_gift := false  # подношение «стартовый Дар» уже сделано
var cycle := 1             # круг Кургана (после победы над финальным боссом можно идти дальше — сложнее)
var stage := 0             # 0 — Степной Курган, 1 — Сердце Кургана
var hp_carry := -1.0       # здоровье, с которым герой переходит на следующую стадию
var run_kills := 0
var run_asyks := 0
var return_reason := ""    # "death" / "victory" — для сообщения в Юрте


func _ready() -> void:
	load_game()


# ------------------------------------------------------------ характеристики
func max_hp() -> float:
	return 100.0 + 15.0 * upgrades["max_hp"]


func cooldown_mult() -> float:
	return 1.0 - 0.08 * upgrades["breath"]


func saber_damage() -> float:
	return 14.0 + 3.0 * upgrades["damage"]


# ------------------------------------------------------------ асыки
func add_asyks(n: int) -> void:
	asyks += n
	run_asyks += n
	stats["asyks_total"] += n
	asyks_changed.emit(asyks)


func spend(n: int) -> bool:
	if asyks < n:
		return false
	asyks -= n
	asyks_changed.emit(asyks)
	save_game()
	return true


func upgrade_cost(key: String) -> int:
	var lvl: int = upgrades[key]
	var costs: Array = UPGRADES[key]["costs"]
	return costs[lvl] if lvl < costs.size() else -1


func buy_upgrade(key: String) -> bool:
	var cost := upgrade_cost(key)
	if cost < 0 or not spend(cost):
		return false
	upgrades[key] += 1
	save_game()
	return true


# ------------------------------------------------------------ Дары
func gift_god(slot: int) -> String:
	return gifts[slot]["god"] if gifts[slot] != null else ""


func gift_level(slot: int) -> int:
	return gifts[slot]["level"] if gifts[slot] != null else 0


func has_gift(slot: int, god: String) -> bool:
	return gift_god(slot) == god


func gift_value(slot: int) -> Dictionary:
	if gifts[slot] == null:
		return {}
	return Gifts.value(gifts[slot]["god"], slot, gifts[slot]["level"])


func set_gift(slot: int, god: String) -> void:
	if gifts[slot] != null and gifts[slot]["god"] == god:
		gifts[slot]["level"] = mini(3, gifts[slot]["level"] + 1)
	else:
		gifts[slot] = {"god": god, "level": 1}
	gifts_changed.emit()


func next_empty_slot() -> int:
	for i in 3:
		if gifts[i] == null:
			return i
	return -1


func offer_starting_gift() -> String:
	## Подношение очагу: случайный Дар в первый слот.
	if offered_gift or not spend(OFFER_GIFT_COST):
		return ""
	offered_gift = true
	var god: String = Gifts.GOD_ORDER.pick_random()
	set_gift(0, god)
	return god


func offer_amulet() -> bool:
	if amulet or not spend(OFFER_AMULET_COST):
		return false
	amulet = true
	gifts_changed.emit()
	return true


# ------------------------------------------------------------ забег
func start_run() -> void:
	stats["runs"] += 1
	cycle = 1
	stage = 0
	hp_carry = -1.0
	run_kills = 0
	run_asyks = 0
	save_game()


func abandon_run() -> void:
	## Выход в меню посреди вылазки: Дары и оберег пропадают, статистика не трогается.
	gifts = [null, null, null]
	amulet = false
	offered_gift = false
	stage = 0
	hp_carry = -1.0
	gifts_changed.emit()
	save_game()


func register_kill() -> void:
	run_kills += 1
	stats["kills"] += 1


func end_run(died: bool, wave: int) -> void:
	stats["last_run"] = {"died": died, "cycle": cycle, "stage": stage, "wave": wave, "kills": run_kills, "asyks": run_asyks}
	if died:
		stats["deaths"] += 1
	else:
		stats["victories"] += 1
	var score := (cycle * 10 + stage) * 10 + wave
	var best: int = (int(stats["best_cycle"]) * 10 + int(stats["best_stage"])) * 10 + int(stats["best_wave"])
	if score > best:
		stats["best_cycle"] = cycle
		stats["best_stage"] = stage
		stats["best_wave"] = wave
	stage = 0
	hp_carry = -1.0
	return_reason = "death" if died else "victory"
	gifts = [null, null, null]
	amulet = false
	offered_gift = false
	gifts_changed.emit()
	save_game()


# ------------------------------------------------------------ сохранение
func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"asyks": asyks, "upgrades": upgrades, "stats": stats}, "\t"))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	asyks = int(data.get("asyks", 0))
	var up: Dictionary = data.get("upgrades", {})
	for k in upgrades:
		upgrades[k] = int(up.get(k, 0))
	var st: Dictionary = data.get("stats", {})
	for k in stats:
		if st.has(k):
			stats[k] = st[k] if k == "last_run" else int(st[k])


func reset_save() -> void:
	asyks = 0
	for k in upgrades:
		upgrades[k] = 0
	for k in stats:
		stats[k] = {} if k == "last_run" else 0
	asyks_changed.emit(asyks)
	save_game()
