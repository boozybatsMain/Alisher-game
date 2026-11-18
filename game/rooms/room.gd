extends Node3D
## Комната забега (модуль D). Читает Run.current_room ({type, reward, god, god2, depth, biome, seed, seal}),
## строит арену (ArenaBuilder), спавнит героя, камеру (GameCamera или запасную), HUD, музыку, шлёт Bus.room_entered.
## Типы: combat/elite — волны (WaveDirector) → награда → двери; boss — босс биома, полоса босса, пепел + Забытая нота,
## после финального босса — победа (Run.end_run); merchant — Лавка Караванщика + Колодец Обмена; duel — «Спор Духов»;
## rest — родник. Флаг seal — после зачистки иногда появляется проклятый сундук «Печать Номада».
## Флаг secret (combat/elite) — у кромки треснувшая плита (ArenaBreakable "secret_wall"); разбил — открывается дверь
## в тайную комнату secret (акробатическая полоса без врагов, награда — Забытая нота; глубина та же).
##
## Сверх контракта (для тестов/отладки): room, arena, waves, doors, state ("fight"/"reward"/"open"/"victory"),
##   reward_node, boss, seal_node, totems; debug_clear() — убить всех врагов; open_doors(); take_reward_now().

const BOSS_DIALOGUE := [
	[{"speaker": "Кайсар", "text": "Жезтырнақ пала... но её когти пахли не степью — Мглой."},
		{"speaker": "Голос корней", "text": "Глубже, хранитель. Корни Байтерека стонут от скверны."}],
	[{"speaker": "Кайсар", "text": "Чугунное Ухо слышало зов из-под корней. Кто-то позвал Кара-Тұман по имени..."},
		{"speaker": "Голос корней", "text": "Тот, кто позвал, носил золотой пояс хана. Иди в Чертог Ерлика."}],
	[{"speaker": "Первый хан", "text": "Я хотел лишь вечности для рода... и открыл ей дверь."},
		{"speaker": "Кайсар", "text": "Тогда я закрою её. Огонь рода не погаснет."}],
]
const SEAL_APPEAR_CHANCE := 0.65

var room: Dictionary = {}
var arena: ArenaBuilder
var player: Node3D
var camera: Camera3D
var hud: Node
var waves: WaveDirector
var doors: Array = []
var choices: Array = []
var state := "intro"
var reward_node: Node3D = null
var boss: Node3D = null
var boss_id := ""
var seal_node: NomadSeal = null
var totems: Array = []
var rng := RandomNumberGenerator.new()
var seal_chance := SEAL_APPEAR_CHANCE   ## шанс появления Печати Номада при room.seal (тесты ставят 1.0)
var _reward_taken := false
var _boss_bar: CanvasLayer = null
var _duel_rejected := ""
var _duel_phase := 0
var _victory := false


func _ready() -> void:
	room = Run.current_room.duplicate(true)
	if room.is_empty():
		room = Run.planner.first_room() if Run.planner else {"type": "combat", "reward": "boon", "god": "tengri", "depth": 0, "biome": 0, "seed": 1}
		Run.current_room = room
	_normalize()
	Run.depth = int(room["depth"])     # HUD и враги читают Run.depth/biome — синхронизируем с комнатой
	Run.biome = int(room["biome"])
	if not Run.active:
		Run.active = true
		if Run.hp <= 0.0:
			Run.hp = Run.max_hp()
	rng.seed = int(room["seed"])
	var layout := ArenaLayouts.for_room(room)
	arena = ArenaBuilder.create(self, layout, int(room["biome"]), int(room["seed"]))
	player = Run.spawn_player(self, arena.spawn_player)
	_setup_camera()
	hud = Run.spawn_hud(self)
	_music()
	waves = WaveDirector.new()
	waves.name = "Waves"
	waves.rng.seed = int(room["seed"]) + 11
	add_child(waves)
	waves.finished.connect(_on_waves_finished)
	_make_doors()
	if bool(room.get("secret", false)) and String(room["type"]) in ["combat", "elite"]:
		_setup_secret_wall()
	Bus.room_entered.emit(room)
	_intro_toast()
	match String(room["type"]):
		"boss":
			_start_boss()
		"merchant":
			RoomMerchant.create(self, arena, int(room["depth"]), rng)
			state = "open"
			open_doors()
		"rest":
			_spawn_reward("spring")
			state = "open"
			open_doors()
		"duel":
			_start_duel()
		"secret":
			_start_secret()
		_:
			state = "fight"
			waves.start(WaveDirector.plan(room, rng), arena, self, 1 if int(room["depth"]) < 6 else 2)


