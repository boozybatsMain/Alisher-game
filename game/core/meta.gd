extends Node
## Постоянный прогресс (сохраняется между забегами): Пепел Тамыра, Сундук Предков (Сандык),
## открытое оружие и аспекты, открытые кюи, сюжетные флаги. Файл: user://tamyr_save.json

const SAVE_PATH := "user://tamyr_save.json"

## Сундук Предков. costs — цена каждого следующего уровня в Пепле.
const CHEST := {
	"reflexes": {"title": "Рефлексы Көкбөрі", "desc": "+1 заряд рывка и +5% скорости атаки за уровень", "costs": [40, 120]},
	"blood": {"title": "Кровь Батыра", "desc": "+10 к максимальному здоровью за уровень (до +100)", "costs": [10, 15, 20, 30, 40, 50, 65, 80, 100, 120]},
	"oath": {"title": "Клятва Жизни", "desc": "+1 воскрешение за забег (40% здоровья)", "costs": [60, 150, 300]},
	"shadow": {"title": "Тень Степи", "desc": "+10% урона при ударе в спину за уровень (до +50%)", "costs": [20, 35, 55, 80, 110]},
	"blessing": {"title": "Благословение Рода", "desc": "+5% шанса Редких и +2% Эпических даров за уровень", "costs": [30, 60, 100, 150]},
}
const CHEST_ORDER := ["reflexes", "blood", "oath", "shadow", "blessing"]

const WEAPONS := ["sword", "spear", "shield", "bow", "gauntlets"]
const WEAPON_UNLOCK_COST := {"sword": 0, "spear": 30, "shield": 40, "bow": 50, "gauntlets": 60}
## Цена открытия аспектов 1 и 2 (аспект 0 — базовый, открыт вместе с оружием).
const ASPECT_COSTS := [0, 80, 160]

var ash := 0
var chest := {"reflexes": 0, "blood": 0, "oath": 0, "shadow": 0, "blessing": 0}
var weapons_unlocked := {"sword": true}
var aspects_unlocked := {"sword": [0], "spear": [0], "shield": [0], "bow": [0], "gauntlets": [0]}
var equipped_weapon := "sword"
var equipped_aspect := 0
var kuis_unlocked: Array = []        ## id кюев (game/hub/kui_data.gd)
var kui_prepared := ""               ## кюй, сыгранный без ошибок перед выходом — бафф на следующий забег
var story := {"step": 0, "seen": [], "flags": {}}   ## сюжетный прогресс (game/hub/story.gd)
var stats := {"runs": 0, "deaths": 0, "victories": 0, "kills": 0, "best_depth": 0, "boss_kills": 0, "ash_total": 0}
var last_run := {}                   ## {"died": bool, "depth": int, "killer": String, "boss": String}


func _ready() -> void:
	load_game()


# ---------------------------------------------------------------- пепел
func add_ash(n: int) -> void:
	ash += n
	stats["ash_total"] += n
	Bus.ash_changed.emit(ash)


func spend_ash(n: int) -> bool:
	if ash < n:
		return false
	ash -= n
	Bus.ash_changed.emit(ash)
	save_game()
	return true


# ---------------------------------------------------------------- сундук
func chest_cost(key: String) -> int:
	var lvl: int = chest[key]
	var costs: Array = CHEST[key]["costs"]
	return costs[lvl] if lvl < costs.size() else -1


func buy_chest(key: String) -> bool:
	var c := chest_cost(key)
	if c < 0 or not spend_ash(c):
		return false
	chest[key] += 1
	save_game()
	return true


# ---------------------------------------------------------------- оружие
func unlock_weapon(id: String) -> bool:
	if weapons_unlocked.get(id, false):
		return true
	if not spend_ash(WEAPON_UNLOCK_COST[id]):
		return false
	weapons_unlocked[id] = true
	save_game()
	return true


func unlock_aspect(id: String, aspect: int) -> bool:
	if aspect in aspects_unlocked[id]:
		return true
	if not weapons_unlocked.get(id, false) or not spend_ash(ASPECT_COSTS[aspect]):
		return false
	aspects_unlocked[id].append(aspect)
	save_game()
	return true


func equip(id: String, aspect := 0) -> void:
	if not weapons_unlocked.get(id, false) or not (aspect in aspects_unlocked[id]):
		return
	equipped_weapon = id
	equipped_aspect = aspect
	save_game()
	Bus.weapon_changed.emit(id, aspect)


func unlock_kui(id: String) -> void:
	if not (id in kuis_unlocked):
		kuis_unlocked.append(id)
		save_game()


# ---------------------------------------------------------------- сохранение
func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"ash": ash, "chest": chest, "weapons_unlocked": weapons_unlocked, "aspects_unlocked": aspects_unlocked,
		"equipped_weapon": equipped_weapon, "equipped_aspect": equipped_aspect, "kuis_unlocked": kuis_unlocked,
		"kui_prepared": kui_prepared, "story": story, "stats": stats, "last_run": last_run,
	}, "\t"))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return
	ash = int(d.get("ash", 0))
	for k in chest:
		chest[k] = int(d.get("chest", {}).get(k, 0))
	for k in d.get("weapons_unlocked", {}):
		weapons_unlocked[k] = bool(d["weapons_unlocked"][k])
	for k in d.get("aspects_unlocked", {}):
		if aspects_unlocked.has(k):
			aspects_unlocked[k] = []
			for a in d["aspects_unlocked"][k]:
				aspects_unlocked[k].append(int(a))
	equipped_weapon = str(d.get("equipped_weapon", "sword"))
	equipped_aspect = int(d.get("equipped_aspect", 0))
	kuis_unlocked = Array(d.get("kuis_unlocked", []))
	kui_prepared = str(d.get("kui_prepared", ""))
	var s: Dictionary = d.get("story", {})
	story = {"step": int(s.get("step", 0)), "seen": Array(s.get("seen", [])), "flags": s.get("flags", {})}
	for k in stats:
		stats[k] = int(d.get("stats", {}).get(k, 0))
	last_run = d.get("last_run", {})


func reset_save() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	ash = 0
	for k in chest:
		chest[k] = 0
	weapons_unlocked = {"sword": true}
	aspects_unlocked = {"sword": [0], "spear": [0], "shield": [0], "bow": [0], "gauntlets": [0]}
	equipped_weapon = "sword"
	equipped_aspect = 0
	kuis_unlocked = []
	kui_prepared = ""
	story = {"step": 0, "seen": [], "flags": {}}
	for k in stats:
		stats[k] = 0
	last_run = {}
	Bus.ash_changed.emit(ash)
