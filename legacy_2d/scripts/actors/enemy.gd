extends Node2D
## Враг по данным из scripts/data/enemy_db.gd.
## Поведение (ai): melee — идёт к герою и бьёт; ranged — держит дистанцию и стреляет; caster — колдует,
## телепортируется и призывает; boss — как melee, но с фазой ярости, призывом и «пошатыванием» от урона.

signal died(enemy: Node)
signal summon_requested(kind: String, x: float)

const DB := preload("res://scripts/data/enemy_db.gd")
const FX := preload("res://scripts/fx/effects.gd")
const FLASH := preload("res://shaders/flash.gdshader")
const PROJECTILE := preload("res://scripts/actors/projectile.gd")
const ASYK := preload("res://scripts/world/asyk.gd")
const SHADOW := preload("res://assets/fx/shadow.png")
const ALERT := preload("res://assets/fx/alert.png")
## Сколько секунд минимум горит «!» до удара — время поднять щит.
const REACT := 0.42
const REACT_ENRAGED := 0.34
const REACT_REPEAT := 0.3

enum S { SPAWN, IDLE, MOVE, ATTACK, RECOVER, HURT, STUN, TELEPORT, DEAD }

var kind := ""
var def: Dictionary
var hp := 100.0
var max_hp := 100.0
var dmg_mult := 1.0
var radius := 60.0
var hover := 0.0
var is_boss := false
var state := S.SPAWN
var st := 0.0
var face := -1
var vx := 0.0
var kb := 0.0
var flash := 0.0
var tele := 0.0          # красный оттенок замаха (отдельно от белой вспышки попадания)
var poise_acc := 0.0
var stun_time := 1.0
var burn_dps := 0.0
var burn_time := 0.0
var burn_tick := 0.0
var cooldowns := []
var global_cd := 0.6
var attack: Dictionary = {}
var combo_left := 0
var leaping := false
var leap_from := 0.0
var leap_to := 0.0
var leap_t := 0.0
var leap_dur := 0.3
var leap_h := 100.0
var dashing := false
var dash_done := false
var proj_left := 0
var proj_t := 0.0
var summon_t := 0.0
var teleport_cd := 2.0
var enraged := false
var bounds := Vector2(-100000.0, 100000.0)
var ground_y := 0.0
var player: Node
var summoned_by: Node = null

var body: Node2D
var sprite: AnimatedSprite2D
var shadow: Sprite2D
var mat: ShaderMaterial
var alert: Sprite2D
var alert_frame := -1     # кадр первого удара: на нём «!» гаснет
var windup_t := 0.0       # удержание позы замаха, если анимация слишком быстрая для реакции
var burn_fx: CPUParticles2D
var _last_event := ""


func setup(p_kind: String, hp_mult: float, p_dmg_mult: float, p_bounds: Vector2, p_ground: float) -> void:
	kind = p_kind
	def = DB.DB[kind]
	max_hp = def["hp"] * hp_mult
	hp = max_hp
	dmg_mult = p_dmg_mult
	radius = def["radius"]
	hover = def.get("hover", 0.0)
	is_boss = def.get("boss", false)
	stun_time = def["stun"]
	bounds = p_bounds
	ground_y = p_ground
	for a in def["attacks"]:
		cooldowns.append(randf_range(0.0, 0.6))


func _ready() -> void:
	add_to_group("enemies")
	position.y = ground_y
	shadow = Sprite2D.new()
	shadow.texture = SHADOW
	shadow.scale = Vector2(radius / 70.0, 1.0)
	shadow.modulate.a = 0.75
	add_child(shadow)
	body = Node2D.new()
	add_child(body)
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = load(def["frames"])
	var anchor: Vector2 = sprite.sprite_frames.get_meta("anchor")
	var fsize: Vector2 = sprite.sprite_frames.get_meta("frame_size")
	sprite.offset = fsize * 0.5 - anchor
	mat = ShaderMaterial.new()
	mat.shader = FLASH
	sprite.material = mat
	body.add_child(sprite)
	sprite.frame_changed.connect(_on_frame)
	alert = Sprite2D.new()
	alert.texture = ALERT
	alert.position = Vector2(0, maxf(def["bar_y"] - 78.0, -440.0))
	alert.visible = false
	alert.z_index = 45
	add_child(alert)
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player:
		face = 1 if player.global_position.x > global_position.x else -1
	# появление: проступает из пыли
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.45)
	FX.dust(get_parent(), Vector2(global_position.x, ground_y), 10, 1.6)
	_play(def["idle_anim"])
	if is_boss:
		Sfx.play("boss_roar")
		Fx.shake(10.0)


