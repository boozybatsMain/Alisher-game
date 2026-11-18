extends Node
## Текущий забег: здоровье, дирхемы, дары, оружие, глубина, комнаты. Обнуляется при смерти.
## Также: сводные характеристики героя (stat), переходы между сценами.

const TITLE_SCENE := "res://game/scenes/title.tscn"
const HUB_SCENE := "res://game/hub/hub.tscn"
const ROOM_SCENE := "res://game/rooms/room.tscn"
const PLAYER_SCENE := "res://game/player/player.tscn"
const HUD_SCENE := "res://game/ui/hud.tscn"
const BOON_MANAGER := "res://game/boons/boon_manager.gd"
const ROOM_PLANNER := "res://game/rooms/room_planner.gd"

## Кюи (Забытые ноты) → бафф «Музыкальный заряд» на весь забег.
const KUIS := {
	"adai": {"title": "Адай", "desc": "+15% к скорости и дальности рывка", "stat": {"dash_speed_mult": 0.15}},
	"korkyt": {"title": "Қорқыт", "desc": "Идеальное уклонение замедляет время на 1 секунду", "stat": {}},
	"aksak_kulan": {"title": "Ақсақ құлан", "desc": "+12% к скорости бега", "stat": {"move_speed_mult": 0.12}},
	"balbyrauyn": {"title": "Балбырауын", "desc": "+10% к скорости атаки", "stat": {"attack_speed_mult": 0.10}},
	"kenes": {"title": "Кеңес", "desc": "+10% ко всему урону", "stat": {"damage_mult": 0.10}},
}

var active := false              ## забег идёт (false — в Хабе)
var depth := 0                   ## номер комнаты в забеге (0 — первая)
var biome := 0                   ## 0 — Осквернённая степь, 1 — Корни Байтерека, 2 — Чертог Ерлика
var hp := 100.0
var dirhams := 0
var ash_run := 0                 ## пепел, собранный за этот забег (уже добавлен в Meta)
var kills := 0
var revives_left := 0
var weapon := "sword"
var aspect := 0
var kui := ""                    ## активный Музыкальный заряд
var current_room: Dictionary = {}
var rooms_cleared := 0
var boss_kills := 0
var rng := RandomNumberGenerator.new()
var boons: Node = null           ## BoonManager (game/boons/boon_manager.gd)
var planner = null               ## RoomPlanner (game/rooms/room_planner.gd)
var hub_reason := ""             ## "death" / "victory" / "" — для диалогов в Хабе
var time_scale_lock := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(BOON_MANAGER):
		boons = load(BOON_MANAGER).new()
		boons.name = "BoonManager"
		add_child(boons)
	if ResourceLoader.exists(ROOM_PLANNER):
		planner = load(ROOM_PLANNER).new()


# ================================================================ характеристики
## Сводная характеристика героя: база + Сандык + Дары + кюй.
## Ключи: max_hp, move_speed_mult, attack_speed_mult, dash_charges, dash_speed_mult, damage_mult,
## crit_chance, crit_mult, backstab_mult, damage_taken_mult, rare_chance, epic_chance, revives.
func stat(key: String) -> float:
	var v := 0.0
	match key:
		"max_hp": v = 100.0 + 10.0 * Meta.chest["blood"]
		"move_speed_mult": v = 1.0
		"attack_speed_mult": v = 1.0 + 0.05 * Meta.chest["reflexes"]
		"dash_charges": v = 1.0 + Meta.chest["reflexes"]
		"dash_speed_mult": v = 1.0
		"damage_mult": v = 1.0
		"crit_chance": v = 0.03
		"crit_mult": v = 2.0
		"backstab_mult": v = 1.0 + 0.1 * Meta.chest["shadow"]
		"damage_taken_mult": v = 1.0
		"rare_chance": v = 0.18 + 0.05 * Meta.chest["blessing"]
		"epic_chance": v = 0.04 + 0.02 * Meta.chest["blessing"]
		"revives": v = Meta.chest["oath"]
	if boons and boons.has_method("stat_bonus"):
		v += boons.stat_bonus(key)
	if kui != "" and KUIS.has(kui):
		v += float(KUIS[kui]["stat"].get(key, 0.0))
	return v


func max_hp() -> float:
	return stat("max_hp")


func has_kui(id: String) -> bool:
	return kui == id


## Прогоняет удар героя через модификаторы: урон-множитель, крит, удар в спину, Дары.
func modify_outgoing(hit: Hit, target: Node) -> void:
	hit.amount *= stat("damage_mult")
	if not hit.is_crit and rng.randf() < stat("crit_chance"):
		hit.is_crit = true
	if boons and boons.has_method("modify_outgoing"):
		boons.modify_outgoing(hit, target)
	if hit.is_crit:
		hit.amount *= stat("crit_mult")
	if target is Node3D and hit.source is Node3D and target.has_method("get_facing"):
		var to_attacker: Vector3 = (hit.source as Node3D).global_position - (target as Node3D).global_position
		var f: Vector3 = target.get_facing()
		if Vector2(f.x, f.z).dot(Vector2(to_attacker.x, to_attacker.z)) < 0.0:
			hit.from_behind = true
			hit.amount *= stat("backstab_mult")


