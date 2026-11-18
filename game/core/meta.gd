extends Node
## Постоянный прогресс (сохраняется между забегами): Пепел Тамыра, Сундук Предков (Сандык),
## открытое оружие и аспекты, открытые кюи, сюжетные флаги. Файл: user://tamyr_save.json

const SAVE_PATH := "user://tamyr_save.json"
## Отдельный сейв для тестов/smoke/check: сцены из res://tools/ (или аргумент `-- test_save`) не трогают сейв игрока,
## даже если прогон прерван посередине. `-- real_save` — принудительно работать с настоящим сейвом.
const TEST_SAVE_PATH := "user://tamyr_test_save.json"

var save_path: String = _pick_save_path()   ## фактический путь сейва (см. _pick_save_path)

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
## Цена открытия аспектов 1..3 (аспект 0 — базовый, открыт вместе с оружием).
const ASPECT_COSTS := [0, 80, 160, 260]

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


static func _pick_save_path() -> String:
	var user_args := OS.get_cmdline_user_args()
	if "real_save" in user_args:
		return SAVE_PATH
	if "test_save" in user_args:
		return TEST_SAVE_PATH
	for a in OS.get_cmdline_args():
		if String(a).begins_with("res://tools/"):
			return TEST_SAVE_PATH
	return SAVE_PATH


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
	if not aspects_unlocked.has(id) or aspect < 0 or aspect >= ASPECT_COSTS.size():
		return false
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
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"ash": ash, "chest": chest, "weapons_unlocked": weapons_unlocked, "aspects_unlocked": aspects_unlocked,
		"equipped_weapon": equipped_weapon, "equipped_aspect": equipped_aspect, "kuis_unlocked": kuis_unlocked,
		"kui_prepared": kui_prepared, "story": story, "stats": stats, "last_run": last_run,
	}, "\t"))


func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(d) != TYPE_DICTIONARY:
		return
	# Каждое поле проверяется по типу: битый/отредактированный руками сейв не роняет загрузку на середине.
	ash = maxi(0, _int(d.get("ash"), 0))
	var c = d.get("chest")
	for k in chest:
		var lvl := _int(c.get(k), 0) if c is Dictionary else 0
		chest[k] = clampi(lvl, 0, (CHEST[k]["costs"] as Array).size())
	weapons_unlocked = {"sword": true}
	var wu = d.get("weapons_unlocked")
	if wu is Dictionary:
		for k in wu:
			if String(k) in WEAPONS and _bool(wu[k]):
				weapons_unlocked[String(k)] = true
	var au = d.get("aspects_unlocked")
	for k in aspects_unlocked:
		var arr: Array = [0]
		if au is Dictionary and au.get(k) is Array:
			for a in au[k]:
				var ai := _int(a, -1)
				if ai > 0 and ai < ASPECT_COSTS.size() and not (ai in arr):
					arr.append(ai)
		aspects_unlocked[k] = arr
	equipped_weapon = String(d.get("equipped_weapon")) if d.get("equipped_weapon") is String else "sword"
	equipped_aspect = _int(d.get("equipped_aspect"), 0)
	if not weapons_unlocked.get(equipped_weapon, false) or not (equipped_aspect in aspects_unlocked.get(equipped_weapon, [])):
		equipped_weapon = "sword"
		equipped_aspect = 0
	kuis_unlocked = []
	var ku = d.get("kuis_unlocked")
	if ku is Array:
		for k in ku:
			if k is String and not (k in kuis_unlocked):
				kuis_unlocked.append(k)
	kui_prepared = String(d.get("kui_prepared")) if d.get("kui_prepared") is String else ""
	var s = d.get("story")
	story = {"step": 0, "seen": [], "flags": {}}
	if s is Dictionary:
		story["step"] = _int(s.get("step"), 0)
		if s.get("seen") is Array:
			story["seen"] = Array(s["seen"])
		if s.get("flags") is Dictionary:
			story["flags"] = s["flags"]
	var st = d.get("stats")
	for k in stats:
		stats[k] = _int(st.get(k), 0) if st is Dictionary else 0
	var lr = d.get("last_run")
	last_run = lr if lr is Dictionary else {}


## int из значения JSON (float/int/bool/строка-число); всё прочее — def.
static func _int(v, def: int) -> int:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
			return int(v)
		TYPE_STRING:
			return int(v) if String(v).is_valid_float() else def
	return def


static func _bool(v) -> bool:
	match typeof(v):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			return bool(v)
	return false


func reset_save() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
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
