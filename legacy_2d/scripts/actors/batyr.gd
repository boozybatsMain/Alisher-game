extends CharacterBody2D
## Батыр — главный герой.
## Бой перенесён из прототипа (tools/preview_demo.html): комбо из трёх ударов (третий — тяжёлый, пробивает броню),
## кувырок с перезарядкой, рывок-удар из кувырка, блок (−75% урона) и идеальный блок в момент удара,
## перезарядка щита после блока, без неуязвимости после попадания.

signal hp_changed(hp: float, max_hp: float)
signal died

const Anchors := preload("res://scripts/data/hero_anchors.gd")
const Gifts := preload("res://scripts/data/gifts.gd")
const FX := preload("res://scripts/fx/effects.gd")
const RIBBON := preload("res://scripts/actors/ribbon.gd")
const FLASH := preload("res://shaders/flash.gdshader")
const GHOST := preload("res://shaders/ghost.gdshader")

# --- темп как в Dead Cells: всё быстро, но у кувырка и щита есть перезарядка ---
const RUN_SPEED := 760.0
const ROLL_SPEED := 1250.0
const ROLL_DECAY := 0.45
const ROLL_RECOVER := 0.17
const ROLL_CD := 1.0
## Щит как в Dead Cells: нажатие поднимает его минимум на SHIELD_MIN_UP секунд (дольше — пока держишь),
## удар в первые PARRY_WINDOW секунд — идеальный блок. Если за подъём щит ничего не принял (промах) —
## он недоступен SHIELD_CD секунд; если принял удар (блок или идеальный блок) — можно ставить сразу снова.
const SHIELD_CD := 0.6
const SHIELD_MIN_UP := 0.5
const COMBO_RECOVER := 0.25
const DASH_SPEED := 1450.0
const PARRY_WINDOW := 0.2
const BUFFER := 0.16
const ROLL_IFRAMES := 0.32

# кадры событий в анимациях (из листов Codex)
const IMPACT := {"attack1": 5, "attack2": 1, "attack3": 2}
const LUNGE := {"attack1": 4, "attack2": 0, "attack3": 1}
const REACH := {"attack1": 185.0, "attack2": 175.0, "attack3": 210.0}
const DMG := {"attack1": 1.0, "attack2": 1.15, "attack3": 2.4}

enum S { IDLE, RUN, ATTACK, COMBO_REC, ROLL, ROLL_REC, DASH, BLOCK, PARRY, HURT, DEAD, LOCKED }

## Из каких состояний щит поднимается мгновенно (то есть почти из любых).
const BLOCK_FROM := [S.IDLE, S.RUN, S.ATTACK, S.COMBO_REC, S.ROLL, S.ROLL_REC, S.DASH, S.HURT]

var state := S.IDLE
var st := 0.0
var facing := 1
var hp := 100.0
var max_hp := 100.0
var combo := 0
var queued := false
var invuln := 0.0
var block_t := 0.0
var parried_this_raise := false   # за этот подъём щит принял удар → без перезарядки
var raise_until := 0.0            # щит стоит минимум до этого block_t (каждое нажатие продлевает на 0.5 с)
var roll_cd := 0.0
var shield_cd := 0.0
var roll_cd_max := ROLL_CD
var shield_cd_max := SHIELD_CD
var deny_roll := 0.0
var deny_shield := 0.0
var hurt_flash := 0.0
var dash_hit := []
var buf := {"attack": 0.0, "roll": 0.0, "block": 0.0}
var ground_y := 0.0
var bounds := Vector2(-100000.0, 100000.0)
var input_enabled := true
var walk_target := NAN   # авто-ход для катсцен (вход на арену, уход со стадии)
var sx := 1.0
var sy := 1.0
var vsx := 0.0
var vsy := 0.0
var lean := 0.0
var ghost_t := 0.0
var run_ghost_t := 0.0
var trail_t := 0.0
var gust := 0.0          # ветер с арены — для ленты
var _last_event := ""

