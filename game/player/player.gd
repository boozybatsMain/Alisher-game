class_name Player
extends CharacterBody3D
## Кайсар — герой. Движение по X/Z относительно камеры, прыжки по ярусам, рывок (заряды, воздушный рывок,
## идеальное уклонение), акробатика в духе Prince of Persia: бег по стене, отскок от стены, удар с отскока,
## зацеп за уступ и подтягивание, подкат, перепрыгивание через врага (Vault).
## Получение урона по контракту (ARCHITECTURE.md), смерть/воскрешение, падение в пропасть.
##
## Контракт (для оружия/врагов/комнат):
##   facing: Vector3 (единичный XZ), aim_dir(), lunge(dir, speed, time), move_lock (сек — бег заблокирован),
##   blocking / block_dir, weapon, sprite, play_anim(name, speed), invulnerable(), teleport_to(pos),
##   take_hit(hit), get_facing(), is_dead(), hit_radius, airborne, wall_kick_time, sliding.
## Сверх контракта:
##   input_enabled: bool / set_input_enabled(on)  — выключить управление (кат-сцена, домбра в Хабе)
##   since_wall_kick() -> float      — секунд с последнего отскока (wall_kick_time — в секундах Time.get_ticks_msec()/1000)
##   dash_charges / max_dash_charges() / is_dashing() / is_wall_running() / is_ledge_grabbing()
##   current_interactable: Node      — ближайший доступный Interactable (или null)
##   respawn_point: Vector3          — последняя безопасная точка (для пропастей); set_safe_point(pos)
##   swap_weapon(id, aspect)         — пересоздать оружие
##   aspect_color() -> Color         — цвет свечения текущего аспекта

const RUN_SPEED := 7.5
const ACCEL_GROUND := 70.0
const ACCEL_AIR := 28.0
const GRAVITY := 30.0
const JUMP_VELOCITY := 12.0
const COYOTE := 0.12
const JUMP_BUFFER := 0.14
const DASH_DIST := 4.4
const DASH_TIME := 0.17
const DASH_RECHARGE := 0.9
const WALL_RUN_TIME := 0.6
const WALL_RUN_SPEED := 9.0
const WALL_KICK_H := 8.5
const WALL_KICK_V := 11.5
const AIR_SPECIAL_WINDOW := 0.6
const LEDGE_TIME := 0.25
const SLIDE_TIME := 0.55
const SLIDE_SPEED := 12.0
const FALL_Y := -10.0
const FALL_DAMAGE := 15.0
const STAND_HEIGHT := 1.7
const SLIDE_HEIGHT := 0.85
const RADIUS := 0.38
const SPRITE_PIXEL := 0.0072
const WEAPON_DATA := "res://game/weapons/weapon_data.gd"

var facing := Vector3(0, 0, 1)
var airborne := false
var wall_kick_time := -100.0
var move_lock := 0.0
var blocking := false
var block_dir := Vector3.ZERO
var weapon: WeaponBase = null
var sprite: AnimatedSprite3D = null
var hit_radius := 0.45
var sliding := false

var input_enabled := true
var dash_charges := 1
var current_interactable: Node = null
var respawn_point := Vector3.ZERO

var _dead := false
var _iframes := 0.0
var _dash_t := 0.0
var _dash_dir := Vector3.ZERO
var _dash_speed := 0.0
var _dash_from := Vector3.ZERO
var _dash_dodged := false
var _ghost_t := 0.0
var _recharge := 0.0
var _air_dash_used := false
var _coyote := 0.0
var _jump_buf := 0.0
var _wall_run_t := 0.0
var _wall_run_n := Vector3.ZERO
var _wall_run_dir := Vector3.ZERO
var _wall_run_used := false
var _wall_kick_cd := 0.0
var _ledge_t := 0.0
var _ledge_block := 0.0
var _slide_t := 0.0
var _slide_dir := Vector3.ZERO
var _vault_t := 0.0
var _vault_vel := Vector3.ZERO
var _vault_turn := Vector3.ZERO
var _dive := false
var _lunge_t := 0.0
var _lunge_vel := Vector3.ZERO
var _stagger := 0.0
var _anim_lock := false
var _air_peak := 0.0
var _air_time := 0.0
var _safe_t := 0.0
var _input_block := 0.0
var _use_mouse := true
var _squash_tw: Tween

@onready var _body: CollisionShape3D = $Body
@onready var _glow: AnimatedSprite3D = get_node_or_null("Glow")
@onready var _shadow: Sprite3D = $Shadow
var _prompt: Label3D
var _capsule: CapsuleShape3D


# ================================================================ жизненный цикл
func _ready() -> void:
	add_to_group("player")
	collision_layer = Combat.LAYER_PLAYER
	collision_mask = Combat.LAYER_WORLD
	floor_snap_length = 0.3
	sprite = $Sprite
	sprite.animation_finished.connect(_on_anim_finished)
	sprite.frame_changed.connect(_sync_glow)
	sprite.animation_changed.connect(_sync_glow)
	_capsule = (_body.shape as CapsuleShape3D).duplicate()
	_body.shape = _capsule
	_set_height(STAND_HEIGHT)
	_shadow.top_level = true
	_prompt = Label3D.new()
	_prompt.name = "Prompt"
	_prompt.top_level = true
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.font_size = 40
	_prompt.outline_size = 10
	_prompt.pixel_size = 0.006
	_prompt.modulate = Color(1, 0.93, 0.75)
	_prompt.outline_modulate = Color(0.08, 0.04, 0.03)
	_prompt.render_priority = 8
	_prompt.visible = false
	add_child(_prompt)
	respawn_point = global_position
	dash_charges = max_dash_charges()
	_create_weapon(Run.weapon if Run.active else Meta.equipped_weapon, Run.aspect if Run.active else Meta.equipped_aspect)
	Bus.weapon_changed.connect(_on_weapon_changed)
	play_anim("idle")
	_anim_lock = false
	Bus.dash_charges_changed.emit.call_deferred(dash_charges, max_dash_charges())
	Bus.hp_changed.emit.call_deferred(Run.hp, Run.max_hp())
	_ensure_camera.call_deferred()