func is_alive() -> bool:
	return state != S.DEAD and state != S.SPAWN


func _play(anim: String, from_frame := 0) -> void:
	_last_event = ""
	sprite.play(anim)
	sprite.frame = from_frame


# ------------------------------------------------------------------ цикл
func _physics_process(delta: float) -> void:
	st += delta
	global_cd -= delta
	teleport_cd -= delta
	for i in cooldowns.size():
		cooldowns[i] -= delta
	flash = maxf(0.0, flash - delta * 6.0)
	_update_burn(delta)
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	var move := 0.0
	match state:
		S.SPAWN:
			if st > 0.6:
				_to_idle()
		S.IDLE, S.MOVE:
			move = _think(delta)
		S.ATTACK:
			_attack_update(delta)
		S.RECOVER:
			vx *= exp(-delta * 8.0)
			if st > (0.2 if enraged else 0.35):
				_to_idle()
		S.HURT:
			vx = 0.0
			if st > (0.45 if is_boss else 0.24):
				_to_idle()
		S.STUN:
			vx = 0.0
			if st > stun_time:
				_to_idle()
		S.TELEPORT:
			_teleport_update()
		S.DEAD:
			vx = 0.0
	if state != S.ATTACK or not dashing:
		vx = lerpf(vx, move, minf(1.0, delta * 10.0)) if state == S.IDLE or state == S.MOVE else vx
	position.x += (vx + kb) * delta
	kb *= exp(-delta * 9.0)
	if not leaping:
		position.x = clampf(position.x, bounds.x, bounds.y)
	position.y = ground_y
	_update_visual(delta)


func _think(delta: float) -> float:
	if player == null or player.is_dead():
		if state != S.IDLE:
			state = S.IDLE
			_play(def["idle_anim"])
		return 0.0
	var dx: float = player.global_position.x - global_position.x
	var dist := absf(dx)
	face = 1 if dx > 0.0 else -1
	var ai: String = def["ai"]
	# бақсы: призыв и телепорт
	if def.has("summon"):
		summon_t += delta
		var sm: Dictionary = def["summon"]
		if summon_t >= sm["every"] and global_cd <= 0.0 and _count_summoned() < sm["max"]:
			summon_t = 0.0
			_start_attack({"anim": "attack", "telegraph": [0, 1], "cooldown": 0.0,
				"summon": {"frame": 3, "kind": sm["kind"], "count": 1}})
			return 0.0
	if def.get("teleport", false) and dist < 230.0 and teleport_cd <= 0.0:
		_start_teleport()
		return 0.0
	if not is_boss and enraged == false and def.get("enrage", 0.0) > 0.0:
		pass
	if global_cd <= 0.0 and _may_attack():
		var pick := _pick_attack(dist)
		if pick >= 0:
			cooldowns[pick] = def["attacks"][pick]["cooldown"] * (0.7 if enraged else 1.0)
			_start_attack(def["attacks"][pick])
			return 0.0
	var speed: float = def["speed"] * (1.2 if enraged else 1.0)
	var want := 0.0
	if ai == "ranged" or ai == "caster":
		var keep: Array = def["keep"]
		if dist < keep[0]:
			want = -face * speed * 0.85    # пятится, не отворачиваясь
		elif dist > keep[1]:
			want = face * speed
	else:
		var stop := 130.0 + radius * 0.5
		if dist > stop:
			want = face * speed
	# не толпиться: если впереди свой — притормозить
	if want != 0.0:
		for o in get_tree().get_nodes_in_group("enemies"):
			if o != self and o.is_alive() and not o.is_boss:
				var od: float = (o.global_position.x - global_position.x) * signf(want)
				if od > 0.0 and od < 75.0:
					want *= 0.2
					break
	var anim: String = def["move_anim"] if absf(want) > 10.0 else def["idle_anim"]
	var new_state := S.MOVE if absf(want) > 10.0 else S.IDLE
	if new_state != state or String(sprite.animation) != anim:
		state = new_state
		_play(anim)
	return want