## Входящий урон по герою: сопротивления Даров (каменная кожа и т.п.).
func modify_incoming(amount: float, source: Node) -> float:
	amount *= stat("damage_taken_mult")
	if boons and boons.has_method("modify_incoming"):
		amount = boons.modify_incoming(amount, source)
	return maxf(0.0, amount)


# ================================================================ валюты
func add_dirhams(n: int) -> void:
	dirhams = maxi(0, dirhams + n)
	Bus.dirhams_changed.emit(dirhams)


func spend_dirhams(n: int) -> bool:
	if dirhams < n:
		return false
	add_dirhams(-n)
	return true


func add_ash(n: int) -> void:
	ash_run += n
	Meta.add_ash(n)
	Meta.save_game()


func set_hp(v: float) -> void:
	hp = clampf(v, 0.0, max_hp())
	Bus.hp_changed.emit(hp, max_hp())


func heal(n: float) -> void:
	if n <= 0.0:
		return
	set_hp(hp + n)


# ================================================================ поток забега
func start_run() -> void:
	active = true
	depth = 0
	biome = 0
	dirhams = 0
	ash_run = 0
	kills = 0
	rooms_cleared = 0
	boss_kills = 0
	weapon = Meta.equipped_weapon
	aspect = Meta.equipped_aspect
	kui = Meta.kui_prepared
	Meta.kui_prepared = ""
	rng.randomize()
	if boons and boons.has_method("reset"):
		boons.reset()
	revives_left = int(stat("revives"))
	hp = max_hp()
	Meta.stats["runs"] += 1
	Meta.save_game()
	var first: Dictionary = planner.first_room() if planner else {"type": "combat", "reward": "boon", "god": "tengri", "depth": 0, "biome": 0, "seed": rng.randi()}
	enter_room(first)


func enter_room(room: Dictionary) -> void:
	current_room = room
	depth = int(room.get("depth", depth))
	biome = int(room.get("biome", biome))
	_change_scene(ROOM_SCENE)


## Варианты дверей после зачистки текущей комнаты (обычно 2).
func door_choices() -> Array:
	if planner:
		return planner.make_choices(current_room, rng)
	return [{"type": "combat", "reward": "boon", "god": "tengri", "depth": depth + 1, "biome": biome, "seed": rng.randi()}]


func register_kill(enemy: Node) -> void:
	kills += 1
	Meta.stats["kills"] += 1


## Герой погиб. Возвращает true, если сработала Клятва Жизни (воскрешение), иначе заканчивает забег.
func on_player_death(killer := "") -> bool:
	if revives_left > 0:
		revives_left -= 1
		set_hp(max_hp() * 0.4)
		Bus.player_revived.emit(revives_left)
		return true
	end_run(true, killer)
	return false


func end_run(died: bool, killer := "", boss := "") -> void:
	Meta.last_run = {"died": died, "depth": depth, "biome": biome, "killer": killer, "boss": boss,
		"kills": kills, "ash": ash_run, "dirhams": dirhams}
	if died:
		Meta.stats["deaths"] += 1
	else:
		Meta.stats["victories"] += 1
	Meta.stats["best_depth"] = maxi(Meta.stats["best_depth"], depth)
	Meta.save_game()
	hub_reason = "death" if died else "victory"
	active = false
	dirhams = 0
	kui = ""
	if boons and boons.has_method("reset"):
		boons.reset()
	_change_scene(HUB_SCENE, 1.2 if died else 0.6)


func goto_hub() -> void:
	active = false
	_change_scene(HUB_SCENE)


func goto_title() -> void:
	active = false
	_change_scene(TITLE_SCENE)


# ================================================================ сцены
func spawn_player(parent: Node, pos: Vector3) -> Node3D:
	var p: Node3D = load(PLAYER_SCENE).instantiate()
	parent.add_child(p)
	p.global_position = pos
	return p


func spawn_hud(parent: Node) -> Node:
	var h: Node = load(HUD_SCENE).instantiate()
	parent.add_child(h)
	return h


func _change_scene(path: String, delay := 0.0) -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	if delay > 0.0:
		await get_tree().create_timer(delay, true, false, true).timeout
	get_tree().call_deferred("change_scene_to_file", path)


## Замедление времени (идеальное уклонение, добивание босса).
func slowmo(scale: float, real_seconds: float) -> void:
	if time_scale_lock:
		return
	time_scale_lock = true
	Engine.time_scale = scale
	await get_tree().create_timer(real_seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	time_scale_lock = false