func _ensure_camera() -> void:
	if not is_inside_tree():
		return
	respawn_point = global_position
	if get_viewport().get_camera_3d() == null:
		GameCamera.attach(get_parent(), self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED:
		_input_block = 0.15


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_use_mouse = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.4:
		_use_mouse = false
	elif event is InputEventJoypadButton:
		_use_mouse = false


# ================================================================ оружие
func _create_weapon(id: String, p_aspect: int) -> void:
	if weapon and is_instance_valid(weapon):
		weapon.cancel()
		weapon.queue_free()
		weapon = null
	var w: WeaponBase = WeaponFactory.create(id, p_aspect)
	if w == null:
		return
	w.name = "Weapon"
	if w.id == "":
		w.id = id
	add_child(w)
	w.setup(self, p_aspect)
	weapon = w
	if _glow:
		var c := aspect_color()
		_glow.modulate = Color(c.r, c.g, c.b, 0.55)


func swap_weapon(id: String, p_aspect := 0) -> void:
	_create_weapon(id, p_aspect)


func _on_weapon_changed(id: String, p_aspect: int) -> void:
	if Run.active:
		return
	_create_weapon(id, p_aspect)
	Fx3D.ring(get_parent(), global_position, 1.6, aspect_color(), 0.4)


func aspect_color() -> Color:
	var id := weapon.id if weapon else Meta.equipped_weapon
	var a := weapon.aspect if weapon else 0
	if ResourceLoader.exists(WEAPON_DATA):
		var scr: Script = load(WEAPON_DATA)
		var consts := scr.get_script_constant_map()
		var ws = consts.get("WEAPONS", {})
		if ws is Dictionary and ws.has(id):
			var asp = ws[id].get("aspects", [])
			if asp is Array and a < asp.size() and asp[a] is Dictionary:
				var c = asp[a].get("color", null)
				if c is Color:
					return c
				if c is String and Color.html_is_valid(c):
					return Color.html(c)
	return Color(1.0, 0.75, 0.35)


## Переопределено ли air_special в настоящем оружии (а не пустая заглушка)?
func _weapon_has_air_special() -> bool:
	if weapon == null:
		return false
	var scr: Script = weapon.get_script()
	var re := RegEx.create_from_string("func\\s+air_special\\s*\\([^)]*\\)[^:]*:\\s*(pass)?")
	while scr != null:
		var src := scr.source_code
		if src == "":
			return true   # исходник недоступен (экспорт) — доверяем оружию
		var m := re.search(src)
		if m:
			return m.get_string(1) == ""
		scr = scr.get_base_script()
	return false


# ================================================================ публичное API
func set_input_enabled(on: bool) -> void:
	input_enabled = on
	if not on:
		_jump_buf = 0.0


func max_dash_charges() -> int:
	return maxi(1, int(round(Run.stat("dash_charges"))))


func is_dashing() -> bool:
	return _dash_t > 0.0


func is_wall_running() -> bool:
	return _wall_run_t > 0.0


func is_ledge_grabbing() -> bool:
	return _ledge_t > 0.0


func since_wall_kick() -> float:
	return _now() - wall_kick_time


func get_facing() -> Vector3:
	return facing


func is_dead() -> bool:
	return _dead


func invulnerable() -> bool:
	return _dead or _iframes > 0.0 or _dash_t > 0.0 or _ledge_t > 0.0 or _dive or Run.victory_pending


func set_safe_point(pos: Vector3) -> void:
	respawn_point = pos


## Направление прицела: к курсору мыши на горизонтальной плоскости героя, иначе — по стику/движению/facing.
func aim_dir() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if _use_mouse and cam and DisplayServer.get_name() != "headless":
		var mp := get_viewport().get_mouse_position()
		var from := cam.project_ray_origin(mp)
		var dir := cam.project_ray_normal(mp)
		var plane := Plane(Vector3.UP, global_position.y + 0.9)
		var hit = plane.intersects_ray(from, dir)
		if hit is Vector3:
			var d: Vector3 = hit - global_position
			d.y = 0.0
			if d.length() > 0.2:
				return d.normalized()
	var mv := _move_input()
	if mv.length() > 0.2:
		return mv.normalized()
	return facing


func lunge(dir: Vector3, speed: float, time: float) -> void:
	var d := Vector3(dir.x, 0, dir.z)
	if d.length_squared() < 0.0001:
		d = facing
	d = d.normalized()
	_lunge_vel = d * speed
	_lunge_t = time
	facing = d


func play_anim(anim_name: String, speed := 1.0) -> void:
	if sprite == null or sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim_name):
		return
	sprite.speed_scale = speed
	if sprite.animation != anim_name or not sprite.is_playing():
		sprite.play(anim_name)
	elif not sprite.sprite_frames.get_animation_loop(anim_name):
		sprite.frame = 0
		sprite.play(anim_name)
	_anim_lock = not sprite.sprite_frames.get_animation_loop(anim_name)


