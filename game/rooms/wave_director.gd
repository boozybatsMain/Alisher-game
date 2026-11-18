class_name WaveDirector
extends Node
## Волны врагов комнаты (модуль D). План волн — данными: [[{type, mods}], ...].
## Следующая волна стартует, когда живых врагов текущей волны ≤ threshold (1–2) или все мертвы.
## Враги появляются по одному с интервалом в точках арены подальше от героя (на разных ярусах).
## Сигналы: wave_started(index, total), finished. Также шлёт Bus.wave_started.
##
## API: WaveDirector.plan(room, rng) -> Array (static, состав волн по типу/глубине/биому)
##      start(waves, arena, parent), alive() -> Array, kill_all(), is_finished()

signal wave_started(index: int, total: int)
signal finished

const SPAWN_GAP := 0.28
const MIN_PLAYER_DIST := 6.0

var waves: Array = []
var arena: ArenaBuilder
var spawn_parent: Node
var current := -1
var threshold := 1
var spawned: Array = []            ## все созданные враги
var _wave_nodes: Array = []        ## враги текущей волны
var _queue: Array = []             ## ожидают появления
var _spawn_t := 0.0
var _finished := false
var _running := false
var _next_delay := 0.0
var rng := RandomNumberGenerator.new()


## Состав волн для комнаты. combat: 2–3 волны по 4–10; elite: меньше врагов, больше элиток.
static func plan(room: Dictionary, rng: RandomNumberGenerator) -> Array:
	var depth := int(room.get("depth", 0))
	var biome := int(room.get("biome", 0))
	var t := String(room.get("type", "combat"))
	var hp_mult := float(room.get("hp_mult", RoomPlanner.difficulty(depth)["hp_mult"]))
	var dmg_mult := float(room.get("dmg_mult", RoomPlanner.difficulty(depth)["dmg_mult"]))
	var n_waves := 2 if depth < 4 else 3
	if depth == 0:
		n_waves = 2
	var base := clampi(4 + depth / 2, 4, 10)
	var elite_chance := clampf((depth - 2) * 0.05, 0.0, 0.35)
	if t == "elite":
		base = clampi(int(round(base * 0.65)), 3, 7)
		elite_chance = 0.5
	var out := []
	for w in n_waves:
		var count := clampi(base + w + rng.randi_range(-1, 1), 4 if t != "elite" else 3, 10)
		var wave := []
		var elites := 0
		for i in count:
			var id := RoomUtil.pick_enemy(biome, rng)
			var elite := rng.randf() < elite_chance
			if t == "elite" and i == 0 and w > 0:
				elite = true   # минимум одна элитка во 2+ волне
			if elite:
				elites += 1
			wave.append({"type": id, "mods": {"elite": elite, "hp_mult": hp_mult, "dmg_mult": dmg_mult}})
		out.append(wave)
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	rng.randomize()


func start(p_waves: Array, p_arena: ArenaBuilder, p_parent: Node, p_threshold := 1) -> void:
	waves = p_waves
	arena = p_arena
	spawn_parent = p_parent
	threshold = p_threshold
	current = -1
	_finished = false
	_running = true
	_next_delay = 0.8
	if waves.is_empty():
		_finish()


func is_finished() -> bool:
	return _finished


func alive() -> Array:
	var out := []
	for e in spawned:
		if RoomUtil.is_alive(e):
			out.append(e)
	return out


func _alive_in_wave() -> int:
	var n := 0
	for e in _wave_nodes:
		if RoomUtil.is_alive(e):
			n += 1
	return n


func _process(delta: float) -> void:
	if not _running or _finished:
		return
	# появление очереди
	if not _queue.is_empty():
		_spawn_t -= delta
		if _spawn_t <= 0.0:
			_spawn_t = SPAWN_GAP
			_spawn_one(_queue.pop_front())
		return
	if _next_delay > 0.0:
		_next_delay -= delta
		return
	var alive_n := _alive_in_wave()
	var last := current >= waves.size() - 1
	if current < 0 or (not last and alive_n <= threshold):
		_start_wave(current + 1)
	elif last and alive().is_empty() and group_alive(get_tree()) == 0:
		_finish()


func _start_wave(i: int) -> void:
	current = i
	_wave_nodes.clear()
	_queue = (waves[i] as Array).duplicate()
	_spawn_t = 0.0
	_next_delay = 1.0
	Sfx.play("wave_start", -3.0)
	Bus.wave_started.emit(i + 1, waves.size())
	wave_started.emit(i + 1, waves.size())


func _spawn_one(e: Dictionary) -> void:
	var pos := pick_spawn_point(String(e.get("type", "")))
	var mods: Dictionary = (e.get("mods", {}) as Dictionary).duplicate()
	var n := RoomUtil.spawn_enemy(String(e.get("type", "wolf")), spawn_parent, pos, mods)
	if n:
		spawned.append(n)
		_wave_nodes.append(n)


## Точка спавна подальше от героя; лучники и духи чаще на ярусах.
func pick_spawn_point(type_id := "") -> Vector3:
	if arena == null or arena.spawn_points.is_empty():
		return Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 2))
	var pl := RoomUtil.player(get_tree())
	var pp := pl.global_position if pl else arena.spawn_player
	var prefer_high := type_id in ["archer", "shaman", "spirit"] and rng.randf() < 0.6
	var cands := []
	for p in arena.spawn_points:
		if Vector2(p.x - pp.x, p.z - pp.z).length() < MIN_PLAYER_DIST:
			continue
		if prefer_high and p.y < 1.0:
			continue
		cands.append(p)
	if cands.is_empty():
		for p in arena.spawn_points:
			if Vector2(p.x - pp.x, p.z - pp.z).length() >= MIN_PLAYER_DIST * 0.6:
				cands.append(p)
	if cands.is_empty():
		cands = arena.spawn_points.duplicate()
	var p: Vector3 = cands[rng.randi_range(0, cands.size() - 1)]
	return p + Vector3(rng.randf_range(-0.6, 0.6), 0.05, rng.randf_range(-0.6, 0.6))


## Живые враги в группе "enemies" (включая призванных боссом/шаманом).
static func group_alive(tree: SceneTree) -> int:
	var n := 0
	for e in tree.get_nodes_in_group("enemies"):
		if RoomUtil.is_alive(e):
			n += 1
	return n


func kill_all() -> void:
	_queue.clear()
	for e in alive():
		if e.has_method("kill"):
			e.kill(null)
		else:
			e.queue_free()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_running = false
	finished.emit()