func _normalize() -> void:
	var defaults := {"type": "combat", "reward": "boon", "god": "tengri", "god2": "", "depth": Run.depth, "biome": Run.biome,
		"seed": randi(), "seal": false}
	for k in defaults:
		if not room.has(k):
			room[k] = defaults[k]
	if String(room["reward"]) == "boon" and String(room["god"]) == "":
		room["god"] = "tengri"
	if String(room["type"]) == "duel" and (String(room["god2"]) == "" or room["god2"] == room["god"]):
		for g in RoomUtil.GODS:
			if g != room["god"]:
				room["god2"] = g
				break
	var diff := RoomPlanner.difficulty(int(room["depth"]))
	if not room.has("hp_mult"):
		room["hp_mult"] = diff["hp_mult"]
	if not room.has("dmg_mult"):
		room["dmg_mult"] = diff["dmg_mult"]


# ================================================================ камера, музыка
func _setup_camera() -> void:
	var gc: Variant = RoomUtil.script_of(RoomUtil.GAME_CAMERA)
	if gc and gc.has_method("attach"):
		var c: Variant = gc.attach(self, player)
		if c is Camera3D:
			camera = c
			if camera.has_method("set_bounds"):
				camera.call("set_bounds", AABB(arena.bounds.position + Vector3(3, 0, 3), arena.bounds.size - Vector3(6, 0, 4)))
			if "floor_y" in camera:
				camera.set("floor_y", 0.0)
			return
	var fc := FallbackCamera.new()
	fc.target = player
	add_child(fc)
	fc.make_current()
	camera = fc


func _music() -> void:
	match String(room["type"]):
		"boss": Sfx.music("boss")
		"merchant", "rest", "secret": Sfx.music("calm")
		_: Sfx.music("battle_day" if int(room["biome"]) == 0 else "battle_night")


func _intro_toast() -> void:
	var biome_name := String(RoomUtil.BIOME_NAMES[clampi(int(room["biome"]), 0, 2)])
	var t := String(room["type"])
	var col := Color(1, 0.9, 0.75)
	var text := "%s · комната %d" % [biome_name, int(room["depth"]) + 1]
	match t:
		"merchant":
			text = "Лавка Караванщика"
			col = RoomRewards.COLORS["merchant"]
		"duel":
			text = "Спор Духов: %s против %s" % [RoomUtil.god_name(room["god"]), RoomUtil.god_name(room["god2"])]
			col = RoomUtil.god_color(room["god"])
		"rest":
			text = "Привал у родника"
			col = RoomRewards.COLORS["rest"]
		"secret":
			text = "Тайник предков"
			col = RoomRewards.COLORS["kui"]
		"elite":
			text += " · Элита Мглы"
			col = Color(1, 0.6, 0.4)
	RoomUtil.toast(text, col)


# ================================================================ двери
func _make_doors() -> void:
	choices = Run.door_choices() if Run.planner else []
	if String(room["type"]) == "boss" and int(room["biome"]) >= 2:
		choices = []   # финальный босс — дальше только победа
	var slots := arena.door_slots
	for i in mini(choices.size(), slots.size()):
		var d := RoomDoor.new()
		d.name = "Door%d" % i
		d.biome = int(room["biome"])
		d.setup(choices[i])
		add_child(d)
		d.global_position = slots[i]
		doors.append(d)


func open_doors() -> void:
	if state == "victory":
		return
	if seal_node and seal_node.active:
		return
	for d in doors:
		if is_instance_valid(d):
			d.unlock()
	if not doors.is_empty() and state != "open":
		RoomUtil.toast("Путь открыт", Color(1, 0.85, 0.55))
	state = "open"


# ================================================================ тайный ход и тайная комната
var secret_wall: ArenaBreakable = null
var secret_door: RoomDoor = null


func _setup_secret_wall() -> void:
	var srng := RandomNumberGenerator.new()
	srng.seed = int(room["seed"]) + 101
	secret_wall = arena.add_secret_wall(srng)
	if secret_wall:
		secret_wall.broken.connect(_on_secret_wall_broken)