func teleport_to(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	_dash_t = 0.0
	_ledge_t = 0.0
	_wall_run_t = 0.0
	var cam := GameCamera.current_cam(get_tree())
	if cam:
		cam.snap()


# ================================================================ урон
func take_hit(hit: Hit) -> void:
	if _dead or hit == null:
		return
	if invulnerable():
		if _dash_t > 0.0 and not _dash_dodged and hit.source != null and hit.source != self:
			_perfect_dodge(hit.source)
		return
	var amount := hit.amount
	var src_pos := global_position - facing
	if hit.source is Node3D and is_instance_valid(hit.source):
		src_pos = (hit.source as Node3D).global_position
	elif hit.position != Vector3.ZERO:
		src_pos = hit.position
	var blocked := false
	if blocking and not ("unblockable" in hit.tags):
		var bd := block_dir if block_dir.length_squared() > 0.01 else facing
		var to_src := src_pos - global_position
		to_src.y = 0.0
		if to_src.length() < 0.05 or bd.normalized().dot(to_src.normalized()) > 0.25:
			blocked = true
			amount *= 0.1 if hit.kind != "special" else 0.2
	amount = Run.modify_incoming(amount, hit.source)
	if blocked:
		Sfx.play("block")
		Fx3D.burst(get_parent(), global_position + Vector3(0, 1.0, 0) + facing * 0.5, Color(1, 0.85, 0.5), 10)
		velocity += hit.knockback * 0.3
	else:
		velocity += Vector3(hit.knockback.x, minf(hit.knockback.y, 6.0), hit.knockback.z)
		_stagger = 0.18 if hit.knockback.length() > 1.0 else 0.08
		if hit.stun > 0.0:   # оглушение от врагов (молния Тенгри): короткое, герою оно неприятно
			_stagger = maxf(_stagger, minf(hit.stun, 0.6))
		Sfx.play("hurt")
		Fx3D.flash_sprite(sprite, Color(3.0, 0.5, 0.4), 0.18)
		if not _anim_lock or sprite.animation == "hurt":
			play_anim("hurt")
		Bus.shake.emit(0.5 + minf(amount, 30.0) / 30.0, 0.25)
		Bus.hitstop.emit(0.05)
	if amount <= 0.0:
		return
	_iframes = maxf(_iframes, 0.45 if not blocked else 0.15)
	Run.set_hp(Run.hp - amount)
	Bus.player_damaged.emit(amount, hit.source)
	Bus.damage_number.emit(global_position + Vector3(0, 2.0, 0), amount, "player")
	if Run.hp <= 0.0:
		_die(hit.source)


func _perfect_dodge(attacker: Node) -> void:
	_dash_dodged = true
	Bus.perfect_dodge.emit(attacker)
	Sfx.play("parry", -4.0)
	Fx3D.ring(get_parent(), global_position, 2.2, Color(0.4, 0.95, 0.9), 0.35)
	Fx3D.flash_sprite(sprite, Color(1.5, 3.0, 3.0), 0.2)
	Fx3D.number(get_parent(), global_position + Vector3(0, 2.3, 0), "Идеально!", Color(0.5, 1, 0.95), 40, 1.0, 0.8)
	if Run.has_kui("korkyt"):
		Run.slowmo(0.3, 1.0)


func _killer_name(src: Node) -> String:
	if src == null or not is_instance_valid(src):
		return ""
	var t = src.get("type_id")
	if t is String and t != "":
		return t
	return str(src.name)


func _die(src: Node) -> void:
	_dead = true
	_dash_t = 0.0
	_wall_run_t = 0.0
	_slide_t = 0.0
	sliding = false
	_set_height(STAND_HEIGHT)
	if weapon:
		weapon.cancel()
	var revived := Run.on_player_death(_killer_name(src))
	if revived:
		_revive()
		return
	Bus.player_died.emit()
	play_anim("death")
	Sfx.play("death")
	Bus.shake.emit(1.2, 0.5)
	Fx3D.burst(get_parent(), global_position + Vector3(0, 1, 0), Color(0.6, 0.1, 0.1), 20)


func _revive() -> void:
	_dead = false
	_iframes = 2.0
	Sfx.play("revive")
	play_anim("parry")
	var root_col := Color(0.55, 1.0, 0.45)
	Fx3D.ring(get_parent(), global_position, 4.5, root_col, 0.6, 0.6)
	Fx3D.ring(get_parent(), global_position, 2.5, Color(1, 0.85, 0.4), 0.45)
	Fx3D.burst(get_parent(), global_position + Vector3(0, 0.5, 0), root_col, 26, 6.0)
	Fx3D.flash_light(get_parent(), global_position, root_col, 6.0, 8.0, 0.6)
	Bus.shake.emit(0.8, 0.4)
	for e in Combat.in_radius(get_tree(), global_position, 4.0, "enemies"):
		if e.has_method("knock"):
			var d: Vector3 = (e as Node3D).global_position - global_position
			d.y = 0.0
			e.knock(d.normalized() * 9.0 + Vector3(0, 4, 0))


# ================================================================ основной цикл
func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if _dead:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		velocity.y -= GRAVITY * delta
		move_and_slide()
		_update_shadow()
		return
	if _ledge_t > 0.0:
		_ledge_t -= delta * 0.25   # страховка: твин сам обнуляет таймер, это лишь защита от зависания
		_update_shadow()
		return   # подтягивание ведёт твин
	var can_input := input_enabled and _input_block <= 0.0
	var mv := _move_input() if can_input else Vector3.ZERO
	var on_floor := is_on_floor()

	# --- кнопки
	if can_input:
		if Input.is_action_just_pressed("jump"):
			_jump_buf = JUMP_BUFFER
		if Input.is_action_just_pressed("dash"):
			_try_dash(mv)
		if Input.is_action_just_pressed("slide"):
			_try_slide(mv)
		_weapon_input()
		if Input.is_action_just_pressed("interact"):
			_try_interact()
	if weapon:
		weapon.tick(delta)

	# --- горизонталь
	var hv := Vector3(velocity.x, 0, velocity.z)
	if _dash_t > 0.0:
		hv = _dash_dir * _dash_speed
		velocity.y = 0.0
		_ghost_t -= delta
		if _ghost_t <= 0.0:
			_ghost_t = 0.045
			_spawn_ghost()
	elif _dive:
		hv = hv.move_toward(facing * 2.0, 20.0 * delta)
	elif _slide_t > 0.0:
		var k := clampf(_slide_t / SLIDE_TIME, 0.0, 1.0)
		hv = _slide_dir * lerpf(5.0, SLIDE_SPEED, k)
		if mv.length() > 0.1:
			_slide_dir = _slide_dir.slerp(mv.normalized(), 2.0 * delta).normalized()
	elif _vault_t > 0.0:
		hv = _vault_vel
	elif _wall_run_t > 0.0:
		hv = _wall_run_dir * WALL_RUN_SPEED - _wall_run_n * 1.5
	elif _lunge_t > 0.0:
		hv = _lunge_vel
	else:
		var speed := RUN_SPEED * Run.stat("move_speed_mult")
		if weapon:
			speed *= weapon.move_mult()
		var want := mv * speed
		if move_lock > 0.0:
			want = Vector3.ZERO
		var acc := ACCEL_GROUND if on_floor else ACCEL_AIR
		if _stagger > 0.0:
			acc *= 0.15
		hv = hv.move_toward(want, acc * delta)
		if mv.length() > 0.1 and move_lock <= 0.0 and (weapon == null or not weapon.is_busy()):
			facing = mv.normalized()

	# --- вертикаль
	if _dash_t > 0.0:
		pass
	elif _dive:
		velocity.y = -26.0
	elif _wall_run_t > 0.0:
		velocity.y = move_toward(velocity.y, -0.5, 10.0 * delta)
	elif not on_floor:
		velocity.y -= GRAVITY * delta
		velocity.y = maxf(velocity.y, -40.0)

	if on_floor:
		_coyote = COYOTE
		_air_dash_used = false
		_wall_run_used = false

	# --- прыжок / отскок
	if _jump_buf > 0.0:
		if (on_floor or _coyote > 0.0) and _wall_run_t <= 0.0:
			if _slide_t > 0.0 and _headroom_blocked():
				pass
			else:
				_jump_buf = 0.0
				_end_slide()
				var e := _vault_target(mv)
				if e:
					_vault(e)
				else:
					_jump()
		elif not on_floor and _wall_kick_cd <= 0.0:
			var n := _wall_run_n if _wall_run_t > 0.0 else _probe_wall(mv)
			if n != Vector3.ZERO:
				_jump_buf = 0.0
				_wall_kick(n)
				hv = Vector3(velocity.x, 0, velocity.z)

	velocity.x = hv.x
	velocity.z = hv.z
	var was_air := airborne
	move_and_slide()
	on_floor = is_on_floor()
	airborne = not on_floor

	# --- воздух: бег по стене, зацеп
	if airborne:
		_air_time += delta
		_air_peak = maxf(_air_peak, global_position.y)
		if _wall_run_t <= 0.0 and _dash_t <= 0.0 and not _dive and _vault_t <= 0.0:
			_try_wall_run(mv)
		if _wall_run_t > 0.0 and _probe_dir(-_wall_run_n, 0.9) == Vector3.ZERO:
			_wall_run_t = 0.0
		if _ledge_block <= 0.0 and _dash_t <= 0.0 and not _dive and velocity.y < 6.0:
			_try_ledge(mv)
	elif was_air:
		_on_land()

	# --- пропасть
	if global_position.y < FALL_Y:
		_fall_out()

	_update_safe_point(delta)
	_update_visual(delta, mv)
	_update_shadow()
	_update_interact()


func _tick_timers(delta: float) -> void:
	_iframes = maxf(0.0, _iframes - delta)
	_coyote -= delta
	_jump_buf -= delta
	_wall_kick_cd -= delta
	_ledge_block -= delta
	_input_block -= delta
	_stagger -= delta
	move_lock = maxf(0.0, move_lock - delta)
	if _lunge_t > 0.0:
		_lunge_t -= delta
	if _vault_t > 0.0:
		_vault_t -= delta
		if _vault_t <= 0.0 and _vault_turn != Vector3.ZERO:
			facing = _vault_turn
			_vault_turn = Vector3.ZERO
	if _wall_run_t > 0.0:
		_wall_run_t -= delta
	if _slide_t > 0.0:
		_slide_t -= delta
		if _slide_t <= 0.0:
			if _headroom_blocked():
				_slide_t = 0.08   # под низким препятствием — едем дальше
			else:
				_end_slide()
	if _dash_t > 0.0:
		_dash_t -= delta
		if _dash_t <= 0.0:
			_end_dash()
	elif _dash_t > -1.0:
		_dash_t -= delta
	# заряды рывка
	var mx := max_dash_charges()
	if dash_charges > mx:
		dash_charges = mx
		Bus.dash_charges_changed.emit(dash_charges, mx)
	if dash_charges < mx:
		_recharge += delta
		if _recharge >= DASH_RECHARGE:
			_recharge = 0.0
			dash_charges += 1
			Bus.dash_charges_changed.emit(dash_charges, mx)
	else:
		_recharge = 0.0


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Ввод движения в мировых координатах XZ относительно камеры.
func _move_input() -> Vector3:
	var v := Input.get_vector("move_left", "move_right", "move_down", "move_up")
	if v.length_squared() < 0.01:
		return Vector3.ZERO
	var right := Vector3.RIGHT
	var fwd := Vector3.FORWARD
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		var b := cam.global_transform.basis
		right = Vector3(b.x.x, 0, b.x.z).normalized()
		fwd = Vector3(-b.z.x, 0, -b.z.z).normalized()
		if fwd.length_squared() < 0.01:
			fwd = Vector3(b.y.x, 0, b.y.z).normalized()
	var d := right * v.x + fwd * v.y
	return d.limit_length(1.0)


func _weapon_input() -> void:
	if weapon == null:
		return
	if Input.is_action_just_pressed("attack"):
		_face_aim()
		weapon.attack_pressed()
	if Input.is_action_just_released("attack"):
		weapon.attack_released()
	if Input.is_action_just_pressed("special"):
		if airborne and since_wall_kick() < AIR_SPECIAL_WINDOW and not _dive:
			_air_special()
		else:
			_face_aim()
			weapon.special_pressed()
	if Input.is_action_just_released("special"):
		weapon.special_released()


## Перед ударом герой разворачивается к прицелу (как в Hades).
func _face_aim() -> void:
	var a := aim_dir()
	if a.length_squared() > 0.01 and _dash_t <= 0.0 and _wall_run_t <= 0.0:
		facing = a.normalized()


# ================================================================ прыжок
func _jump() -> void:
	velocity.y = JUMP_VELOCITY
	_coyote = 0.0
	_air_peak = global_position.y
	_squash(Vector3(0.8, 1.25, 1.0), 0.18)
	Sfx.play("leap", -8.0, 0.12)
	Fx3D.puff(get_parent(), global_position, Color(0.85, 0.78, 0.65, 0.6), 4)


func _vault_target(mv: Vector3) -> Node3D:
	var dir := mv.normalized() if mv.length() > 0.2 else facing
	var best: Node3D = null
	var bd := 1.5
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D) or not is_instance_valid(e):
			continue
		if e.has_method("is_dead") and e.is_dead():
			continue
		var d: Vector3 = (e as Node3D).global_position - global_position
		if absf(d.y) > 1.2:
			continue
		d.y = 0.0
		var dist := d.length()
		var r := 0.5
		var hr = e.get("hit_radius")
		if hr != null:
			r = float(hr)
		if dist - r < bd and dist > 0.05 and d.normalized().dot(dir) > 0.35:
			bd = dist - r
			best = e
	return best