@onready var visual: Node2D = $Visual
@onready var sprite: AnimatedSprite2D = $Visual/Sprite
@onready var glow: AnimatedSprite2D = $Visual/Glow
@onready var shadow: Sprite2D = $Shadow
var ribbon: Node2D
var blur: Array[Sprite2D] = []
var flash_mat: ShaderMaterial
var ghost_mat: ShaderMaterial


func _ready() -> void:
	add_to_group("player")
	ground_y = position.y
	max_hp = GameState.max_hp()
	hp = max_hp if GameState.hp_carry < 0 else minf(GameState.hp_carry, max_hp)
	roll_cd_max = ROLL_CD * GameState.cooldown_mult()
	shield_cd_max = SHIELD_CD * GameState.cooldown_mult()
	var anchor: Vector2 = sprite.sprite_frames.get_meta("anchor")
	var fsize: Vector2 = sprite.sprite_frames.get_meta("frame_size")
	sprite.offset = fsize * 0.5 - anchor
	glow.offset = sprite.offset
	glow.stop()
	flash_mat = ShaderMaterial.new()
	flash_mat.shader = FLASH
	sprite.material = flash_mat
	ghost_mat = ShaderMaterial.new()
	ghost_mat.shader = GHOST
	# размытие движения: копии спрайта позади героя
	for i in 3:
		var b := Sprite2D.new()
		b.offset = sprite.offset
		b.visible = false
		visual.add_child(b)
		visual.move_child(b, 0)
		blur.append(b)
	ribbon = RIBBON.new()
	ribbon.hero = self
	add_child(ribbon)
	move_child(ribbon, 1)
	sprite.frame_changed.connect(_on_frame)
	_play("idle")
	hp_changed.emit(hp, max_hp)


# ------------------------------------------------------------------ ввод
func _read_input() -> float:
	if not input_enabled:
		buf.attack = 0.0
		buf.roll = 0.0
		buf.block = 0.0
		if not is_nan(walk_target):
			var d := walk_target - global_position.x
			return 0.0 if absf(d) < 12.0 else signf(d)
		return 0.0
	if Input.is_action_just_pressed("attack"):
		buf.attack = BUFFER
	if Input.is_action_just_pressed("roll"):
		buf.roll = BUFFER
	if Input.is_action_just_pressed("block"):
		# очень быстрое нажатие (нажал и отпустил в одном кадре) видно только как just_pressed —
		# запоминаем его, а заодно нажатие чуть раньше конца перезарядки или паузы после парирования
		buf.block = BUFFER
	if Input.is_action_just_pressed("block") and shield_cd > 0.0 and state != S.BLOCK and state != S.PARRY and state != S.DEAD:
		deny_shield = 1.0
	return Input.get_axis("move_left", "move_right")


func _want(a: String) -> bool:
	return buf[a] > 0.0


func _use(a: String) -> void:
	buf[a] = 0.0


func _try_roll(dir: float) -> bool:
	if not _want("roll"):
		return false
	if roll_cd > 0.0:
		if buf.roll >= BUFFER - 0.001:
			deny_roll = 1.0
		return false
	_use("roll")
	_start_roll(dir)
	return true


