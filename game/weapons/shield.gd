extends WeaponBase
## Қалқан (щит): тяжёлый удар с отталкиванием (сбивает броню), удержание обычной > 0.25 с — блок спереди,
## особая — бросок щита рикошетом по цепочке до 4 целей и возврат.
## Аспекты: 0 — базовый; 1 — Абылай хан (блок отражает снаряды, затем удар ×2);
## 2 — Бөгенбай (после рикошетов щит 2.5 с крутится на месте жерновом);
## 3 — Ер Жәнібек (удар, принятый на блок, отвечает ударной волной вперёд).

const BLOCK_DELAY := 0.25
const MAX_BOUNCES := 4

var in_hand := true
var _wave_cd := 0.0
var thrown: WeaponProjectile = null
var counter_ready := false
var _blocking := false
var _bounces := 0
var _saw_t := 0.0
var _saw_tick := 0.0


func _init() -> void:
	id = "shield"
	base_damage = 16.0
	combo_window = 0.5


func _ready() -> void:
	super._ready()
	if not Bus.player_damaged.is_connected(_on_player_damaged):
		Bus.player_damaged.connect(_on_player_damaged)


func _pose_model() -> void:
	model.position = Vector3(0, 0, -0.35)
	model.rotation = Vector3.ZERO


func attack_pressed() -> void:
	super.attack_pressed()
	if not in_hand:
		if ready_to_attack():
			_punch()
		return
	if ready_to_attack():
		_bash()
	else:
		buffer("attack")


func attack_released() -> void:
	super.attack_released()
	_set_block(false)


func special_pressed() -> void:
	super.special_pressed()
	if after_wall_kick():
		air_special()
		return
	if not in_hand or special_cd > 0.0:
		return
	_set_block(false)
	if ready_to_attack():
		_throw()
	else:
		buffer("special")


func _buffered(kind: String) -> void:
	if kind == "attack" and in_hand:
		_bash()
	elif kind == "special" and in_hand and special_cd <= 0.0:
		_throw()


func _on_cancel() -> void:
	_blocking = false


# ---------------------------------------------------------------- удар и блок
func _bash() -> void:
	if try_move_attack():
		return
	var d := aim()
	set_recovery(0.55)
	slow_move(0.35, 0.3)
	player.lunge(d, 6.0, 0.1)
	anim("attack_heavy", 1.0)
	Sfx.play("swing_heavy")
	thrust(0.7, 0.12 / aspd())
	var h := make_hit(16.0)
	h.direction = d
	h.heavy = true
	h.armor_mult = 3.0
	h.stun = 0.4
	h.tags.append("shield_bash")
	if counter_ready:
		counter_ready = false
		h.amount *= 2.0
		h.tags.append("counter")
		WeaponFx.light_pop(self, feet(), glow, 3.0, 4.0, 0.25)
	schedule(0.08 / aspd(), func():
		strike_cone(origin(), d, 2.1, 110.0, h, 11.0, 1.5)
		WeaponFx.slash_arc(self, origin() - Vector3(0, 0.3, 0), d, 1.9, 110.0, glow, 0.16, 0.9)
		WeaponFx.ring(self, feet() + d * 1.2, 1.6, glow, 0.22))


## Рывок + обычная: таран щитом — герой проносится вперёд, враги на линии отлетают (удар о стену ×2).
func dash_attack() -> bool:
	if not in_hand:
		return false
	var d := aim()
	var start := origin()
	set_recovery(0.5)
	player.lunge(d, 16.0, 0.2)
	anim("attack_heavy", 1.2)
	Sfx.play("swing_heavy")
	thrust(0.9, 0.12)
	var h := make_hit(18.0)
	h.direction = d
	h.heavy = true
	h.armor_mult = 2.5
	h.stun = 0.5
	h.tags.append("shield_bash")
	h.tags.append("shield_ram")
	h.tags.append("dash_strike")
	h.tags.append("wall_x2")
	schedule(0.1, func():
		strike_line(start, start + d * 4.0, 0.9, h, 13.0, 1.0)
		WeaponFx.ring(self, feet() + d * 0.8, 1.8, glow, 0.22))
	return true