func _vault(e: Node3D) -> void:
	var d := e.global_position - global_position
	d.y = 0.0
	var dist := d.length()
	var dir := d.normalized()
	velocity.y = JUMP_VELOCITY * 1.15
	var air := 2.0 * velocity.y / GRAVITY
	_vault_vel = dir * clampf((dist * 2.0 + 0.9) / air, 3.0, 9.0)
	_vault_t = air * 0.95
	_vault_turn = -dir
	_iframes = maxf(_iframes, 0.4)
	_coyote = 0.0
	_air_peak = global_position.y
	facing = dir
	play_anim("roll", 0.8)
	_squash(Vector3(0.75, 1.3, 1.0), 0.2)
	Sfx.play("leap", -4.0)
	Fx3D.puff(get_parent(), e.global_position + Vector3(0, 1.6, 0), Color(1, 0.95, 0.8, 0.5), 5)


# ================================================================ стены
## Ищет стену рядом: сначала из физики (is_on_wall), затем лучами. Возвращает нормаль стены или ZERO.
func _probe_wall(mv: Vector3) -> Vector3:
	if is_on_wall():
		var n := get_wall_normal()
		n.y = 0.0
		if n.length() > 0.5:
			return n.normalized()
	var dirs: Array[Vector3] = []
	if mv.length() > 0.2:
		dirs.append(mv.normalized())
	dirs.append(facing)
	for i in 8:
		var a := TAU * i / 8.0
		dirs.append(Vector3(cos(a), 0, sin(a)))
	for d in dirs:
		var n := _probe_dir(d, RADIUS + 0.4)
		if n != Vector3.ZERO:
			return n
	return Vector3.ZERO