const MAX_ATTACKERS := 2


func _may_attack() -> bool:
	## Очередь атак: одновременно замахиваются не больше двух обычных врагов (боссы — всегда),
	## иначе урон без неуязвимости складывается мгновенно и бой становится нечестным.
	if is_boss:
		return true
	var n := 0
	for o in get_tree().get_nodes_in_group("enemies"):
		if o != self and not o.is_boss and o.state == S.ATTACK:
			n += 1
	return n < MAX_ATTACKERS


func _pick_attack(dist: float) -> int:
	var total := 0.0
	var options := []
	var attacks: Array = def["attacks"]
	for i in attacks.size():
		var a: Dictionary = attacks[i]
		var r: Array = a["range"]
		if cooldowns[i] > 0.0 or dist < r[0] or dist > r[1]:
			continue
		if a.has("hp_below") and hp / max_hp > a["hp_below"]:
			continue
		if a.has("summon") and _count_summoned() + a["summon"]["count"] > a["summon"].get("max", 2):
			continue   # не больше max призванных одновременно
		var w: float = a.get("weight", 1.0)
		options.append([i, w])
		total += w
	if options.is_empty():
		return -1
	var roll := randf() * total
	for o in options:
		roll -= o[1]
		if roll <= 0.0:
			return o[0]
	return options[-1][0]


func _count_summoned() -> int:
	var n := 0
	for o in get_tree().get_nodes_in_group("enemies"):
		if o.summoned_by == self and o.is_alive():
			n += 1
	return n


func _to_idle() -> void:
	state = S.IDLE
	st = 0.0
	alert.visible = false
	windup_t = 0.0
	sprite.speed_scale = 1.0
	_play(def["idle_anim"])


# ------------------------------------------------------------------ удары
func _start_attack(a: Dictionary) -> void:
	attack = a
	state = S.ATTACK
	st = 0.0
	leaping = false
	dashing = false
	proj_left = 0
	combo_left = 1 if randf() < a.get("combo", 0.0) else 0
	if player:
		face = 1 if player.global_position.x > global_position.x else -1
	sprite.speed_scale = a.get("speed", 1.0) * (1.25 if enraged else 1.0)
	_play(a["anim"], a.get("start", 0))
	_begin_telegraph(REACT_ENRAGED if enraged else REACT)
	_event_once()


func _danger_frame(a: Dictionary, from: int) -> int:
	## Первый кадр, на котором удар может задеть героя (удар, бросок, выстрел).
	var frames := []
	for h in a.get("hits", []):
		if h["frame"] >= 0:
			frames.append(h["frame"])
	if a.has("dash"):
		frames.append(a["dash"]["from"])
	if a.has("projectile"):
		frames.append(a["projectile"]["frame"])
	var best := -1
	for f in frames:
		if f >= from and (best < 0 or f < best):
			best = f
	return best


