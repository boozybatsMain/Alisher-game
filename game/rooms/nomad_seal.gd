class_name NomadSeal
extends Interactable
## «Печать Номада» (модуль D): проклятый сундук, иногда появляется после зачистки комнаты с room["seal"] = true.
## Открыл → таймер 45 с (крупный на экране), враги непрерывно появляются (до 5 живых одновременно,
## всего TOTAL = 12 + depth/2). Испытание заканчивается, когда перебиты все TOTAL врагов или вышло время
## (оставшиеся враги рассыпаются в пепел — без награды за них).
##
## Награда (тем больше, чем больше убито и чем быстрее):
##   дирхемы = round((6 · убито + 4 · оставшиеся_секунды) · (1 + 0.05 · depth))
##   пепел   = max(3, round((убито / 2 + оставшиеся_секунды / 5) · (1 + 0.03 · depth)))
## Вид награды (дирхемы/пепел) выбирается при появлении сундука (35% — пепел) и написан над ним.
##
## API: NomadSeal.make(depth, biome, rng, arena) ; signal finished(kills: int, time_left: float, reward: Dictionary)
##      static reward_for(kills, time_left, depth, ash: bool) -> int

signal finished(kills: int, time_left: float, reward: Dictionary)

const DURATION := 45.0
const MAX_ALIVE := 5
const SPAWN_EVERY := 1.4

var depth := 0
var biome := 0
var arena: ArenaBuilder
var reward_ash := false
var total := 12
var active := false
var done := false
var time_left := DURATION
var kills := 0
var spawned_n := 0
var rng := RandomNumberGenerator.new()
var _mine := {}
var _spawn_t := 0.0
var _timer_ui: RoomUi.BigTimer
var _light: OmniLight3D
var _lid: Node3D
var _label: Label3D


static func make(p_depth: int, p_biome: int, p_rng: RandomNumberGenerator, p_arena: ArenaBuilder) -> NomadSeal:
	var s := NomadSeal.new()
	s.name = "NomadSeal"
	s.depth = p_depth
	s.biome = p_biome
	s.arena = p_arena
	s.rng.seed = p_rng.randi()
	s.reward_ash = s.rng.randf() < 0.35
	s.total = 12 + p_depth / 2
	return s


static func reward_for(p_kills: int, p_time_left: float, p_depth: int, ash: bool) -> int:
	if ash:
		return maxi(3, int(round((p_kills / 2.0 + p_time_left / 5.0) * (1.0 + 0.03 * p_depth))))
	return int(round((6.0 * p_kills + 4.0 * p_time_left) * (1.0 + 0.05 * p_depth)))


func _ready() -> void:
	radius = 1.9
	prompt = "Сорвать Печать Номада (испытание 45 с)"
	super._ready()
	_build()
	Bus.enemy_killed.connect(_on_killed)


func _build() -> void:
	var dark := RoomUtil.mat(Color(0.14, 0.1, 0.14), 0.8)
	var iron := RoomUtil.mat(Color(0.3, 0.28, 0.32), 0.4, Color.BLACK, 0.0, 0.7)
	var curse := Color(0.7, 0.3, 1.0)
	RoomUtil.mesh(self, RoomUtil.box_mesh(Vector3(1.5, 0.8, 1.0)), Vector3(0, 0.4, 0), dark)
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.8, -0.5)
	add_child(_lid)
	RoomUtil.mesh(_lid, RoomUtil.box_mesh(Vector3(1.55, 0.32, 1.05)), Vector3(0, 0.16, 0.5), dark)
	for sx: float in [-0.55, 0.0, 0.55]:
		RoomUtil.mesh(self, RoomUtil.box_mesh(Vector3(0.1, 0.84, 1.04)), Vector3(sx, 0.42, 0), iron, false)
	# цепи крест-накрест и печать
	for k in 2:
		var c := RoomUtil.mesh(self, RoomUtil.box_mesh(Vector3(1.9, 0.07, 0.07)), Vector3(0, 0.6, 0.53), iron, false)
		c.rotation.z = 0.45 if k == 0 else -0.45
	var seal := RoomUtil.mesh(self, RoomUtil.cyl_mesh(0.22, 0.22, 0.06, 12), Vector3(0, 0.6, 0.56), RoomUtil.glow_mat(curse, 3.0), false)
	seal.rotation.x = PI * 0.5
	_light = OmniLight3D.new()
	_light.light_color = curse
	_light.light_energy = 2.0
	_light.omni_range = 5.0
	_light.position = Vector3(0, 1.3, 0.4)
	add_child(_light)
	var what := "Пепел" if reward_ash else "Дирхемы"
	_label = RoomUtil.label3d("Печать Номада · %s" % what, curse.lerp(Color.WHITE, 0.3), 40, 0.006)
	_label.position = Vector3(0, 2.0, 0)
	add_child(_label)
	scale = Vector3.ONE * 0.01
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func can_activate(_p: Node) -> bool:
	return enabled and not active and not done