func _probe_dir(dir: Vector3, length: float, height := 0.9) -> Vector3:
	var r := _ray(global_position + Vector3(0, height, 0), global_position + Vector3(0, height, 0) + dir * length)
	if r.is_empty():
		return Vector3.ZERO
	var n: Vector3 = r["normal"]
	if absf(n.y) > 0.4:
		return Vector3.ZERO
	n.y = 0.0
	return n.normalized()


func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, Combat.LAYER_WORLD, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q)


func _try_wall_run(mv: Vector3) -> void:
	if _wall_run_used or mv.length() < 0.3 or velocity.y < -6.0:
		return
	var n := Vector3.ZERO
	if is_on_wall():
		n = get_wall_normal()
		n.y = 0.0
		if n.length() < 0.5:
			return
		n = n.normalized()
	else:
		return
	var d := mv.normalized()
	var along := d - n * d.dot(n)
	if absf(d.dot(n)) > 0.8 or along.length() < 0.45:
		return   # бежим прямо в стену — это зацеп/отскок, не бег
	_wall_run_used = true
	_wall_run_t = WALL_RUN_TIME
	_wall_run_n = n
	_wall_run_dir = along.normalized()
	facing = _wall_run_dir
	velocity.y = maxf(velocity.y, 2.5)
	play_anim("run", 1.4)
	_anim_lock = false
	Sfx.play("roll", -10.0)