func _on_secret_wall_broken(b: ArenaBreakable) -> void:
	if state == "victory" or secret_door != null:
		return
	var srng := RandomNumberGenerator.new()
	srng.seed = int(room["seed"]) + 202
	var sr := RoomPlanner.secret_room(room, srng)
	var d := RoomDoor.new()
	d.name = "SecretDoor"
	d.biome = int(room["biome"])
	d.setup(sr)
	add_child(d)
	d.global_position = arena.to_global(b.get_meta("door_pos", b.position))
	d.rotation.y = float(b.get_meta("door_rot", 0.0))
	secret_door = d
	doors.append(d)
	RoomUtil.toast("Тайный ход! За стеной звучит забытая нота…", RoomRewards.COLORS["kui"])
	if state == "open" and not (seal_node and seal_node.active):
		d.unlock()


## Тайная комната: врагов нет, нота лежит в конце акробатической полосы; двери — после того как её забрали.
func _start_secret() -> void:
	state = "reward"
	_spawn_reward(String(room["reward"]))
	Sfx.music("calm")
	RoomUtil.toast("Тайник предков: доберись до ноты", RoomRewards.COLORS["kui"])


# ================================================================ бой → награда
func _on_waves_finished() -> void:
	if String(room["type"]) == "duel":
		_duel_wave_done()
		return
	if String(room["type"]) == "boss":
		return
	_room_cleared()
	if String(room["type"]) == "elite":
		var bonus := 20 + int(room["depth"]) * 2
		Run.add_dirhams(bonus)
		RoomUtil.toast("Элита повержена: +%d дирхемов" % bonus, RoomUtil.GOLD)
	_spawn_reward(String(room["reward"]))
	if bool(room.get("seal", false)) and rng.randf() < seal_chance:
		_spawn_seal()


func _room_cleared() -> void:
	state = "reward"
	Run.rooms_cleared += 1
	Bus.room_cleared.emit()
	Sfx.play("wave_clear")
	RoomUtil.toast("Комната очищена", Color(0.95, 0.85, 0.55))
	Sfx.music("calm", 2.0)


func _spawn_reward(kind: String) -> void:
	var pos := arena.reward_point
	var depth := int(room["depth"])
	var elite_k := 1.5 if String(room["type"]) == "elite" else 1.0
	var node: Node3D = null
	match kind:
		"boon":
			node = _make_totem(String(room["god"]))
		"ash":
			node = RewardPickup.make("ash", int(RoomRewards.ash_amount(depth) * elite_k))
		"gold":
			node = RewardPickup.make("gold", int(RoomRewards.gold_amount(depth, rng) * elite_k))
		"upgrade", "heal", "kui", "spring":
			node = RewardPickup.make(kind)
		_:
			node = RewardPickup.make("gold", RoomRewards.gold_amount(depth, rng))
	add_child(node)
	node.global_position = pos
	reward_node = node
	_reward_taken = false
	if node.has_signal("taken"):
		node.connect("taken", _on_reward_taken.unbind(_taken_argc(node)))
	Fx3D.flash_light(self, pos + Vector3(0, 2, 0), Color(1, 0.9, 0.7), 4.0, 6.0, 0.4)


## Тотем духа: сцена модуля B (spirit_totem.tscn, export god) или запасной RewardPickup "boon".
func _make_totem(god: String) -> Node3D:
	if ResourceLoader.exists(RoomUtil.SPIRIT_TOTEM):
		var ps: Variant = load(RoomUtil.SPIRIT_TOTEM)
		if ps is PackedScene:
			var t: Node = (ps as PackedScene).instantiate()
			if t is Node3D:
				t.set("god", god)
				return t
			t.free()
	return RewardPickup.make("boon", 0, god)


## Сколько аргументов у сигнала taken у узла (SpiritTotem: 1, RewardPickup: 2) — чтобы отбросить их.
func _taken_argc(n: Node) -> int:
	for s in n.get_signal_list():
		if String(s["name"]) == "taken":
			return (s["args"] as Array).size()
	return 0


func _on_reward_taken() -> void:
	if _reward_taken:
		return
	_reward_taken = true
	if String(room["type"]) == "boss" and _victory:
		return
	open_doors()


## Немедленно забрать награду (тесты/отладка).
func take_reward_now() -> void:
	if reward_node and is_instance_valid(reward_node):
		if reward_node is RewardPickup:
			(reward_node as RewardPickup)._finish((reward_node as RewardPickup).apply())
		else:
			_on_reward_taken()