func _begin_telegraph(react: float) -> void:
	## «!» над врагом до первого удара. Если замах короче react — враг дольше держит позу замаха.
	var a := attack
	alert_frame = _danger_frame(a, sprite.frame)
	windup_t = 0.0
	if alert_frame < 0:
		alert.visible = false
		return
	var unblockable := false
	for h in a.get("hits", []):
		if not h.get("block", true):
			unblockable = true
	alert.modulate = Color(1.0, 0.22, 0.15) if unblockable else Color(1.0, 0.82, 0.25)
	alert.visible = true
	alert.scale = Vector2(0.2, 0.2)
	var tw := create_tween()
	tw.tween_property(alert, "scale", Vector2(1.25, 1.25), 0.08)
	tw.tween_property(alert, "scale", Vector2.ONE, 0.08)
	var t_hit := _anim_time(a["anim"], sprite.frame, alert_frame, false) * (1.0 - sprite.frame_progress * 0.5)
	if t_hit < react:
		windup_t = react - t_hit
		sprite.pause()
	Sfx.play("alert", -8.0 if not unblockable else -3.0)


func _event_once() -> void:
	## События стартового кадра удара — ровно один раз (смена кадра в _play может уже вызвать _on_frame).
	var key := "%s%d" % [sprite.animation, sprite.frame]
	if key != _last_event:
		_last_event = key
		_attack_event(sprite.frame)


func _on_frame() -> void:
	var key := "%s%d" % [sprite.animation, sprite.frame]
	if key == _last_event:
		return
	_last_event = key
	if state == S.ATTACK:
		_attack_event(sprite.frame)
	elif state == S.MOVE and (sprite.frame == 0 or sprite.frame == 2) and not is_boss and hover == 0.0:
		if kind == "balbal":
			FX.dust(get_parent(), Vector2(global_position.x + face * 20, ground_y), 2, 0.6)
	elif state == S.MOVE and is_boss and (sprite.frame == 0 or sprite.frame == 2):
		Fx.shake(3.0 if kind == "shoyyn" else 1.0)
		FX.dust(get_parent(), Vector2(global_position.x + face * 30, ground_y), 4, 1.2)


func _attack_event(f: int) -> void:
	var a := attack
	if f >= alert_frame:
		alert.visible = false
	for h in a.get("hits", []):
		if h["frame"] == f:
			_resolve_hit(h)
	if a.has("lunge") and a["lunge"]["frame"] == f:
		vx = face * a["lunge"]["speed"]
	if a.has("smear") and a["smear"]["frame"] == f:
		var sm: Dictionary = a["smear"]
		FX.smear(get_parent(), global_position + Vector2(face * 10, -150.0 * sm["radius"] / 300.0), face, sm["radius"], sm["color"])
		Sfx.play("swing_enemy")
	if a.has("impact") and a["impact"]["frame"] == f:
		var im: Dictionary = a["impact"]
		var p := Vector2(global_position.x + face * im["x"], ground_y)
		FX.dust(get_parent(), p, 12, 1.8)
		FX.chips(get_parent(), p, 6)
		Fx.shake(im["shake"])
		Sfx.play("slam")
	if a.has("leap") and a["leap"]["from"] == f:
		var lp: Dictionary = a["leap"]
		leaping = true
		leap_t = 0.0
		leap_from = global_position.x
		var tx: float = player.global_position.x - face * 50.0 if player else global_position.x + face * 300.0
		leap_to = clampf(tx, bounds.x, bounds.y)
		leap_h = lp["height"]
		leap_dur = _anim_time(a["anim"], lp["from"], lp["to"])
		Sfx.play("leap")
	if a.has("dash") and a["dash"]["from"] == f:
		dashing = true
		dash_done = false
		vx = face * a["dash"]["speed"]
		Sfx.play("dash_enemy")
	if a.has("dash") and a["dash"]["to"] + 1 == f:
		dashing = false
	if a.has("projectile") and a["projectile"]["frame"] == f:
		proj_left = a["projectile"].get("count", 1)
		proj_t = 0.0
	if a.has("summon") and a["summon"]["frame"] == f:
		var sm2: Dictionary = a["summon"]
		for i in sm2["count"]:
			var sx := clampf(global_position.x + (i * 2 - 1) * 260.0 + randf_range(-60, 60), bounds.x, bounds.y)
			summon_requested.emit(sm2["kind"], sx)
		FX.glow_burst(get_parent(), global_position + Vector2(0, -180), Color(0.8, 0.4, 1.0, 0.9), 2.5)
		Sfx.play("summon")