# ------------------------------------------------------------------ цикл
func _physics_process(delta: float) -> void:
	st += delta
	invuln = maxf(0.0, invuln - delta)
	roll_cd = maxf(0.0, roll_cd - delta)
	shield_cd = maxf(0.0, shield_cd - delta)
	deny_roll = maxf(0.0, deny_roll - delta * 3.0)
	deny_shield = maxf(0.0, deny_shield - delta * 3.0)
	hurt_flash = maxf(0.0, hurt_flash - delta * 4.0)
	var dir := _read_input()
	var block_pressed := input_enabled and Input.is_action_just_pressed("block")
	var block_held := input_enabled and (Input.is_action_pressed("block") or block_pressed)
	# щит — в любой момент: прерывает удар, восстановление, кувырок, рывок и оглушение
	if (block_held or _want("block")) and shield_cd <= 0.0 and state in BLOCK_FROM:
		_use("block")
		_start_block(dir)

	match state:
		S.IDLE, S.RUN:
			if _try_roll(dir):
				pass
			elif _want("attack"):
				_use("attack")
				if dir != 0.0:
					facing = int(signf(dir))
				_start_attack(0)
			elif dir != 0.0:
				facing = int(signf(dir))
				velocity.x = dir * RUN_SPEED * (0.55 if not input_enabled else 1.0)
				if state != S.RUN:
					_set_state(S.RUN)
					_play("run")
			else:
				velocity.x *= exp(-delta * 22.0)
				if state != S.IDLE:
					_set_state(S.IDLE)
					_play("idle")
		S.ATTACK:
			velocity.x *= exp(-delta * 7.0)
			if _want("attack") and combo < 2:
				_use("attack")
				queued = true
			var anim := String(sprite.animation)
			var imp: int = IMPACT[anim]
			var past := sprite.frame > imp or (sprite.frame == imp and sprite.frame_progress > 0.6)
			if combo < 2 and sprite.frame >= imp and _try_roll(dir):
				pass
			elif queued and past:
				if dir != 0.0:
					facing = int(signf(dir))
				_start_attack(combo + 1)   # отмена восстановления в следующий удар
			elif not sprite.is_playing():
				if combo == 2:
					_set_state(S.COMBO_REC)   # после тяжёлого финала — заметное восстановление
				else:
					_to_idle()
		S.COMBO_REC:
			velocity.x *= exp(-delta * 10.0)
			if st >= COMBO_RECOVER:
				_to_idle()
		S.ROLL:
			var total := 0.35
			var k := minf(1.0, st / total)
			velocity.x = facing * ROLL_SPEED * (1.0 - ROLL_DECAY * k)
			if GameState.has_gift(1, "ot_ana"):
				trail_t -= delta
				if trail_t <= 0.0:
					trail_t = 0.06
					FX.fire_patch(get_parent(), Vector2(global_position.x, ground_y), GameState.gift_value(1)["dps"], self)
			if _want("attack") and st > 0.05:
				_use("attack")
				_start_dash()
			elif not sprite.is_playing():
				_end_roll()
				_set_state(S.ROLL_REC)
		S.ROLL_REC:
			velocity.x *= exp(-delta * 16.0)
			if st >= ROLL_RECOVER:
				_to_idle()
		S.DASH:
			if sprite.frame == 0:
				velocity.x *= exp(-delta * 10.0)
			elif sprite.frame >= 3:
				velocity.x *= exp(-delta * 9.0)
			if sprite.frame >= 1:
				for e in get_tree().get_nodes_in_group("enemies"):
					if e.is_alive() and not dash_hit.has(e) and absf(e.global_position.x - global_position.x) < 80.0 + e.radius * 0.4:
						dash_hit.append(e)
						_hit_enemy(e, GameState.saber_damage() * 1.6, false)
			if not sprite.is_playing():
				_end_roll()
				_to_idle()
		S.BLOCK:
			block_t += delta
			velocity.x *= exp(-delta * 12.0)
			if dir != 0.0:
				facing = int(signf(dir))
			else:
				var td := _threat_dir(false)   # держишь щит — он поворачивается к тому, кто бьёт
				if td != 0:
					facing = td
			sprite.frame = 0 if block_t < 0.08 else 1 + int((block_t - 0.08) * 5.0) % 2
			if _want("block"):
				_use("block")
				raise_until = block_t + SHIELD_MIN_UP   # повторное нажатие продлевает щит
			if not block_held and block_t >= raise_until:
				_lower_shield()   # короткое нажатие держит щит 0.5 с, дольше — пока зажат
				_to_idle()
			elif _try_roll(dir):
				_lower_shield()
		S.PARRY:
			velocity.x *= exp(-delta * 10.0)
			if st > 0.12 and _want("attack"):
				_use("attack")
				_lower_shield()
				_start_attack(0)   # контратака после идеального блока
			elif st > 0.35:
				if block_held or _want("block"):
					_use("block")
					_set_state(S.BLOCK)
					block_t = PARRY_WINDOW   # дальше обычный блок: пока держишь или ещё 0.5 с после нажатия
					raise_until = block_t + SHIELD_MIN_UP
					_play("block")
					sprite.stop()
				else:
					_lower_shield()
					_to_idle()
		S.HURT:
			velocity.x *= exp(-delta * 6.0)
			# неуязвимости нет, но из оглушения можно выйти кувырком (или щитом — он работает всегда)
			if st > 0.12 and _try_roll(dir):
				pass
			elif not sprite.is_playing():
				_to_idle()
		S.DEAD:
			velocity.x *= exp(-delta * 5.0)
		S.LOCKED:
			velocity.x *= exp(-delta * 12.0)

	for k in buf:
		buf[k] = maxf(0.0, buf[k] - delta)
	move_and_slide()
	_separate_from_enemies()
	# граница арены — последней: у стены враг может «зажать» героя, но не вытолкнуть за барьер
	global_position.x = clampf(global_position.x, bounds.x, bounds.y)
	global_position.y = ground_y
	_update_visual(delta)