func _spawn_seal() -> void:
	seal_node = NomadSeal.make(int(room["depth"]), int(room["biome"]), rng, arena)
	add_child(seal_node)
	var p := arena.reward_point + Vector3(3.5, 0, 1.5)
	if arena.height_at(p.x, p.z) == -INF or arena.is_pit(p.x, p.z, 1.0):
		p = arena.random_floor_point(rng, arena.reward_point, 2.5)
	else:
		p.y = arena.height_at(p.x, p.z)
	seal_node.global_position = p
	seal_node.activated.connect(func(_p: Node): _lock_for_seal())
	seal_node.finished.connect(func(_k: int, _t: float, _r: Dictionary):
		if _reward_taken:
			open_doors())
	Sfx.play("alert", -6.0)
	RoomUtil.toast("Появилась Печать Номада…", Color(0.75, 0.4, 1.0))


func _lock_for_seal() -> void:
	for d in doors:
		if is_instance_valid(d):
			d.lock()
	state = "seal"


# ================================================================ босс
func _start_boss() -> void:
	state = "fight"
	boss_id = RoomUtil.boss_for(int(room["biome"]))
	var mods := {"hp_mult": 1.0, "dmg_mult": 1.0}
	var bid := boss_id
	if bid == "":
		bid = "balbal"
		mods = {"elite": true, "hp_mult": 6.0, "dmg_mult": 1.5}
		boss_id = "balbal"
	var pos: Vector3 = arena.extra_points.get("boss", Vector3(0, 0, -5))
	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree():
		return
	Sfx.play("boss_roar")
	Bus.shake.emit(0.8, 0.6)
	RoomUtil.toast(RoomUtil.enemy_name(bid), RoomRewards.COLORS["boss"])
	boss = RoomUtil.spawn_enemy(bid, self, pos, mods)
	if boss == null:
		_boss_defeated()
		return
	# BossBase (модуль C) рисует свою полосу при активации (own_bar) — вторую не создаём.
	if not bool(boss.get("own_bar")) and get_tree().get_first_node_in_group("boss_bar") == null:
		var bb := RoomUi.BossBar.new()
		add_child(bb)
		bb.set_target(boss)
		_boss_bar = bb


func _process(_delta: float) -> void:
	if String(room.get("type", "")) == "boss" and state == "fight" and boss != null:
		if not RoomUtil.is_alive(boss):
			_boss_defeated()


func _boss_defeated() -> void:
	if state != "fight":
		return
	state = "reward"
	boss = null
	waves.kill_all()
	for e in get_tree().get_nodes_in_group("enemies"):
		if RoomUtil.is_alive(e) and e.has_method("kill"):
			e.kill(null)
	Run.boss_kills += 1
	if boss_id != "" and not (boss_id in Run.bosses_killed):
		Run.bosses_killed.append(boss_id)
	Meta.stats["boss_kills"] = int(Meta.stats.get("boss_kills", 0)) + 1
	Meta.save_game()
	Run.rooms_cleared += 1
	Bus.room_cleared.emit()
	Sfx.play("wave_clear")
	Run.slowmo(0.3, 0.8)
	var biome := int(room["biome"])
	var ash := 50 + 25 * biome
	Bus.dialogue_requested.emit(BOSS_DIALOGUE[clampi(biome, 0, 2)])
	if _boss_bar:
		var bb := _boss_bar
		_boss_bar = null
		get_tree().create_timer(1.5).timeout.connect(bb.queue_free)
	if biome >= 2:
		_final_victory(ash)
		return
	RoomUtil.toast("Владыка повержен!", RoomRewards.COLORS["boss"])
	Sfx.music("calm", 2.0)
	_spawn_reward_custom(RewardPickup.make("ash_boss", ash), arena.reward_point + Vector3(-2.0, 0, 0), true)
	_spawn_reward_custom(RewardPickup.make("kui"), arena.reward_point + Vector3(2.0, 0, 0), false)


func _spawn_reward_custom(node: RewardPickup, pos: Vector3, main: bool) -> void:
	add_child(node)
	node.global_position = Vector3(pos.x, maxf(0.0, arena.height_at(pos.x, pos.z)), pos.z)
	if main:
		reward_node = node
		node.taken.connect(func(_k: String, _i: Dictionary): _on_reward_taken())


func _final_victory(ash: int) -> void:
	_victory = true
	state = "victory"
	Run.victory_pending = true
	Run.add_ash(ash)
	RewardPickup.unlock_random_kui()
	Sfx.music("victory", 1.0)
	RoomUtil.toast("Победа! Мгла отступает от Байтерека (+%d Пепла)" % ash, Color(1, 0.85, 0.4))
	# Таймер победы стоит на паузе (PAUSABLE) и стартует только после того, как финальный диалог дочитан,
	# иначе Run.end_run оборвал бы сюжетную сцену.
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = 3.0
	t.process_mode = Node.PROCESS_MODE_PAUSABLE
	t.ignore_time_scale = true
	add_child(t)
	t.timeout.connect(func():
		if Run.active:
			Run.end_run(false, "", boss_id))
	if DialogueBox.is_open():
		DialogueBox.ensure(get_tree()).closed.connect(_start_victory_timer.bind(t), CONNECT_ONE_SHOT)
	else:
		t.start()