func _anim_time(anim: String, from: int, to: int, clamp_min := true) -> float:
	var t := 0.0
	var sf := sprite.sprite_frames
	var fps := sf.get_animation_speed(anim) * sprite.speed_scale
	for i in range(from, to):
		t += sf.get_frame_duration(anim, i) / fps
	return maxf(t, 0.15) if clamp_min else t


func _attack_update(delta: float) -> void:
	var a := attack
	# телеграф: подсветка в кадрах замаха — время среагировать
	if windup_t > 0.0 or sprite.frame in a.get("telegraph", []):
		tele = 0.55 + 0.45 * sin(st * 22.0)
	if windup_t > 0.0:
		vx *= exp(-delta * 6.0)
		windup_t -= delta
		if windup_t <= 0.0:
			sprite.play()   # продолжить анимацию с того же кадра
		return
	if leaping:
		leap_t += delta
		var k := minf(1.0, leap_t / leap_dur)
		position.x = lerpf(leap_from, leap_to, k)
		body.position.y = -sin(k * PI) * leap_h - hover
		if k >= 1.0:
			leaping = false
			body.position.y = -hover
	elif not dashing:
		vx *= exp(-delta * 6.0)
	if dashing and not dash_done and player:
		if absf(player.global_position.x - global_position.x) < 80.0:
			dash_done = true
			for h in a.get("hits", []):
				if h["frame"] == -1:
					_resolve_hit(h, true)
	if proj_left > 0:
		proj_t -= delta
		if proj_t <= 0.0:
			proj_left -= 1
			proj_t = a["projectile"].get("interval", 0.2)
			_fire(a["projectile"])
	if not sprite.is_playing():
		alert.visible = false
		windup_t = 0.0
		if combo_left > 0 and player and absf(player.global_position.x - global_position.x) < a["range"][1] + 80.0:
			combo_left -= 1
			face = 1 if player.global_position.x > global_position.x else -1
			var from: int = a.get("combo_from", 0)
			_play(a["anim"], from)
			sprite.frame_progress = 0.55   # повторный удар — с коротким замахом
			_begin_telegraph(REACT_REPEAT)
			_event_once()
		else:
			state = S.RECOVER
			st = 0.0
			dashing = false
			sprite.speed_scale = 1.0
			global_cd = 0.25 if enraged else 0.45
			_play(def["idle_anim"])


func _resolve_hit(h: Dictionary, contact := false) -> void:
	if player == null or player.is_dead():
		return
	var dx: float = (player.global_position.x - global_position.x) * face
	var ok := false
	if h.has("radius"):
		ok = absf(player.global_position.x - global_position.x) <= h["radius"]
	elif contact:
		ok = true
	elif h.has("reach"):
		var r: Array = h["reach"]
		ok = dx >= r[0] and dx <= r[1]
	if not ok:
		return
	player.receive_attack({"dmg": h["dmg"] * dmg_mult, "knock": h["knock"], "from_x": global_position.x,
		"parry": h.get("parry", true), "block": h.get("block", true), "source": self})


func _fire(pr: Dictionary) -> void:
	var dirs := [face]
	if pr.get("both_enraged", false) and enraged:
		dirs = [face, -face]
	for d in dirs:
		var p := PROJECTILE.new()
		var x0: float = global_position.x + d * pr.get("x", 60.0)
		p.setup(pr["kind"], Vector2(x0, ground_y + pr["y"]), d, pr["speed"], pr["dmg"] * dmg_mult, self, ground_y)
		get_parent().add_child(p)
	Sfx.play("shoot_" + String(pr["kind"]))


# ------------------------------------------------------------------ телепорт (бақсы)
func _start_teleport() -> void:
	state = S.TELEPORT
	st = 0.0
	teleport_cd = 5.0
	_play("teleport")
	Sfx.play("teleport")