func _separate_from_enemies() -> void:
	# сквозь врагов проходят только кувырок и рывок
	if state == S.ROLL or state == S.DASH or state == S.DEAD:
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.is_alive() or e.get("hover") > 0.0:
			continue
		var min_d: float = 60.0 + e.radius * 0.6
		var d: float = global_position.x - e.global_position.x
		if absf(d) < min_d:
			global_position.x = e.global_position.x + (signf(d) if d != 0.0 else -facing) * min_d


func _set_state(s: S) -> void:
	state = s
	st = 0.0


func _to_idle() -> void:
	_set_state(S.IDLE)
	_play("idle")


func _play(anim: String) -> void:
	_last_event = ""
	sprite.play(anim)
	sprite.frame = 0
	sprite.frame_progress = 0.0


# ------------------------------------------------------------------ атака
func _start_attack(i: int) -> void:
	_set_state(S.ATTACK)
	combo = i
	queued = false
	_play(["attack1", "attack2", "attack3"][i])
	_on_frame()


func _on_frame() -> void:
	var anim := String(sprite.animation)
	var f := sprite.frame
	var key := "%s%d" % [anim, f]
	if key == _last_event:
		return
	_last_event = key
	match anim:
		"run":
			if f == 0 or f == 2:
				_squash(1.06, 0.93)
				FX.dust(get_parent(), Vector2(global_position.x + facing * 30, ground_y), 3, 0.7, gust)
		"attack1", "attack2", "attack3":
			if state != S.ATTACK:
				return
			if f == LUNGE[anim]:
				velocity.x = facing * (550.0 if anim == "attack3" else 390.0)
				_squash(1.09, 0.93)
				Sfx.play("swing" if anim != "attack3" else "swing_heavy")
			if f == IMPACT[anim]:
				_do_hit(anim)
		"dash":
			if f == 1:
				velocity.x = facing * DASH_SPEED
				FX.dust(get_parent(), Vector2(global_position.x, ground_y), 6)
				_squash(1.18, 0.86)
				Sfx.play("dash")
			elif f == 3:
				velocity.x = facing * 120.0
				_squash(0.92, 1.07)
		"roll":
			if f == 0:
				_squash(1.16, 0.85)
				FX.dust(get_parent(), Vector2(global_position.x, ground_y), 5)
			elif f == 3:
				_squash(0.9, 1.08)
				FX.dust(get_parent(), Vector2(global_position.x, ground_y), 4)