func _wall_kick(n: Vector3) -> void:
	_wall_run_t = 0.0
	_wall_kick_cd = 0.2
	_ledge_block = 0.18
	_wall_run_used = false
	_air_dash_used = false
	velocity = n * WALL_KICK_H + Vector3(0, WALL_KICK_V, 0)
	_stagger = 0.22   # короткое время ввод почти не влияет — отскок читается
	facing = n
	wall_kick_time = _now()
	_air_peak = global_position.y
	Bus.player_wall_kick.emit(global_position)
	Sfx.play("leap", -2.0)
	_squash(Vector3(0.8, 1.2, 1.0), 0.16)
	Fx3D.puff(get_parent(), global_position + Vector3(0, 0.9, 0) - n * RADIUS, Color(0.9, 0.85, 0.75, 0.6), 5)
	play_anim("roll", 1.2)


func _air_special() -> void:
	if weapon and _weapon_has_air_special():
		weapon.air_special()
		return
	# удар с отскока по умолчанию: нисходящий удар (пике) с ударной волной при приземлении
	_dive = true
	_wall_kick_cd = 1.0
	velocity.y = -26.0
	play_anim("attack3", 1.4)
	Sfx.play("swing_heavy")


func _dive_impact() -> void:
	_dive = false
	_wall_kick_cd = 0.0
	_iframes = maxf(_iframes, 0.15)
	var pos := global_position
	Bus.shake.emit(1.4, 0.35)
	Bus.hitstop.emit(0.07)
	Sfx.play("slam")
	Fx3D.ring(get_parent(), pos, 2.8, Color(1, 0.8, 0.4), 0.35, 0.5)
	Fx3D.burst(get_parent(), pos + Vector3(0, 0.3, 0), Color(1, 0.75, 0.35), 18, 6.0)
	Fx3D.flash_light(get_parent(), pos, Color(1, 0.7, 0.3), 5.0, 6.0, 0.25)
	for t in Combat.in_radius(get_tree(), pos, 2.6):
		var h := Hit.make(32.0, self, "special")
		h.armor_mult = 2.5
		h.heavy = true
		h.position = pos
		var d: Vector3 = (t as Node3D).global_position - pos
		d.y = 0.0
		h.direction = d.normalized() if d.length() > 0.05 else facing
		h.knockback = h.direction * 7.0 + Vector3(0, 4.0, 0)
		h.stun = 0.4
		h.tags = ["air_special", "wall_kick", "dive"]
		if weapon:
			h.tags.append("weapon:" + weapon.id)
		Combat.player_hit(t, h)


# ================================================================ зацеп за уступ
func _try_ledge(mv: Vector3) -> void:
	var dir := mv.normalized() if mv.length() > 0.3 else facing
	if dir.length_squared() < 0.01:
		return
	var r1 := _ray(global_position + Vector3(0, 0.6, 0), global_position + Vector3(0, 0.6, 0) + dir * (RADIUS + 0.45))
	if r1.is_empty():
		return
	var n: Vector3 = r1["normal"]
	if absf(n.y) > 0.4:
		return
	n.y = 0.0
	n = n.normalized()
	if dir.dot(-n) < 0.4:
		return
	var p1: Vector3 = r1["position"]
	var top_from := Vector3(p1.x, global_position.y + 2.7, p1.z) - n * 0.35
	var r2 := _ray(top_from, top_from - Vector3(0, 2.1, 0))
	if r2.is_empty():
		return
	var tn: Vector3 = r2["normal"]
	if tn.y < 0.75:
		return
	var top: Vector3 = r2["position"]
	var rise := top.y - global_position.y
	if rise < 0.4 or rise > 2.6:
		return
	# место наверху свободно?
	if not _ray(top + Vector3(0, 0.05, 0), top + Vector3(0, STAND_HEIGHT, 0)).is_empty():
		return
	if not _ray(global_position + Vector3(0, 1.0, 0), Vector3(global_position.x, top.y + 1.0, global_position.z)).is_empty():
		return
	_grab_ledge(Vector3(p1.x, top.y, p1.z) - n * (RADIUS + 0.12), -n)