func _start_victory_timer(t: Timer) -> void:
	if is_instance_valid(t) and t.is_inside_tree():
		t.start()


# ================================================================ «Спор Духов»
func _start_duel() -> void:
	state = "reward"
	_duel_phase = 0
	var g1 := String(room["god"])
	var g2 := String(room["god2"])
	for i in 2:
		var t := _make_totem(g1 if i == 0 else g2)
		add_child(t)
		var off := Vector3(-3.2 if i == 0 else 3.2, 0, 0)
		var p := arena.reward_point + off
		t.global_position = Vector3(p.x, maxf(0.0, arena.height_at(p.x, p.z)), p.z)
		totems.append(t)
		if t.has_signal("taken"):
			t.connect("taken", _on_duel_taken.bind(i).unbind(_taken_argc(t)))
	# огни на полу между тотемами — «спор»
	Fx3D.ring(self, arena.reward_point, 3.5, RoomUtil.god_color(g1).lerp(RoomUtil.god_color(g2), 0.5), 1.0, 0.3)


func _on_duel_taken(i: int) -> void:
	if _duel_phase == 0:
		_duel_phase = 1
		var other: Node3D = totems[1 - i]
		_duel_rejected = String(room["god2"] if i == 0 else room["god"])
		_set_totem_lit(other, false)
		other.set("enabled", false)
		var gname := RoomUtil.god_name(_duel_rejected)
		RoomUtil.toast("Гнев духа %s!" % gname, RoomUtil.god_color(_duel_rejected))
		Sfx.play("thunder")
		Bus.shake.emit(0.6, 0.5)
		state = "fight"
		Sfx.music("battle_day" if int(room["biome"]) == 0 else "battle_night")
		var plan := WaveDirector.plan({"type": "combat", "depth": int(room["depth"]) + 1, "biome": int(room["biome"]),
			"hp_mult": float(room["hp_mult"]) * 1.4, "dmg_mult": float(room["dmg_mult"]) * 1.15}, rng)
		plan = plan.slice(0, 2)
		for w in plan:
			for e in w:
				e["mods"]["element"] = _duel_rejected
				e["mods"]["hp_mult"] = float(room["hp_mult"]) * 1.4
		waves.start(plan, arena, self, 1)
	elif _duel_phase == 2:
		_duel_phase = 3
		_reward_taken = true
		open_doors()


func _duel_wave_done() -> void:
	_duel_phase = 2
	_room_cleared()
	var other: Node3D = null
	for t in totems:
		if is_instance_valid(t) and not bool(t.get("used")):
			other = t
	if other:
		_set_totem_lit(other, true)
		other.set("enabled", true)
		RoomUtil.toast("Дух %s смирился — его дар ждёт тебя" % RoomUtil.god_name(_duel_rejected), RoomUtil.god_color(_duel_rejected))
	else:
		open_doors()


func _set_totem_lit(t: Node, on: bool) -> void:
	for n in t.find_children("*", "", true, false):
		if n is Light3D:
			(n as Light3D).visible = on
		elif n is Label3D:
			(n as Label3D).modulate.a = 1.0 if on else 0.35
		elif n is Sprite3D:
			(n as Sprite3D).visible = on


# ================================================================ отладка
## Убить всех врагов (для тестов/отладки): волны завершатся естественным путём.
func debug_clear() -> void:
	waves.kill_all()
	for e in get_tree().get_nodes_in_group("enemies"):
		if RoomUtil.is_alive(e) and e.has_method("kill"):
			e.kill(null)
	if boss and boss.has_method("kill"):
		boss.kill(null)


# ================================================================ запасная камера
class FallbackCamera extends Camera3D:
	var target: Node3D
	var dist := 18.5

	func _init() -> void:
		fov = 32.0
		far = 220.0
		rotation_degrees = Vector3(-40, 45, 0)

	func _process(delta: float) -> void:
		if target == null or not is_instance_valid(target):
			return
		var goal := target.global_position + Vector3(0, 0.9, 0) + global_transform.basis.z * (dist + maxf(0.0, target.global_position.y) * 1.1)
		global_position = global_position.lerp(goal, 1.0 - exp(-6.0 * delta))