func _do_hit(anim: String) -> void:
	var heavy := anim == "attack3"
	var dmg: float = GameState.saber_damage() * DMG[anim]
	var hit_any := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.is_alive():
			continue
		var dx: float = (e.global_position.x - global_position.x) * facing
		if dx > -40.0 - e.radius * 0.3 and dx < REACH[anim] + e.radius * 0.5:
			_hit_enemy(e, dmg, heavy)
			hit_any = true
	if hit_any:
		Fx.hitstop(0.13 if heavy else 0.075)
		Fx.shake(14.0 if heavy else 6.0)
		if heavy:
			Fx.punch(0.06)
		_squash(1.06, 0.95)
	elif heavy:
		FX.dust(get_parent(), Vector2(global_position.x + facing * 140, ground_y), 8, 1.4)
		Fx.shake(5.0)


func _hit_enemy(e: Node, dmg: float, heavy: bool) -> void:
	var dealt: float = e.take_hit(dmg, facing, 900.0 if heavy else 300.0, heavy)
	if dealt <= 0.0:
		return
	var pos: Vector2 = e.global_position + Vector2(-facing * 30, -120 + e.get("hover") * -1.0)
	FX.sparks(get_parent(), pos, facing, 18 if heavy else 10)
	Sfx.play("hit_heavy" if heavy else "hit")
	_saber_gifts(e, dmg)


func _saber_gifts(e: Node, dmg: float) -> void:
	var g := GameState.gift_god(0)
	if g == "":
		return
	var v := GameState.gift_value(0)
	match g:
		"tengri":
			if randf() * 100.0 < v["chance"]:
				var best: Node = null
				var bd := 360.0
				for o in get_tree().get_nodes_in_group("enemies"):
					if o != e and o.is_alive():
						var d: float = absf(o.global_position.x - e.global_position.x)
						if d < bd:
							bd = d
							best = o
				var target_pos: Vector2 = (best.global_position if best else e.global_position) + Vector2(0, -120)
				FX.lightning(get_parent(), e.global_position + Vector2(0, -260), target_pos)
				if best:
					best.take_hit(v["dmg"], facing, 120.0, false)
				Sfx.play("thunder", -6.0)
		"umai":
			heal(v["heal"])
		"ot_ana":
			e.apply_burn(v["dps"], 3.0)


# ------------------------------------------------------------------ щит
func _start_block(dir: float) -> void:
	# щит сразу в нужную сторону: куда нажато направление, а без него — к угрозе
	if dir != 0.0:
		facing = int(signf(dir))
	else:
		var td := _threat_dir(true)
		if td != 0:
			facing = td
	if state == S.ROLL or state == S.DASH:
		invuln = 0.0   # кувырок прерван щитом — его неуязвимость пропадает, работает блок
	queued = false
	parried_this_raise = false
	raise_until = SHIELD_MIN_UP
	# щит нажат последним — отложенные нажатия кувырка и удара отменяются, иначе они сорвали бы блок
	buf.roll = 0.0
	buf.attack = 0.0
	velocity.x *= 0.3
	_set_state(S.BLOCK)
	block_t = 0.0
	_play("block")
	sprite.stop()


func _threat_dir(any_enemy: bool) -> int:
	## Сторона самой срочной угрозы: враг в замахе, летящий снаряд, а при any_enemy — ближайший враг.
	var best := 1e9
	var side := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.is_alive() or e.state != e.S.ATTACK:
			continue
		var d: float = absf(e.global_position.x - global_position.x)
		if d < 700.0 and d < best:
			best = d
			side = int(signf(e.global_position.x - global_position.x))
	for p in get_tree().get_nodes_in_group("projectiles"):
		if p.reflected:
			continue
		var dx: float = p.global_position.x - global_position.x
		if absf(dx) < 800.0 and signf(p.vel.x) == -signf(dx) and absf(dx) < best:
			best = absf(dx)
			side = int(signf(dx))
	if side == 0 and any_enemy:
		for e in get_tree().get_nodes_in_group("enemies"):
			if not e.is_alive():
				continue
			var d2: float = absf(e.global_position.x - global_position.x)
			if d2 < 500.0 and d2 < best:
				best = d2
				side = int(signf(e.global_position.x - global_position.x))
	return side