func _teleport_update() -> void:
	if st < 0.45:
		modulate.a = 1.0 - st / 0.45
		return
	if st < 0.5 and player:
		var px: float = player.global_position.x
		var to := px + 520.0 if px < (bounds.x + bounds.y) * 0.5 else px - 520.0
		position.x = clampf(to, bounds.x, bounds.y)
		FX.glow_burst(get_parent(), global_position + Vector2(0, -120), Color(0.75, 0.35, 1.0, 0.9), 2.0)
	modulate.a = minf(1.0, (st - 0.5) / 0.3)
	if st > 0.8:
		modulate.a = 1.0
		_to_idle()


# ------------------------------------------------------------------ получение урона
func take_hit(dmg: float, dir: int, knock: float, heavy: bool) -> float:
	if state == S.DEAD or state == S.SPAWN:
		return 0.0
	if state == S.STUN:
		dmg *= 1.5
	hp -= dmg
	flash = 0.55 if is_boss else 1.0
	mat.set_shader_parameter("flash_color", Color(1, 1, 1))
	Fx.float_text(get_parent(), global_position + Vector2(0, _text_y()), str(roundi(dmg)),
		Color(1, 0.82, 0.4) if heavy else Color.WHITE, 34 if heavy else 30)
	kb = dir * knock * def["knock_mult"]
	if hp <= 0.0:
		_die()
		return dmg
	if is_boss and not enraged and hp / max_hp < def.get("enrage", 0.0):
		enraged = true
		Fx.float_text(get_parent(), global_position + Vector2(0, _text_y() - 50.0), "ЯРОСТЬ!", Color(1, 0.35, 0.2), 34)
		Sfx.play("boss_roar")
		Fx.shake(12.0)
	poise_acc += dmg
	if state == S.STUN:
		stun_time += 0.1
		return dmg
	var interruptible: bool = state == S.IDLE or state == S.MOVE or state == S.RECOVER or state == S.HURT \
		or (state == S.ATTACK and not def["armored"])
	if heavy and state == S.ATTACK and def["armored"] and not is_boss:
		interruptible = true   # третий удар комбо пробивает броню
		Fx.float_text(get_parent(), global_position + Vector2(0, _text_y() - 40.0), "пробит", Color(1, 0.82, 0.4), 22)
	if is_boss:
		interruptible = poise_acc >= def["poise"]
	elif poise_acc < def["poise"] and not heavy:
		interruptible = false
	if interruptible:
		poise_acc = 0.0
		_hurt()
	return dmg


func _text_y() -> float:
	## Высота всплывающих цифр: над головой, но у огромных боссов — не выше края экрана.
	return maxf(def["bar_y"] + 30.0, -380.0)


func _hurt() -> void:
	state = S.HURT
	st = 0.0
	leaping = false
	dashing = false
	proj_left = 0
	alert.visible = false
	windup_t = 0.0
	body.position.y = -hover
	sprite.speed_scale = 1.0
	_play(def["hurt_anim"])


func stun(extra := 0.0) -> void:
	## Идеальный блок героя: враг оглушён и получает ×1.5 урона.
	if state == S.DEAD:
		return
	state = S.STUN
	st = 0.0
	stun_time = def["stun"] + extra
	leaping = false
	dashing = false
	proj_left = 0
	alert.visible = false
	windup_t = 0.0
	vx = 0.0
	kb = -face * 70.0
	body.position.y = -hover
	sprite.speed_scale = 1.0
	_play(def["stun_anim"])


func apply_burn(dps: float, dur: float) -> void:
	if state == S.DEAD:
		return
	burn_dps = maxf(burn_dps, dps)
	burn_time = maxf(burn_time, dur)
	if burn_fx == null:
		burn_fx = CPUParticles2D.new()
		burn_fx.texture = preload("res://assets/fx/soft.png")
		burn_fx.material = FX.additive()
		burn_fx.amount = 14
		burn_fx.lifetime = 0.6
		burn_fx.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		burn_fx.emission_rect_extents = Vector2(radius * 0.5, 50)
		burn_fx.position = Vector2(0, -90)
		burn_fx.direction = Vector2(0, -1)
		burn_fx.gravity = Vector2(0, -200)
		burn_fx.initial_velocity_min = 20.0
		burn_fx.initial_velocity_max = 60.0
		burn_fx.scale_amount_min = 0.2
		burn_fx.scale_amount_max = 0.45
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.75, 0.3, 0.9))
		g.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
		burn_fx.color_ramp = g
		body.add_child(burn_fx)
	burn_fx.emitting = true