## Прыжок + обычная: удар щитом вниз — герой обрушивается, по приземлении бьёт по площади (сбивает броню).
func air_attack() -> bool:
	if not in_hand:
		return false
	set_recovery(0.5)
	busy = maxf(busy, 0.4)
	anim("attack_down", 1.3)
	Sfx.play("leap", -3.0)
	player.velocity = Vector3(player.velocity.x * 0.3, -16.0, player.velocity.z * 0.3)
	swing_to(-1.0, 0.0, 0.1)
	_shield_slam_wait(0.0)
	return true


func _shield_slam_wait(waited: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if waited < 0.5 and not player.is_on_floor():
		schedule(0.03, _shield_slam_wait.bind(waited + 0.03))
		return
	var pos := player.global_position
	var h := make_hit(16.0)
	h.heavy = true
	h.armor_mult = 3.0
	h.stun = 0.4
	h.tags.append("air_attack")
	h.tags.append("shield_slam")
	strike_radius(pos, 2.4, h, 6.0, 2.5)
	WeaponFx.ring(self, pos, 2.6, glow, 0.3)
	WeaponFx.flash(self, pos + Vector3(0, 0.3, 0), glow, 2.0, 0.2)
	Sfx.play("slam", -3.0)
	Bus.shake.emit(0.35, 0.18)


func _punch() -> void:
	var d := aim()
	set_recovery(0.3)
	anim("attack", 1.2)
	Sfx.play("swing", -4.0)
	var h := make_hit(6.0)
	h.tags.append("unarmed")
	h.armor_mult = 0.5
	strike_cone(origin(), d, 1.4, 90.0, h, 2.5)


func _set_block(on: bool) -> void:
	if on == _blocking:
		return
	_blocking = on
	if player:
		player.blocking = on
		if on:
			player.block_dir = aim()
	if on:
		Sfx.play("block", -8.0)
		anim("block", 1.0)


func _on_player_damaged(_amount: float, _source: Node) -> void:
	if _blocking and aspect == 1:
		counter_ready = true
	elif _blocking and aspect == 3 and _wave_cd <= 0.0 and player != null and is_inside_tree():
		_zhanibek_wave()


## Аспект Ер Жәнібека: принятый на блок удар отвечает ударной волной по фронту.
func _zhanibek_wave() -> void:
	_wave_cd = 0.6
	var d := aim()
	var h := make_hit(16.0, "special")
	h.tags.append("zhanibek_wave")
	h.armor_mult = 2.0
	h.stun = 0.4
	h.direction = d
	strike_cone(origin(), d, 3.6, 120.0, h, 8.0)
	WeaponFx.slash_arc(self, origin() - Vector3(0, 0.4, 0), d, 3.4, 120.0, glow, 0.2, 0.8)
	WeaponFx.ring(self, feet() + d * 1.2, 1.8, glow, 0.25)
	Sfx.play("swing_heavy", -2.0)
	Bus.shake.emit(0.15, 0.1)


# ---------------------------------------------------------------- бросок
func _throw() -> void:
	var d := aim()
	var first := _best_target(origin(), d, 10.0, 70.0, [])
	if first:
		var to := first.global_position - origin()
		to.y = 0.0
		if to.length() > 0.1:
			d = to.normalized()
	var h := make_hit(15.0, "special")
	h.tags.append("shield_throw")
	h.tags.append("projectile")
	h.armor_mult = 2.0
	h.stun = 0.2
	var vis := WeaponModel.build("shield", glow)
	vis.rotation = Vector3(-PI / 2, 0, 0)   # плашмя
	var holder := Node3D.new()
	holder.add_child(vis)
	var p := spawn_projectile(origin() + d * 0.5, d, 22.0, h, holder)
	if p == null:
		return
	p.pierce = -1
	p.stick = true
	p.radius = 0.6
	p.max_dist = 12.0
	p.knock_force = 5.0
	p.spin = 16.0
	p.lifetime = 8.0
	p.target_hit.connect(_on_shield_hit)
	p.finished.connect(_on_shield_finished)
	thrown = p
	in_hand = false
	_bounces = 0
	show_model(false)
	special_cd = 0.4
	set_recovery(0.3)
	anim("special", 1.2)
	Sfx.play("swing_heavy")


func _best_target(from: Vector3, dir: Vector3, dist: float, cone: float, exclude: Array) -> Node3D:
	var best: Node3D = null
	var bd := dist
	for t in Combat.in_cone(get_tree(), from, dir, dist, cone):
		if t in exclude or t == player or (t.has_method("is_dead") and t.is_dead()):
			continue
		var dd: float = from.distance_to((t as Node3D).global_position)
		if dd < bd:
			bd = dd
			best = t
	return best


func _on_shield_hit(p: WeaponProjectile, _target: Node) -> void:
	if p.return_to != null:
		return
	_bounces += 1
	Sfx.play("block", -4.0, 0.2)
	if _bounces < MAX_BOUNCES:
		var next := Combat.nearest(get_tree(), p.global_position, 8.0, "hurtable_enemy", p.hit_set.keys() + [player])
		if next:
			var to := next.global_position - p.global_position
			to.y = 0.0
			if to.length() > 0.05:
				p.dir = to.normalized()
				p.traveled = 0.0
				p.max_dist = 9.0
				return
	_end_bounces(p)


func _end_bounces(p: WeaponProjectile) -> void:
	if aspect == 2 and _saw_t <= 0.0:
		p.stuck = true
		_saw_t = 2.5
		_saw_tick = 0.0
		Sfx.play("wind_wall", -4.0)
		return
	_return_shield(p)


func _return_shield(p: WeaponProjectile) -> void:
	_saw_t = 0.0
	var h := make_hit(8.0, "special")
	h.tags.append("shield_return")
	h.tags.append("projectile")
	p.hit_proto = h
	p.recall(player, 26.0)


func _on_shield_finished(p: WeaponProjectile, reason: String) -> void:
	if p != thrown:
		return
	if reason == "wall" or reason == "range":
		Sfx.play("block", -6.0)
		_end_bounces(p)
		return
	_catch()


func _catch() -> void:
	in_hand = true
	thrown = null
	_saw_t = 0.0
	show_model(true)
	Sfx.play("block", -6.0)


func _tick(delta: float) -> void:
	_wave_cd = maxf(0.0, _wave_cd - delta)
	if not in_hand and (thrown == null or not is_instance_valid(thrown)):
		_catch()
	# блок: удержание обычной атаки
	if in_hand and attack_held and hold_time > BLOCK_DELAY and recovery <= 0.1:
		_set_block(true)
	elif _blocking and (not attack_held or not in_hand):
		_set_block(false)
	if _blocking:
		slow_move(0.4, 0.1)
		player.block_dir = aim()
		swing_yaw = lerpf(swing_yaw, 0.0, 0.3)
		if aspect == 1:
			if reflect_projectiles(origin(), 2.2, aim(), 140.0) > 0:
				counter_ready = true
	# жернов Бөгенбая
	if _saw_t > 0.0 and thrown and is_instance_valid(thrown):
		_saw_t -= delta
		_saw_tick -= delta
		if thrown.visual:
			thrown.visual.rotate_y(22.0 * delta)
		if _saw_tick <= 0.0:
			_saw_tick = 0.25
			var h := make_hit(5.0, "special")
			h.tags.append("shield_saw")
			h.armor_mult = 1.0
			strike_radius(thrown.global_position, 1.7, h, 1.5)
			WeaponFx.slash_arc(self, thrown.global_position - Vector3(0, 0.3, 0), Vector3.FORWARD, 1.6, 360.0, glow, 0.2, 0.4)
		if _saw_t <= 0.0:
			_return_shield(thrown)


func _exit_tree() -> void:
	if thrown and is_instance_valid(thrown):
		thrown.queue_free()
	if player and is_instance_valid(player):
		player.blocking = false