# ------------------------------------------------------------------ кувырок и рывок
func _start_roll(dir: float) -> void:
	if dir != 0.0:
		facing = int(signf(dir))
	_set_state(S.ROLL)
	invuln = ROLL_IFRAMES
	roll_cd = roll_cd_max
	trail_t = 0.0
	if GameState.has_gift(1, "umai"):
		var v := GameState.gift_value(1)
		roll_cd = roll_cd_max * (1.0 - v["save"] / 100.0)
		heal(v["heal"])
	_play("roll")
	Sfx.play("roll")


func _start_dash() -> void:
	_set_state(S.DASH)
	dash_hit.clear()
	invuln = 0.35
	_play("dash")


func _end_roll() -> void:
	if GameState.has_gift(1, "tengri"):
		var v := GameState.gift_value(1)
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.is_alive() and absf(e.global_position.x - global_position.x) < 200.0:
				FX.lightning(get_parent(), e.global_position + Vector2(0, -300), e.global_position + Vector2(0, -100))
				e.take_hit(v["dmg"], facing, 200.0, false)
		FX.glow_burst(get_parent(), global_position + Vector2(0, -80), Color(0.6, 0.85, 1.0, 0.8), 1.4)
		Sfx.play("thunder", -6.0)


# ------------------------------------------------------------------ получение урона
func receive_attack(info: Dictionary) -> String:
	## Ответ: "dodged", "parried", "blocked", "hit" или "ignored".
	if state == S.DEAD:
		return "ignored"
	if invuln > 0.0:
		Fx.float_text(get_parent(), global_position + Vector2(0, -260), "уклон", Color(0.56, 0.91, 0.87), 24)
		return "dodged"
	var from_x: float = info.get("from_x", global_position.x + facing)
	var dxa := from_x - global_position.x
	var facing_attacker := absf(dxa) < 40.0 or signf(dxa) == facing   # враг вплотную — щит всё равно закрывает
	var src: Node = info.get("source")
	if state == S.BLOCK and facing_attacker and info.get("parry", true) and block_t < PARRY_WINDOW:
		_perfect_block(src, info)
		return "parried"
	if state == S.BLOCK and facing_attacker and info.get("block", true):
		parried_this_raise = true   # щит принял удар — после него без перезарядки
		var dmg: float = info.get("dmg", 10.0) * 0.25
		_lose_hp(dmg)
		velocity.x = -facing * 380.0
		hurt_flash = 0.5
		FX.sparks(get_parent(), global_position + Vector2(facing * 55, -140), facing, 10)
		Fx.float_text(get_parent(), global_position + Vector2(0, -260), "%d · блок" % roundi(dmg), Color(1, 0.7, 0.65), 26)
		Fx.hitstop(0.06)
		Fx.shake(7.0)
		Sfx.play("block")
		if hp <= 0.0:
			_die()
		return "blocked"
	# без неуязвимости после попадания: каждый удар — урон; герой не разворачивается
	var dmg2: float = info.get("dmg", 10.0)
	_lose_hp(dmg2)
	Fx.float_text(get_parent(), global_position + Vector2(0, -260), str(roundi(dmg2)), Color(1, 0.42, 0.35), 32)
	hurt_flash = 1.0
	var away := signf(global_position.x - from_x)
	if away == 0.0:
		away = -facing
	velocity.x = away * info.get("knock", 400.0)
	Fx.hitstop(0.09)
	Fx.shake(10.0)
	Sfx.play("hurt")
	if hp <= 0.0:
		_die()
	else:
		_set_state(S.HURT)
		_play("hurt")
		_squash(0.92, 1.07)
	return "hit"