func _update_burn(delta: float) -> void:
	if burn_time <= 0.0:
		return
	burn_time -= delta
	burn_tick -= delta
	if burn_tick <= 0.0:
		burn_tick = 0.5
		if state != S.DEAD:
			hp -= burn_dps * 0.5
			Fx.float_text(get_parent(), global_position + Vector2(0, _text_y() + 10.0), str(roundi(burn_dps * 0.5)), Color(1, 0.6, 0.25), 22)
			if hp <= 0.0:
				_die()
	if burn_time <= 0.0 and burn_fx:
		burn_fx.emitting = false


func _die() -> void:
	if state == S.DEAD:
		return
	state = S.DEAD
	st = 0.0
	leaping = false
	alert.visible = false
	windup_t = 0.0
	body.position.y = -hover
	remove_from_group("enemies")
	sprite.speed_scale = 1.0
	_play(def["death_anim"])
	if burn_fx:
		burn_fx.emitting = false
	GameState.register_kill()
	var n := randi_range(def["asyks"][0], def["asyks"][1])
	for i in n:
		var a := ASYK.new()
		a.position = global_position + Vector2(randf_range(-30, 30), -100 - hover)
		a.ground_y = ground_y
		get_parent().add_child(a)
	FX.chips(get_parent(), global_position + Vector2(0, -60), 10 if kind == "balbal" else 4)
	if is_boss:
		Fx.hitstop(0.35, 0.03)
		Fx.shake(20.0)
		Fx.punch(0.08)
		Sfx.play("boss_death")
	else:
		Fx.hitstop(0.08)
		Sfx.play("death_" + kind)
	died.emit(self)
	var tw := create_tween()
	tw.tween_interval(1.4 if is_boss else 0.9)
	tw.tween_property(self, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)


# ------------------------------------------------------------------ картинка
func _update_visual(_delta: float) -> void:
	sprite.flip_h = face < 0
	if alert.visible:
		# «!» следует за телом (прыжок, парение) и пульсирует
		alert.position.y = maxf(def["bar_y"] - 78.0, -440.0) + body.position.y + hover
		alert.rotation = sin(Time.get_ticks_msec() * 0.03) * 0.08
	if hover > 0.0 and not leaping:
		body.position.y = -hover + sin(Time.get_ticks_msec() * 0.004 + position.x * 0.01) * 6.0
	tele = maxf(0.0, tele - _delta * 5.0)
	var red := tele * 0.6 + (0.22 + 0.1 * sin(Time.get_ticks_msec() * 0.01) if enraged else 0.0)
	sprite.self_modulate = Color(1.0, 1.0 - red * 0.6, 1.0 - red * 0.75)
	mat.set_shader_parameter("flash", flash)
	shadow.modulate.a = 0.75 * (1.0 - clampf(-body.position.y / 300.0, 0.0, 0.7))
	queue_redraw()


func _draw() -> void:
	# полоска здоровья над обычными врагами (у боссов — большая полоса внизу экрана)
	if is_boss or state == S.DEAD or hp >= max_hp:
		return
	var w := 110.0
	var y: float = def["bar_y"] + body.position.y + hover
	draw_rect(Rect2(-w / 2 - 2, y - 2, w + 4, 11), Color(0.08, 0.04, 0.03, 0.85))
	draw_rect(Rect2(-w / 2, y, w * clampf(hp / max_hp, 0.0, 1.0), 7), Color(0.85, 0.28, 0.23))
	draw_rect(Rect2(-w / 2 - 2, y - 2, w + 4, 11), Color(0.85, 0.7, 0.36), false, 1.5)