func _grab_ledge(dest: Vector3, dir: Vector3) -> void:
	_ledge_t = LEDGE_TIME
	_wall_run_t = 0.0
	velocity = Vector3.ZERO
	facing = dir
	play_anim("roll", 1.3)
	Sfx.play("roll", -6.0)
	_squash(Vector3(1.15, 0.85, 1.0), 0.12)
	var up := Vector3(global_position.x, dest.y + 0.06, global_position.z)
	var tw := create_tween()
	tw.tween_property(self, "global_position", up, LEDGE_TIME * 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "global_position", dest + Vector3(0, 0.06, 0), LEDGE_TIME * 0.4)
	tw.tween_callback(func():
		_ledge_t = 0.0
		velocity = Vector3.ZERO
		airborne = false
		_anim_lock = false
		Bus.player_landed.emit(0.0))


# ================================================================ рывок, подкат
func _try_dash(mv: Vector3) -> void:
	if dash_charges <= 0 or _dash_t > 0.0 or _ledge_t > 0.0:
		return
	if airborne and _air_dash_used:
		return
	if airborne:
		_air_dash_used = true
	dash_charges -= 1
	Bus.dash_charges_changed.emit(dash_charges, max_dash_charges())
	_end_slide()
	_dive = false
	_wall_run_t = 0.0
	_vault_t = 0.0
	_lunge_t = 0.0
	if weapon:
		weapon.cancel()
	_dash_dir = mv.normalized() if mv.length() > 0.2 else facing
	facing = _dash_dir
	var mult := Run.stat("dash_speed_mult")
	_dash_speed = DASH_DIST * mult / DASH_TIME
	_dash_t = DASH_TIME
	_dash_from = global_position
	_dash_dodged = false
	_ghost_t = 0.0
	play_anim("dash", 1.4)
	Sfx.play("dash")
	Fx3D.puff(get_parent(), global_position, Color(0.8, 0.9, 0.9, 0.5), 5)


func _end_dash() -> void:
	_iframes = maxf(_iframes, 0.06)
	_anim_lock = false
	var hv := _dash_dir * RUN_SPEED * 0.8
	velocity.x = hv.x
	velocity.z = hv.z
	Bus.player_dashed.emit(_dash_from, global_position)


func _try_slide(mv: Vector3) -> void:
	if not is_on_floor() or _slide_t > 0.0 or _dash_t > 0.0:
		return
	_slide_dir = mv.normalized() if mv.length() > 0.2 else facing
	facing = _slide_dir
	_slide_t = SLIDE_TIME
	sliding = true
	_set_height(SLIDE_HEIGHT)
	if weapon:
		weapon.cancel()
	play_anim("roll", 1.0)
	Sfx.play("roll")
	Fx3D.puff(get_parent(), global_position, Color(0.85, 0.78, 0.65, 0.6), 4)


func _end_slide() -> void:
	if not sliding:
		return
	sliding = false
	_slide_t = 0.0
	_set_height(STAND_HEIGHT)
	_anim_lock = false


func _headroom_blocked() -> bool:
	return not _ray(global_position + Vector3(0, 0.3, 0), global_position + Vector3(0, STAND_HEIGHT + 0.05, 0)).is_empty()


func _set_height(h: float) -> void:
	if _capsule == null:
		return
	_capsule.radius = RADIUS
	_capsule.height = maxf(h, RADIUS * 2.0 + 0.01)
	_body.position = Vector3(0, _capsule.height * 0.5, 0)


func _spawn_ghost() -> void:
	if sprite == null or sprite.sprite_frames == null or not is_inside_tree():
		return
	var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if tex == null:
		return
	var g := Sprite3D.new()
	g.texture = tex
	g.pixel_size = sprite.pixel_size
	g.offset = sprite.offset
	g.flip_h = sprite.flip_h
	g.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	g.shaded = false
	g.modulate = Color(0.45, 0.95, 1.0, 0.45)
	g.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	get_parent().add_child(g)
	g.global_position = sprite.global_position
	g.scale = sprite.scale
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.25)
	tw.tween_callback(g.queue_free)


# ================================================================ приземление, пропасть, безопасная точка
func _on_land() -> void:
	var h := maxf(0.0, _air_peak - global_position.y)
	_air_time = 0.0
	_vault_t = 0.0
	if _vault_turn != Vector3.ZERO:
		facing = _vault_turn
		_vault_turn = Vector3.ZERO
	if _dive:
		_dive_impact()
	_wall_run_t = 0.0
	Bus.player_landed.emit(h)
	if h > 0.6:
		_squash(Vector3(1.25, 0.75, 1.0), 0.14)
		Fx3D.puff(get_parent(), global_position, Color(0.85, 0.78, 0.65, 0.6), 6)
	if h > 3.0:
		Bus.shake.emit(0.4, 0.15)
	if sprite.animation in ["roll", "dash"] and _dash_t <= 0.0:
		_anim_lock = false
	_air_peak = global_position.y


func _fall_out() -> void:
	_dash_t = 0.0
	_dive = false
	_wall_run_t = 0.0
	_end_slide()
	teleport_to(respawn_point + Vector3(0, 0.4, 0))
	_iframes = 1.0
	Sfx.play("hurt")
	Fx3D.flash_sprite(sprite, Color(3, 0.5, 0.4), 0.3)
	Run.set_hp(Run.hp - FALL_DAMAGE)
	Bus.player_damaged.emit(FALL_DAMAGE, null)
	Bus.damage_number.emit(global_position + Vector3(0, 2.0, 0), FALL_DAMAGE, "player")
	if Run.hp <= 0.0:
		_die(null)