func _lower_shield() -> void:
	## Щит опущен: после промаха — перезарядка, если он принял удар — можно сразу снова (иначе не закрыться от двойного удара).
	shield_cd = 0.0 if parried_this_raise else shield_cd_max
	parried_this_raise = false


func _perfect_block(src: Node, info: Dictionary) -> void:
	parried_this_raise = true
	_set_state(S.PARRY)
	_play("parry")
	Fx.hitstop(0.16)
	Fx.shake(12.0)
	Fx.punch(0.05)
	FX.sparks(get_parent(), global_position + Vector2(facing * 60, -140), facing, 24, Color(0.5, 1.0, 0.92))
	FX.glow_burst(get_parent(), global_position + Vector2(facing * 60, -140), Color(0.4, 1.0, 0.9, 0.9), 1.2)
	Fx.float_text(get_parent(), global_position + Vector2(0, -290), "ИДЕАЛЬНЫЙ БЛОК", Color(0.5, 0.96, 0.9), 28)
	Sfx.play("parry")
	var stun_extra := 0.0
	var g := GameState.gift_god(2)
	if g != "":
		var v := GameState.gift_value(2)
		match g:
			"tengri":
				for e in get_tree().get_nodes_in_group("enemies"):
					if e.is_alive() and absf(e.global_position.x - global_position.x) < 280.0:
						FX.lightning(get_parent(), global_position + Vector2(0, -160), e.global_position + Vector2(0, -120))
						e.take_hit(v["dmg"], facing, 300.0, false)
				Sfx.play("thunder", -4.0)
			"umai":
				heal(v["heal"])
				roll_cd = 0.0
			"ot_ana":
				stun_extra = 0.8
				if src and src.has_method("apply_burn"):
					src.apply_burn(v["dps"], 3.0)
	if src and src.has_method("stun"):
		src.stun(stun_extra)


func _lose_hp(d: float) -> void:
	hp = maxf(0.0, hp - d)
	hp_changed.emit(hp, max_hp)


func heal(n: float) -> void:
	if state == S.DEAD or n <= 0.0:
		return
	var before := hp
	hp = minf(max_hp, hp + n)
	if hp > before:
		Fx.float_text(get_parent(), global_position + Vector2(20, -280), "+%d" % roundi(hp - before), Color(0.55, 1.0, 0.55), 24)
		hp_changed.emit(hp, max_hp)


func _die() -> void:
	if GameState.amulet:
		# Тұмар спасает один раз
		GameState.amulet = false
		GameState.gifts_changed.emit()
		hp = max_hp * 0.5
		hp_changed.emit(hp, max_hp)
		invuln = 1.0
		FX.glow_burst(get_parent(), global_position + Vector2(0, -120), Color(1.0, 0.85, 0.4, 0.9), 3.0)
		Fx.float_text(get_parent(), global_position + Vector2(0, -300), "Тұмар уберёг!", Color(1, 0.85, 0.4), 30)
		Sfx.play("revive")
		_to_idle()
		return
	_set_state(S.DEAD)
	invuln = 999.0
	_play("death")
	Fx.hitstop(0.2)
	Fx.shake(14.0)
	Sfx.play("death")
	died.emit()


# ------------------------------------------------------------------ внешнее управление
func set_locked(locked: bool) -> void:
	input_enabled = not locked
	if locked and state != S.DEAD:
		buf.attack = 0.0
		buf.roll = 0.0
		if state == S.BLOCK or state == S.RUN:
			_to_idle()


func walk_to(x: float) -> void:
	walk_target = x


func speed() -> float:
	return absf(velocity.x)


func is_dead() -> bool:
	return state == S.DEAD