func activate(p: Node) -> void:
	if not can_activate(p):
		return
	activated.emit(p)
	begin()


func begin() -> void:
	active = true
	enabled = false
	time_left = DURATION
	Sfx.play("boss_roar", -4.0)
	Sfx.play("chest")
	Bus.shake.emit(0.7, 0.4)
	RoomUtil.toast("Печать сорвана! Перебей орду Мглы за 45 секунд", Color(0.8, 0.45, 1.0))
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", -1.9, 0.4).set_trans(Tween.TRANS_BACK)
	if is_inside_tree():
		Fx3D.burst(get_parent(), global_position + Vector3(0, 1, 0), Color(0.7, 0.3, 1.0), 24, 6.0)
		_timer_ui = RoomUi.BigTimer.new()
		get_parent().add_child(_timer_ui)
	_update_ui()
	_spawn_t = 0.3


func _process(delta: float) -> void:
	if not active:
		return
	time_left -= delta
	_spawn_t -= delta
	if _spawn_t <= 0.0 and spawned_n < total and _alive() < MAX_ALIVE:
		_spawn_t = SPAWN_EVERY
		_spawn()
		if spawned_n < total and _alive() < MAX_ALIVE - 2:
			_spawn()
	_update_ui()
	if kills >= total or time_left <= 0.0:
		_end()


func _alive() -> int:
	var n := 0
	for e in _mine.keys():
		if RoomUtil.is_alive(e):
			n += 1
	return n


func _spawn() -> void:
	var pos := Vector3.ZERO
	if arena:
		var pl := RoomUtil.player(get_tree())
		pos = arena.random_floor_point(rng, pl.global_position if pl else Vector3.INF, 5.0)
	var diff := RoomPlanner.difficulty(depth)
	var e := RoomUtil.spawn_enemy(RoomUtil.pick_enemy(biome, rng), get_parent(), pos + Vector3(0, 0.05, 0),
		{"elite": rng.randf() < 0.12, "hp_mult": float(diff["hp_mult"]) * 0.9, "dmg_mult": diff["dmg_mult"], "element": "erlik", "dirhams": 1})
	spawned_n += 1
	if e:
		_mine[e] = true


func _on_killed(enemy: Node, _hit: Hit) -> void:
	if active and _mine.has(enemy):
		kills += 1
		_mine.erase(enemy)


func _update_ui() -> void:
	if _timer_ui:
		_timer_ui.set_time(time_left)
		_timer_ui.set_info("Печать Номада: %d / %d" % [kills, total])


func _end() -> void:
	active = false
	done = true
	time_left = maxf(0.0, time_left)
	# остатки орды рассыпаются
	for e in _mine.keys():
		if RoomUtil.is_alive(e):
			if e.has_method("kill"):
				e.kill(null)
			else:
				e.queue_free()
	_mine.clear()
	var n := reward_for(kills, time_left, depth, reward_ash)
	var reward := {}
	if reward_ash:
		Run.add_ash(n)
		reward = {"ash": n}
		RoomUtil.toast("Печать снята: %d убито, +%d Пепла Тамыра" % [kills, n], RoomRewards.COLORS["ash"])
	else:
		Run.add_dirhams(n)
		reward = {"dirhams": n}
		RoomUtil.toast("Печать снята: %d убито, +%d дирхемов" % [kills, n], RoomUtil.GOLD)
	Sfx.play("wave_clear")
	if _timer_ui:
		_timer_ui.queue_free()
		_timer_ui = null
	if _light:
		create_tween().tween_property(_light, "light_energy", 0.0, 0.8)
	if _label:
		_label.text = "Печать снята"
	finished.emit(kills, time_left, reward)