func _update_safe_point(delta: float) -> void:
	if not is_on_floor() or sliding or _dash_t > 0.0:
		return
	_safe_t -= delta
	if _safe_t > 0.0:
		return
	_safe_t = 0.25
	# безопасно, если под ногами пол во все стороны на полметра
	for d: Vector3 in [Vector3(0.6, 0, 0), Vector3(-0.6, 0, 0), Vector3(0, 0, 0.6), Vector3(0, 0, -0.6)]:
		var a := global_position + d + Vector3(0, 0.3, 0)
		if _ray(a, a - Vector3(0, 0.8, 0)).is_empty():
			return
	respawn_point = global_position


# ================================================================ визуал
func _update_visual(_delta: float, mv: Vector3) -> void:
	if sprite == null:
		return
	# поворот по экранному X
	var cam := get_viewport().get_camera_3d()
	var right := Vector3.RIGHT
	if cam:
		var b := cam.global_transform.basis.x
		right = Vector3(b.x, 0, b.z).normalized()
	var sx := facing.dot(right)
	if absf(sx) > 0.12:
		sprite.flip_h = sx < 0.0
	if _glow:
		_glow.flip_h = sprite.flip_h
	# мигание в неуязвимости после удара
	if _iframes > 0.0 and _dash_t <= 0.0 and not _dead:
		sprite.visible = int(_iframes * 20.0) % 2 == 0 or _iframes > 1.2
	else:
		sprite.visible = true
	if _anim_lock:
		return
	if _dash_t > 0.0:
		return
	if sliding:
		return
	if airborne:
		if _wall_run_t > 0.0:
			_loco("run", 1.6)
		elif velocity.y > 0.0:
			_loco("run", 0.0, 1)
		else:
			_loco("run", 0.0, 2)
	elif Vector3(velocity.x, 0, velocity.z).length() > 0.6 and mv.length() > 0.1:
		_loco("run", clampf(Vector3(velocity.x, 0, velocity.z).length() / RUN_SPEED, 0.6, 1.5))
	else:
		_loco("idle", 1.0)


func _loco(anim_name: String, speed: float, hold_frame := -1) -> void:
	if not sprite.sprite_frames.has_animation(anim_name):
		return
	if sprite.animation != anim_name:
		sprite.play(anim_name)
	if hold_frame >= 0:
		sprite.pause()
		sprite.frame = mini(hold_frame, sprite.sprite_frames.get_frame_count(anim_name) - 1)
	else:
		if not sprite.is_playing():
			sprite.play(anim_name)
		sprite.speed_scale = speed


func _on_anim_finished() -> void:
	_anim_lock = false


func _sync_glow() -> void:
	if _glow == null or sprite == null:
		return
	if _glow.sprite_frames and _glow.sprite_frames.has_animation(sprite.animation):
		if _glow.animation != sprite.animation:
			_glow.animation = sprite.animation
		_glow.frame = mini(sprite.frame, _glow.sprite_frames.get_frame_count(sprite.animation) - 1)
		_glow.visible = sprite.visible


func _squash(s: Vector3, time: float) -> void:
	if sprite == null:
		return
	if _squash_tw and _squash_tw.is_valid():
		_squash_tw.kill()
	sprite.scale = s
	if _glow:
		_glow.scale = s
	_squash_tw = create_tween().set_parallel(true)
	_squash_tw.tween_property(sprite, "scale", Vector3.ONE, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _glow:
		_squash_tw.tween_property(_glow, "scale", Vector3.ONE, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_shadow() -> void:
	if _shadow == null or not is_inside_tree():
		return
	var r := _ray(global_position + Vector3(0, 0.3, 0), global_position - Vector3(0, 30, 0))
	if r.is_empty():
		_shadow.visible = false
		return
	_shadow.visible = true
	var p: Vector3 = r["position"]
	var h := maxf(0.0, global_position.y - p.y)
	_shadow.global_position = p + Vector3(0, 0.03, 0)
	var k := clampf(1.0 - h / 8.0, 0.35, 1.0)
	_shadow.scale = Vector3(k, k, k)
	_shadow.modulate.a = 0.75 * k


# ================================================================ интерактив
func _update_interact() -> void:
	var best: Node3D = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("interactable"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		if n.get("enabled") == false:
			continue
		var p: Vector3 = (n as Node3D).global_position
		if absf(p.y - global_position.y) > 2.5:
			continue
		var r := 1.6
		var rv = n.get("radius")
		if rv != null:
			r = float(rv)
		var d := Vector2(p.x - global_position.x, p.z - global_position.z).length()
		if d <= r + 0.7 and d < bd:
			if n.has_method("can_activate") and not n.can_activate(self):
				continue
			bd = d
			best = n
	current_interactable = best
	if best and input_enabled and not _dead:
		var pr = best.get("prompt")
		_prompt.text = "[E]  " + (str(pr) if pr != null else "Взаимодействовать")
		_prompt.global_position = best.global_position + Vector3(0, 2.4, 0)
		_prompt.visible = true
	else:
		_prompt.visible = false


func _try_interact() -> void:
	if current_interactable == null or not is_instance_valid(current_interactable):
		return
	if DialogueBox.blocks_input():
		return
	if current_interactable.has_method("activate"):
		current_interactable.activate(self)