func anchor_point() -> Vector2:
	## Мировая точка затылка в текущем кадре — к ней крепится лента.
	var list: Array = Anchors.HAIR.get(String(sprite.animation), [Vector2(-20, -190)])
	var f := clampi(sprite.frame, 0, list.size() - 1)
	var p: Vector2 = list[f]
	p = Vector2(p.x * facing * sx, p.y * sy).rotated(lean)
	return global_position + visual.position + p


# ------------------------------------------------------------------ живая картинка
func _squash(x: float, y: float) -> void:
	sx = x
	sy = y
	vsx = 0.0
	vsy = 0.0


func _bob() -> float:
	if String(sprite.animation) != "run" or state != S.RUN:
		return 0.0
	var steps := (sprite.frame + sprite.frame_progress) / 2.0  # 2 шага за цикл из 4 кадров
	return -10.0 * absf(sin(PI * steps))


func _update_visual(delta: float) -> void:
	# пружина сжатия/растяжения
	vsx += (-(sx - 1.0) * 420.0 - vsx * 20.0) * delta
	sx += vsx * delta
	vsy += (-(sy - 1.0) * 420.0 - vsy * 20.0) * delta
	sy += vsy * delta
	var breath := sin(Time.get_ticks_msec() * 0.0024) if state == S.IDLE else 0.0
	visual.scale = Vector2(sx * (1.0 - 0.006 * breath), sy * (1.0 + 0.012 * breath))
	var target_lean := 0.0
	if state == S.RUN:
		target_lean = 0.1 * facing
	elif state == S.DASH and sprite.frame > 0 and sprite.frame < 3:
		target_lean = 0.1 * facing
	lean = lerpf(lean, target_lean, minf(1.0, delta * 12.0))
	visual.rotation = lean
	visual.position.y = _bob()
	sprite.flip_h = facing < 0
	if state == S.ROLL_REC or state == S.COMBO_REC:
		sprite.pause()
	flash_mat.set_shader_parameter("flash", hurt_flash * 0.7)
	flash_mat.set_shader_parameter("flash_color", Color(1.0, 0.25, 0.15))
	# свечение орнамента — тот же кадр, аддитивно, пульсирует
	glow.animation = sprite.animation
	glow.frame = sprite.frame
	glow.flip_h = sprite.flip_h
	glow.modulate.a = 0.55 + 0.35 * sin(Time.get_ticks_msec() * 0.0031)
	shadow.scale = Vector2(1.0 + visual.position.y / 60.0, 1.0)
	# размытие движения на скорости
	var spd := absf(velocity.x)
	var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	for i in blur.size():
		var b := blur[i]
		b.visible = spd > 380.0 and state != S.DEAD
		if b.visible:
			var k := minf(1.0, (spd - 380.0) / 600.0)
			b.texture = tex
			b.flip_h = sprite.flip_h
			b.position = Vector2(-signf(velocity.x) * (i + 1) * 11.0 * (0.5 + k), 0)
			b.modulate.a = 0.2 - (i + 1) * 0.045
	# шлейф силуэтов: кувырок, рывок и бег
	if state == S.ROLL or (state == S.DASH and sprite.frame > 0 and sprite.frame < 3):
		ghost_t -= delta
		if ghost_t <= 0.0:
			ghost_t = 0.024
			_spawn_ghost(tex, 0.42, 0.26)
	elif state == S.RUN and spd > 500.0:
		run_ghost_t -= delta
		if run_ghost_t <= 0.0:
			run_ghost_t = 0.05
			_spawn_ghost(tex, 0.2, 0.2)


func _spawn_ghost(tex: Texture2D, alpha: float, life: float) -> void:
	var g := Sprite2D.new()
	g.texture = tex
	g.offset = sprite.offset
	g.flip_h = sprite.flip_h
	g.material = ghost_mat
	g.global_position = global_position + visual.position
	g.rotation = lean
	g.scale = visual.scale
	g.modulate.a = alpha
	g.z_index = -1
	get_parent().add_child(g)
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, life)
	tw.tween_callback(g.queue_free)
