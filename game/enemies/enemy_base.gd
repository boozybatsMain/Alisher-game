class_name EnemyBase
extends CharacterBody3D
## Базовый враг Мглы (модуль C). CharacterBody3D (слой 4, маска 1), группы "enemies" и "hurtable_enemy".
## Спрайт-билборд (AnimatedSprite3D, FIXED_Y), тень, полосы HP и брони над головой, хит-флэш, подсветка статусов.
##
## Контракт (ARCHITECTURE.md): take_hit(hit), apply_status(id, params), knock(v), get_facing(), is_dead(),
##   поля type_id, hp, max_hp, armor, max_armor, elite, statuses, hit_radius, facing; сигнал died(enemy).
##
## Сверх контракта (для комнат/даров/HUD):
##   display_name, mods, element, damage, move_speed, is_boss, flying, agile, active (false — ещё появляется),
##   sprite: AnimatedSprite3D, spawn_delay (сек до активации), dirhams_drop (сколько выпадет; 0 — ничего),
##   signal health_changed(hp, max_hp, armor, max_armor), signal attack_started(attack_name)
##   is_stunned(), is_attacking(), interrupt(), launch(), heal(n), kill(hit := null)
## Для наследников (ИИ конкретных типов):
##   _setup(), _try_attack(pl, dist, dy) -> bool, _custom_move(delta, pl) -> bool, pref_dist,
##   begin_attack(name, windup, strike: Callable, recover, anim) + tele_circle/tele_cone/tele_line/tele_ring,
##   strike_circle/strike_cone/strike_line(…, dmg, opts) -> bool (попал ли), deal_player(pl, dmg, opts),
##   jump_to(pos, time, on_land), dash(dir, speed, time, dmg, opts), shockwave(center, max_r, speed, dmg),
##   fire(dir, speed, kind, homing), mist_teleport(pos), player(), fx_parent(), summon(type, pos, mods)
##
## opts для ударов: {"tags": Array ("wide" — подкатом можно проехать, "ground" — прыжком можно избежать,
##   "unblockable"), "knock": float (сила отбрасывания героя), "kind": "normal"|"special", "color": Color}

signal died(enemy: EnemyBase)
signal health_changed(hp: float, max_hp: float, armor: float, max_armor: float)
signal attack_started(attack_name: String)

const GRAVITY := 30.0
const WALL_SLAM_SPEED := 6.0
const FALL_SLAM_HEIGHT := 2.5
const PIT_Y := -8.0
const TELE := 0.5                     ## стандартное время телеграфа
const FRICTION := 22.0
const ELITE_HP := 2.2
const ELITE_SCALE := 1.25
const ARMOR_BREAK_STUN := 1.5
const FLINCH_IMMUNITY := 1.4
const BAR_TEX_W := 64

# ---------------------------------------------------------------- контракт
var type_id := ""
var hp := 30.0
var max_hp := 30.0
var armor := 0.0
var max_armor := 0.0
var elite := false
var statuses := {}
var hit_radius := 0.5
var facing := Vector3(0, 0, 1)

# ---------------------------------------------------------------- сверх контракта
var display_name := ""
var data: Dictionary = {}
var mods: Dictionary = {}
var element := ""
var damage := 10.0
var move_speed := 4.0
var is_boss := false
var flying := false
var agile := false
var active := false
var spawn_delay := 0.6
var dirhams_drop := 0
var pref_dist := 1.6                  ## желаемая дистанция до героя
var attack_cd_range := Vector2(1.4, 2.4)
var tele_mult := 1.0                  ## множитель времени телеграфа (не меньше 0.4 с итогового)
var speed_mult := 1.0                 ## kokbori, фазы боссов
var knock_resist := 1.0               ## 1 — обычное отбрасывание, 0.15 — боссы
var launchable := true
var armor_regen := 0.0                ## сек до восстановления брони после разрушения (0 — не восстанавливается)
var sprite: AnimatedSprite3D
var vis_scale := 1.0
var body_height := 1.6

# ---------------------------------------------------------------- состояние
var _dead := false
var _spawn_t := 0.0
var _atk: Dictionary = {}
var _atk_serial := 0
var _attack_cd := 1.0
var _flinch_imm := 0.0
var _hurt_t := 0.0
var _knock_t := 0.0
var _knock_hit: Hit = null
var _fall_armed := false
var _wall_armed := false
var _air_peak := 0.0
var _was_floor := true
var _launch_t := 0.0
var _launch_hit_t := 0.0
var _jumping := false
var _jump_t := 0.0
var _jump_land: Callable = Callable()
var _jump_cd := 0.0
var _scramble := 0
var _wall_kicks := 0
var _dash_t := 0.0
var _dash_vel := Vector3.ZERO
var _dash_hit_done := false
var _dash_dmg := 0.0
var _dash_opts: Dictionary = {}
var _roll_t := 0.0
var _roll_cd := 0.0
var _scan_t := 0.0
var _flank := 0.0
var _flank_t := 0.0
var _stuck_t := 0.0
var _unreach_t := 0.0
var _progress_pos := Vector3.ZERO
var _progress_t := 0.0
var _flash_t := 0.0
var _flash_col := Color(3, 3, 3)
var _dot_t := 0.0
var _armor_regen_t := 0.0
var _element_t := 0.0
var _trail: Array = []
var _trail_t := 0.0
var _base_tint := Color.WHITE
var _rng := RandomNumberGenerator.new()

var _shadow: Sprite3D
var _outline: AnimatedSprite3D
var _bar_root: Node3D
var _bar_hp: Sprite3D
var _bar_armor: Sprite3D
var _bar_armor_bg: Sprite3D
var _aura: MeshInstance3D
var _col: CollisionShape3D

static var _meta_cache := {}
static var _bar_tex: ImageTexture


# ================================================================ жизненный цикл
func _ready() -> void:
	_rng.randomize()
	add_to_group("enemies")
	add_to_group("hurtable_enemy")
	collision_layer = Combat.LAYER_ENEMY
	collision_mask = Combat.LAYER_WORLD
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	if data.is_empty():
		data = EnemyData.data(type_id if type_id != "" else "wolf")
	if type_id == "":
		type_id = "wolf"
	display_name = EnemyData.display_name(type_id)
	is_boss = bool(data.get("boss", false))
	flying = bool(data.get("flying", false))
	agile = bool(data.get("agile", false))
	elite = bool(mods.get("elite", false)) and not is_boss
	element = String(mods.get("element", ""))
	var hp_mult := float(mods.get("hp_mult", 1.0))
	max_hp = float(data.get("hp", 30.0)) * hp_mult * (ELITE_HP if elite else 1.0)
	hp = max_hp
	max_armor = float(data.get("armor", 0.0)) * hp_mult
	if elite:
		max_armor = maxf(max_armor * 1.5, max_hp * 0.6)
	if element == "zher_su":
		max_armor += max_hp * 0.5
	armor = max_armor
	damage = float(data.get("dmg", 10.0)) * float(mods.get("dmg_mult", 1.0)) * (1.3 if elite else 1.0)
	move_speed = float(data.get("speed", 4.0))
	if element == "kokbori":
		speed_mult *= 1.3
	vis_scale = float(data.get("scale", 1.0)) * (ELITE_SCALE if elite else 1.0) * float(mods.get("scale", 1.0))
	hit_radius = float(data.get("radius", 0.5)) * vis_scale
	body_height = float(data.get("height", 1.6)) * vis_scale
	var dr: Array = data.get("dirhams", [2, 4])
	dirhams_drop = int(mods.get("dirhams", _rng.randi_range(int(dr[0]), int(dr[1])) * (3 if elite else 1)))
	if is_boss:
		knock_resist = 0.15
		launchable = false
	spawn_delay = float(mods.get("spawn_delay", spawn_delay))
	_flank = _rng.randf() * TAU
	_attack_cd = _rng.randf_range(0.6, 1.6)
	_build_body()
	_build_visual()
	_setup()
	_spawn_t = spawn_delay
	if _spawn_t <= 0.0:
		_activate()
	else:
		sprite.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(sprite, "modulate:a", 1.0, _spawn_t)
	health_changed.emit(hp, max_hp, armor, max_armor)


## Переопределяется наследниками (настройка pref_dist, кулдаунов и т.п.).
func _setup() -> void:
	pass


func _activate() -> void:
	active = true
	sprite.modulate.a = 1.0


func _build_body() -> void:
	_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = clampf(hit_radius * 0.7, 0.25, 1.2)
	cap.height = maxf(body_height * 0.85, cap.radius * 2.0 + 0.05)
	_col.shape = cap
	_col.position.y = cap.height * 0.5
	add_child(_col)


func _build_visual() -> void:
	sprite = AnimatedSprite3D.new()
	sprite.name = "Sprite"
	var folder := String(data.get("sprite", "wolf"))
	var path := EnemyData.SPRITES % [folder, folder]
	if ResourceLoader.exists(path):
		sprite.sprite_frames = load(path)
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.pixel_size = float(data.get("pixel", 0.0065))
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.shaded = false
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var m := _sprite_meta(folder)
	sprite.offset = Vector2(0, float(m.get("anchor_y", 0.0)) - float(m.get("frame_h", 0.0)) * 0.5)
	sprite.scale = Vector3.ONE * vis_scale
	_base_tint = data.get("tint", Color.WHITE)
	if element != "":
		_base_tint = _base_tint.lerp(EnemyData.ELEMENT_COLORS.get(element, Color.WHITE), 0.35)
	sprite.modulate = _base_tint
	add_child(sprite)
	play_anim("idle")
	# тень
	_shadow = Sprite3D.new()
	_shadow.name = "Shadow"
	if ResourceLoader.exists("res://assets/fx/shadow.png"):
		_shadow.texture = load("res://assets/fx/shadow.png")
	_shadow.axis = Vector3.AXIS_Y
	_shadow.shaded = false
	_shadow.modulate = Color(0, 0, 0, 0.55)
	_shadow.top_level = true
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _shadow.texture:
		_shadow.pixel_size = hit_radius * 2.6 / maxf(_shadow.texture.get_width(), 1.0)
	add_child(_shadow)
	# золотой контур элитки + аура
	if elite or is_boss:
		_outline = AnimatedSprite3D.new()
		_outline.name = "Outline"
		_outline.sprite_frames = sprite.sprite_frames
		_outline.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		_outline.pixel_size = sprite.pixel_size
		_outline.offset = sprite.offset
		_outline.shaded = false
		_outline.render_priority = -1
		_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_outline.scale = sprite.scale * 1.07
		_outline.modulate = Color(2.4, 1.7, 0.35, 0.75) if elite else Color(0.9, 0.3, 1.6, 0.55)
		add_child(_outline)
	if elite or element != "" or is_boss:
		var col: Color = Color(1.0, 0.78, 0.25) if elite else EnemyData.ELEMENT_COLORS.get(element, Color(0.6, 0.25, 0.9))
		_aura = MeshInstance3D.new()
		_aura.name = "Aura"
		_aura.mesh = EnemyTelegraph.sector_mesh(hit_radius * 1.05, hit_radius * 1.35, 0, TAU, 40)
		var am := StandardMaterial3D.new()
		am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		am.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		am.cull_mode = BaseMaterial3D.CULL_DISABLED
		am.albedo_color = Color(col.r, col.g, col.b, 0.8)
		_aura.material_override = am
		_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_aura.position.y = 0.05
		add_child(_aura)
	_build_bars()


func _build_bars() -> void:
	if _bar_tex == null:
		var img := Image.create(BAR_TEX_W, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_bar_tex = ImageTexture.create_from_image(img)
	_bar_root = Node3D.new()
	_bar_root.name = "Bars"
	_bar_root.position.y = body_height + 0.35
	add_child(_bar_root)
	var w := 1.1 if not elite else 1.5
	var px := w / BAR_TEX_W
	var bg := _bar_sprite(Color(0.05, 0.03, 0.04, 0.85), px * 1.0, 0)
	bg.region_rect = Rect2(0, 0, BAR_TEX_W, 8)
	bg.scale = Vector3(1.04, 1.5, 1)
	bg.offset = Vector2(-BAR_TEX_W * 0.5, -4)
	bg.position = Vector3(0, -px * 2.0, 0)
	_bar_hp = _bar_sprite(Color(0.9, 0.18, 0.15), px, 1)
	if max_armor > 0.0:
		_bar_armor_bg = _bar_sprite(Color(0.05, 0.05, 0.08, 0.85), px, 0)
		_bar_armor_bg.region_rect = Rect2(0, 0, BAR_TEX_W, 8)
		_bar_armor_bg.position.y = px * 9.0
		_bar_armor = _bar_sprite(Color(0.85, 0.9, 1.0), px, 1)
		_bar_armor.position.y = px * 9.0
	_bar_root.visible = false
	_update_bars()


func _bar_sprite(col: Color, px: float, prio: int) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = _bar_tex
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, BAR_TEX_W, 8)
	s.centered = false
	s.offset = Vector2(-BAR_TEX_W * 0.5, -4)
	s.pixel_size = px
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.shaded = false
	s.modulate = col
	s.render_priority = 10 + prio
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar_root.add_child(s)
	return s


func _update_bars() -> void:
	if _bar_root == null:
		return
	_bar_root.visible = not is_boss and not _dead and active and (hp < max_hp or elite or max_armor > 0.0)
	_bar_hp.region_rect = Rect2(0, 0, maxf(0.5, BAR_TEX_W * clampf(hp / max_hp, 0.0, 1.0)), 8)
	if _bar_armor:
		_bar_armor.region_rect = Rect2(0, 0, maxf(0.0, BAR_TEX_W * clampf(armor / maxf(max_armor, 1.0), 0.0, 1.0)), 8)
		_bar_armor.visible = armor > 0.0
		_bar_armor_bg.visible = true


static func _sprite_meta(folder: String) -> Dictionary:
	if _meta_cache.has(folder):
		return _meta_cache[folder]
	var d := {}
	var p := "res://assets/sprites/%s/meta.json" % folder
	if FileAccess.file_exists(p):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary:
			d = parsed
	_meta_cache[folder] = d
	return d


# ================================================================ анимации
func anim_name(logical: String) -> String:
	var anims: Dictionary = data.get("anims", {})
	var n := String(anims.get(logical, logical))
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(n):
		return n
	if sprite and sprite.sprite_frames:
		var fb := String(anims.get("idle", "idle"))
		if sprite.sprite_frames.has_animation(fb):
			return fb
		var names := sprite.sprite_frames.get_animation_names()
		if names.size() > 0:
			return names[0]
	return ""


func play_anim(logical: String, speed := 1.0) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var n := anim_name(logical)
	if n == "":
		return
	sprite.speed_scale = speed * (1.3 if element == "kokbori" else 1.0)
	if sprite.animation != n or not sprite.is_playing():
		sprite.play(n)


# ================================================================ физика и ИИ
func _physics_process(delta: float) -> void:
	if _dead:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)
		if not flying:
			velocity.y -= GRAVITY * delta
		else:
			velocity.y = move_toward(velocity.y, -2.0, 6.0 * delta)
		move_and_slide()
		_update_shadow()
		return
	if not active:
		_spawn_t -= delta
		if not flying:
			velocity.y -= GRAVITY * delta
			move_and_slide()
		if _spawn_t <= 0.0:
			_activate()
		_update_shadow()
		return
	_tick_statuses(delta)
	_timers(delta)
	var pl := player()
	var pre_vel := velocity
	var on_floor := is_on_floor()
	if _knock_t > 0.0 or _launch_t > 0.0:
		_knock_t -= delta
		_launch_t -= delta
		if on_floor and _launch_t <= 0.0:
			velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
			velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)
	elif is_stunned():
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)
		if flying:
			velocity.y = move_toward(velocity.y, 0.0, 10.0 * delta)
	elif _jumping:
		_jump_t += delta
		if is_on_wall() and _jump_t > 0.08:
			_on_wall_in_jump()
	elif _dash_t > 0.0:
		_dash_tick(delta, pl)
	elif _roll_t > 0.0:
		pass
	elif pl != null:
		_ai(delta, pl)
	else:
		_steer(Vector3.ZERO, delta)
	# гравитация
	if flying and _launch_t <= 0.0 and _knock_t <= 0.0:
		pass
	else:
		var g := GRAVITY
		if _launch_t > 0.0:
			g *= 0.45 if _launch_hit_t > 0.0 else 0.8
		velocity.y -= g * delta
	move_and_slide()
	_post_move(pre_vel, on_floor)
	_update_visual(delta, pl)


func _timers(delta: float) -> void:
	_flinch_imm -= delta
	_hurt_t -= delta
	_jump_cd -= delta
	_roll_cd -= delta
	_roll_t -= delta
	_launch_hit_t -= delta
	_flash_t -= delta
	_flank_t -= delta
	if _flank_t <= 0.0:
		_flank_t = _rng.randf_range(3.0, 5.0)
		_flank = wrapf(_flank + _rng.randf_range(-1.2, 1.2), 0.0, TAU)
	if armor_regen > 0.0 and max_armor > 0.0 and armor <= 0.0:
		_armor_regen_t -= delta
		if _armor_regen_t <= 0.0:
			armor = max_armor
			Fx3D.ring(fx_parent(), global_position, hit_radius * 2.5, Color(0.8, 0.9, 1.0), 0.4)
			Fx3D.number(fx_parent(), global_position + Vector3(0, body_height + 0.6, 0), "Броня восстановлена", Color(0.8, 0.9, 1.0), 36)
			_emit_health()


func _ai(delta: float, pl: Node3D) -> void:
	if not _atk.is_empty():
		_attack_tick(delta)
		if not bool(_atk.get("move", false)):
			_steer(Vector3.ZERO, delta, 30.0)
		return
	_attack_cd -= delta
	_element_tick(delta, pl)
	_scan_projectiles(delta)
	if _roll_t > 0.0:
		return
	var to := pl.global_position - global_position
	var dy := to.y
	to.y = 0.0
	var dist := to.length()
	if to.length_squared() > 0.01:
		facing = to.normalized()
	if _attack_cd <= 0.0 and not statuses.has("shock") and _try_attack(pl, dist, dy):
		_attack_cd = _rng.randf_range(attack_cd_range.x, attack_cd_range.y) / (1.3 if element == "kokbori" else 1.0)
		return
	if _custom_move(delta, pl):
		return
	_move_ai(delta, pl, dist, dy)


## Переопределяется: начать атаку, если есть смысл. true — атака начата.
func _try_attack(_pl: Node3D, _dist: float, _dy: float) -> bool:
	return false


## Переопределяется: своя логика движения (true — базовая не нужна).
func _custom_move(_delta: float, _pl: Node3D) -> bool:
	return false


## Обход с флангов: каждая особь держит свой угол вокруг героя, плюс расталкивание с соседями.
func _move_ai(delta: float, pl: Node3D, dist: float, dy: float) -> void:
	var pp := pl.global_position
	var goal := pp + Vector3(cos(_flank), 0, sin(_flank)) * pref_dist
	# если далеко — сначала сближаемся по дуге: цель на полпути смещена к флангу
	var to_goal := goal - global_position
	to_goal.y = 0.0
	var desired := Vector3.ZERO
	if to_goal.length() > 0.4:
		desired = to_goal.normalized()
		# не пробегать сквозь героя: если герой ближе цели и почти по пути — уводим вбок
		var to_p := pp - global_position
		to_p.y = 0.0
		if to_p.length() < to_goal.length() and to_p.length() < pref_dist + 1.0:
			var side := Vector3(-to_p.z, 0, to_p.x).normalized()
			if side.dot(to_goal) < 0.0:
				side = -side
			desired = (desired + side * 1.2).normalized()
	desired += _separation() * 1.3
	if desired.length() > 1.0:
		desired = desired.normalized()
	# ярусы
	if flying:
		var ty := pp.y + 1.2
		velocity.y = move_toward(velocity.y, clampf((ty - global_position.y) * 2.5, -5.0, 5.0), 12.0 * delta)
	elif is_on_floor():
		if dy > 1.4:
			if agile and _jump_cd <= 0.0 and dist < 14.0:
				var dir2 := Vector3(global_position.x - pp.x, 0, global_position.z - pp.z).normalized()
				jump_to(pp + dir2 * 1.4, clampf(0.55 + dist * 0.04, 0.55, 1.0))
				_jump_cd = 1.5
				return
			_unreach_t += delta
		elif dy < -1.4 and agile and _jump_cd <= 0.0 and dist < 10.0 and _rng.randf() < 0.02:
			jump_to(pp + Vector3(cos(_flank), 0, sin(_flank)) * 1.5, 0.6)
			_jump_cd = 2.0
			return
		else:
			_unreach_t = maxf(0.0, _unreach_t - delta)
		if desired != Vector3.ZERO and dy > -1.4 and not _ground_ahead(desired):
			desired = Vector3.ZERO      ## не сваливаться в пропасть, если герой не внизу
			_unreach_t += delta * 0.5
	_steer(desired * move_speed * speed_mult * _slow_mult(), delta)
	# застревание
	_progress_t += delta
	if _progress_t >= 1.5:
		var moved := global_position.distance_to(_progress_pos)
		if desired.length() > 0.5 and moved < 0.5:
			_stuck_t += _progress_t
			if agile and is_on_floor() and not flying:
				jump_to(global_position + desired * 2.5 + Vector3(0, 0, 0), 0.6)
		else:
			_stuck_t = 0.0
		_progress_pos = global_position
		_progress_t = 0.0
	if _unreach_t > 4.5 or _stuck_t > 5.0:
		_unreach_t = 0.0
		_stuck_t = 0.0
		mist_teleport(find_floor_near(pp, 3.0))


func _steer(v: Vector3, delta: float, accel := 22.0) -> void:
	velocity.x = move_toward(velocity.x, v.x, accel * delta)
	velocity.z = move_toward(velocity.z, v.z, accel * delta)


func _slow_mult() -> float:
	var m := 1.0
	if statuses.has("slow"):
		m *= clampf(float(statuses["slow"].get("mult", 0.6)), 0.1, 1.0)
	return m


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not (e is Node3D):
			continue
		var d: Vector3 = global_position - (e as Node3D).global_position
		d.y = 0.0
		var r: float = hit_radius + float(e.get("hit_radius")) + 0.5
		var l := d.length()
		if l < r and l > 0.001:
			push += d / l * (1.0 - l / r)
		elif l <= 0.001:
			push += Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
	return push


func _ground_ahead(dir: Vector3) -> bool:
	var from := global_position + dir.normalized() * (hit_radius + 0.6) + Vector3(0, 0.6, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -3.6, 0), Combat.LAYER_WORLD)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _post_move(pre_vel: Vector3, was_floor: bool) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		_air_peak = maxf(_air_peak, global_position.y)
	# столкновение со стеной при отбрасывании
	if _wall_armed:
		var hs := Vector2(pre_vel.x, pre_vel.z).length()
		for i in get_slide_collision_count():
			var c := get_slide_collision(i)
			var n := c.get_normal()
			if n.y < 0.5 and hs > WALL_SLAM_SPEED:
				_wall_slam(hs, c.get_collider(), n, pre_vel)
				break
	# приземление
	if on_floor and not was_floor:
		var h := _air_peak - global_position.y
		if _fall_armed and h > FALL_SLAM_HEIGHT and not flying:
			var fh := Hit.make(14.0 + 7.0 * h, _knock_hit.source if _knock_hit else null, "fall")
			fh.tags = ["fall_slam"]
			fh.no_boons = true
			fh.position = global_position
			Sfx.play("slam")
			Bus.shake.emit(0.5, 0.2)
			Fx3D.puff(fx_parent(), global_position, Color(0.75, 0.68, 0.58, 0.8), 10)
			_fall_armed = false
			take_hit(fh)
		if _jumping:
			_jumping = false
			_wall_kicks = 0
			_scramble = 0
			Fx3D.puff(fx_parent(), global_position, Color(0.8, 0.72, 0.6, 0.7), 5)
			var cb := _jump_land
			_jump_land = Callable()
			if cb.is_valid():
				cb.call()
		_fall_armed = false
		_air_peak = global_position.y
		if _knock_t <= 0.0:
			_wall_armed = false
	if on_floor:
		_air_peak = global_position.y
		if _knock_t <= 0.0 and _launch_t <= 0.0:
			_wall_armed = false
			_fall_armed = false
	if global_position.y < PIT_Y and not _dead:
		var ph := Hit.make(hp + armor + 1.0, _knock_hit.source if _knock_hit else null, "fall")
		ph.tags = ["pit"]
		ph.pierce_armor = true
		ph.no_boons = true
		take_hit(ph)
	_was_floor = on_floor


func _wall_slam(speed: float, collider: Object, normal: Vector3, pre_vel: Vector3) -> void:
	_wall_armed = false
	var x2 := _knock_hit != null and ("wall_x2" in _knock_hit.tags)
	var amount := (10.0 + (speed - WALL_SLAM_SPEED) * 3.0) * (2.0 if x2 else 1.0)
	var src: Node = _knock_hit.source if _knock_hit else null
	Sfx.play("hit_heavy")
	Bus.shake.emit(0.6, 0.2)
	Bus.hitstop.emit(0.05)
	Fx3D.burst(fx_parent(), global_position + Vector3(0, body_height * 0.5, 0) - normal * hit_radius, Color(0.85, 0.78, 0.65), 12, 5.0)
	Fx3D.puff(fx_parent(), global_position - normal * hit_radius, Color(0.7, 0.65, 0.55, 0.8), 6)
	if collider is Node and ((collider as Node).is_in_group("destructible") or (collider as Node).get_parent() != null and (collider as Node).get_parent().is_in_group("destructible")):
		var dn: Node = collider if (collider as Node).has_method("take_hit") else (collider as Node).get_parent()
		if dn.has_method("take_hit"):
			var dh := Hit.make(amount, src, "wall")
			dh.tags = ["wall_slam"]
			dh.direction = Vector3(pre_vel.x, 0, pre_vel.z).normalized()
			dh.knockback = dh.direction * 4.0
			dh.heavy = true
			dn.take_hit(dh)
	var wh := Hit.make(amount, src, "wall")
	wh.tags = ["wall_slam"]
	wh.armor_mult = 2.0
	wh.no_boons = true
	wh.position = global_position
	velocity = pre_vel.bounce(normal) * 0.25
	velocity.y = maxf(velocity.y, 2.0)
	take_hit(wh)


# ================================================================ визуал
func _update_visual(delta: float, pl: Node3D) -> void:
	# поворот к герою (кроме атаки — направление зафиксировано)
	if pl and _atk.is_empty() and _dash_t <= 0.0 and not is_stunned():
		var to := pl.global_position - global_position
		to.y = 0.0
		if to.length_squared() > 0.04:
			facing = to.normalized()
	var right := _screen_right()
	var sx := facing.dot(right)
	if absf(sx) > 0.1:
		sprite.flip_h = sx < 0.0
	# анимация передвижения
	if _atk.is_empty() and _hurt_t <= 0.0 and not _jumping:
		if is_stunned() or _launch_t > 0.0 or _knock_t > 0.0:
			play_anim("stun")
		elif Vector2(velocity.x, velocity.z).length() > 0.6:
			play_anim("move", clampf(Vector2(velocity.x, velocity.z).length() / maxf(move_speed, 0.1), 0.6, 1.6))
		else:
			play_anim("idle")
	if statuses.has("freeze"):
		sprite.pause()
	# цвет: база × статус, вспышки
	var col := _base_tint
	for id in ["freeze", "burn", "poison", "curse", "shock", "bleed", "slow", "stun"]:
		if statuses.has(id):
			var sc: Color = EnemyData.STATUS_COLORS[id]
			var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
			col = col.lerp(Color(sc.r, sc.g, sc.b, col.a), 0.45 * pulse if id != "freeze" else 0.7)
			break
	if not _atk.is_empty() and String(_atk.get("phase", "")) == "windup":
		var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)
		col = col.lerp(Color(2.4, 0.35, 0.3, col.a), 0.55 * p)
	if _flash_t > 0.0:
		col = Color(_flash_col.r, _flash_col.g, _flash_col.b, col.a)
	col.a = sprite.modulate.a
	sprite.modulate = col
	if _outline:
		_outline.animation = sprite.animation
		_outline.frame = sprite.frame
		_outline.flip_h = sprite.flip_h
	_update_shadow()
	# стихия Умай: горящий след
	if element == "umai":
		_trail_tick(delta, pl)


func _screen_right() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		var b := cam.global_transform.basis.x
		var r := Vector3(b.x, 0, b.z)
		if r.length_squared() > 0.001:
			return r.normalized()
	return Vector3(0.7071, 0, -0.7071)


func _update_shadow() -> void:
	if _shadow == null:
		return
	var from := global_position + Vector3(0, 0.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -12, 0), Combat.LAYER_WORLD)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		_shadow.visible = false
	else:
		_shadow.visible = true
		var gp: Vector3 = r["position"]
		_shadow.global_position = gp + Vector3(0, 0.03, 0)
		var hgt := global_position.y - gp.y
		_shadow.modulate.a = clampf(0.55 - hgt * 0.06, 0.15, 0.55) * sprite.modulate.a


func flash(col := Color(3, 3, 3), time := 0.09) -> void:
	_flash_col = col
	_flash_t = time


# ================================================================ атаки и телеграфы
## Начать атаку: телеграф (добавьте tele_* сразу после вызова), вспышка, звук alert;
## через windup вызывается strike(); затем recover секунд «отдыха».
func begin_attack(attack_name: String, windup: float, strike: Callable, recover := 0.5, anim := "attack") -> void:
	_atk_serial += 1
	_atk = {"name": attack_name, "phase": "windup", "t": 0.0, "windup": maxf(windup * tele_mult, 0.4),
		"recover": recover, "strike": strike, "tele": [], "anim": anim, "serial": _atk_serial, "move": false}
	flash(Color(3.0, 0.4, 0.3), 0.12)
	Sfx.play("alert", -6.0)
	if sprite and sprite.sprite_frames:
		var n := anim_name(anim)
		sprite.play(n)
		sprite.speed_scale = 1.0
		if sprite.sprite_frames.get_frame_count(n) > 2:
			sprite.frame = 1
		sprite.pause()
	attack_started.emit(attack_name)


## Атака продолжается из strike(): цепочка комбо без «отдыха».
func chain_attack(attack_name: String, windup: float, strike: Callable, recover := 0.5, anim := "attack") -> void:
	begin_attack(attack_name, windup, strike, recover, anim)


func windup_time() -> float:
	return float(_atk.get("windup", TELE))


func is_attacking() -> bool:
	return not _atk.is_empty()


func _attack_tick(delta: float) -> void:
	if _jumping or _dash_t > 0.0:
		return
	_atk["t"] = float(_atk["t"]) + delta
	var ph := String(_atk["phase"])
	if ph == "windup" and float(_atk["t"]) >= float(_atk["windup"]):
		var serial := int(_atk["serial"])
		_atk["phase"] = "strike"
		_atk["t"] = 0.0
		if sprite and sprite.sprite_frames:
			var n := anim_name(String(_atk["anim"]))
			if sprite.sprite_frames.get_frame_count(n) > 2:
				sprite.frame = 2
			sprite.play(n)
		var cb: Callable = _atk["strike"]
		if cb.is_valid():
			cb.call()
		if not _atk.is_empty() and int(_atk["serial"]) == serial and String(_atk["phase"]) == "strike":
			_atk["phase"] = "recover"
			_atk["t"] = 0.0
	elif ph == "recover" and float(_atk["t"]) >= float(_atk["recover"]):
		_atk = {}


func _track_tele(n: Node3D) -> Node3D:
	if n and not _atk.is_empty():
		(_atk["tele"] as Array).append(n)
	return n


func tele_circle(pos: Vector3, radius: float, time := -1.0, col := EnemyTelegraph.RED) -> Node3D:
	return _track_tele(EnemyTelegraph.circle(fx_parent(), _ground_at(pos), radius, windup_time() if time < 0.0 else time, col))


func tele_cone(dir: Vector3, radius: float, angle_deg: float, time := -1.0, col := EnemyTelegraph.RED) -> Node3D:
	return _track_tele(EnemyTelegraph.cone(fx_parent(), global_position, dir, radius, angle_deg, windup_time() if time < 0.0 else time, col))


func tele_line(a: Vector3, b: Vector3, width: float, time := -1.0, col := EnemyTelegraph.RED) -> Node3D:
	return _track_tele(EnemyTelegraph.line(fx_parent(), _ground_at(a), b, width, windup_time() if time < 0.0 else time, col))


func tele_ring(pos: Vector3, r_in: float, r_out: float, time := -1.0, col := EnemyTelegraph.RED) -> Node3D:
	return _track_tele(EnemyTelegraph.ring(fx_parent(), _ground_at(pos), r_in, r_out, windup_time() if time < 0.0 else time, col))


func _ground_at(pos: Vector3) -> Vector3:
	var from := pos + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -6.0, 0), Combat.LAYER_WORLD)
	var r := get_world_3d().direct_space_state.intersect_ray(q) if is_inside_tree() else {}
	if r.is_empty():
		return pos
	return r["position"]


## Прервать текущую атаку (оглушение, отбрасывание, смерть) — телеграфы снимаются.
func interrupt() -> void:
	if not _atk.is_empty():
		for t in _atk["tele"]:
			if is_instance_valid(t):
				(t as Node).queue_free()
	_atk = {}
	_dash_t = 0.0


## Попал ли герой в круг (XZ) в момент удара.
func player_in_circle(pl: Node3D, center: Vector3, radius: float, max_dy := 2.0) -> bool:
	if pl == null:
		return false
	var p := pl.global_position
	var r: float = radius + _player_radius(pl)
	if Vector2(p.x - center.x, p.z - center.z).length() > r:
		return false
	return p.y > center.y - 1.2 and p.y < center.y + max_dy


func player_in_cone(pl: Node3D, origin: Vector3, dir: Vector3, radius: float, angle_deg: float, max_dy := 2.0) -> bool:
	if not player_in_circle(pl, origin, radius, max_dy):
		return false
	var v := Vector2(pl.global_position.x - origin.x, pl.global_position.z - origin.z)
	if v.length() < 0.5 + _player_radius(pl):
		return true
	return absf(Vector2(dir.x, dir.z).angle_to(v)) <= deg_to_rad(angle_deg) * 0.5


func player_on_line(pl: Node3D, a: Vector3, b: Vector3, width: float, max_dy := 2.0) -> bool:
	if pl == null:
		return false
	var p := pl.global_position
	if p.y < a.y - 1.2 or p.y > a.y + max_dy:
		return false
	var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
	return q.distance_to(Vector2(p.x, p.z)) <= width * 0.5 + _player_radius(pl)


func _player_radius(pl: Node) -> float:
	var r = pl.get("hit_radius")
	return float(r) if r != null else 0.45


## Учитывает «wide» (подкат) и «ground» (прыжок). true — удар засчитан.
func _evades(pl: Node3D, opts: Dictionary) -> bool:
	var tags: Array = opts.get("tags", [])
	if "wide" in tags and pl.get("sliding") == true:
		Fx3D.number(fx_parent(), pl.global_position + Vector3(0, 1.8, 0), "Подкат!", Color(0.6, 1.0, 0.9), 32)
		return true
	if "ground" in tags and pl is CharacterBody3D and not (pl as CharacterBody3D).is_on_floor():
		return true
	return false


func strike_circle(center: Vector3, radius: float, dmg: float, opts := {}) -> bool:
	var pl := player()
	if player_in_circle(pl, center, radius, float(opts.get("max_dy", 2.0))) and not _evades(pl, opts):
		var o := opts.duplicate()
		if not o.has("from"):
			o["from"] = center
		deal_player(pl, dmg, o)
		return true
	return false


func strike_cone(origin: Vector3, dir: Vector3, radius: float, angle_deg: float, dmg: float, opts := {}) -> bool:
	var pl := player()
	if player_in_cone(pl, origin, dir, radius, angle_deg, float(opts.get("max_dy", 2.0))) and not _evades(pl, opts):
		deal_player(pl, dmg, opts)
		return true
	return false


func strike_line(a: Vector3, b: Vector3, width: float, dmg: float, opts := {}) -> bool:
	var pl := player()
	if player_on_line(pl, a, b, width, float(opts.get("max_dy", 2.0))) and not _evades(pl, opts):
		deal_player(pl, dmg, opts)
		return true
	return false


## Нанести урон герою (через его take_hit). Учитывает dmg_mult/элиту (в damage) и стихию.
func deal_player(pl: Node3D, dmg: float, opts := {}) -> void:
	if pl == null or not pl.has_method("take_hit"):
		return
	var h := Hit.make(dmg, self, String(opts.get("kind", "normal")))
	var from: Vector3 = opts.get("from", global_position)
	var d := pl.global_position - from
	d.y = 0.0
	if d.length_squared() < 0.001:
		d = facing
	h.direction = d.normalized()
	h.position = pl.global_position + Vector3(0, 1.0, 0)
	h.knockback = h.direction * float(opts.get("knock", 4.0)) + Vector3(0, float(opts.get("knock_up", 0.0)), 0)
	h.tags = (opts.get("tags", []) as Array).duplicate()
	h.element = element
	var inv: bool = pl.has_method("invulnerable") and pl.invulnerable()
	match element:
		"tengri":
			h.stun = 0.4
			h.tags.append("shock")
			Fx3D.lightning(fx_parent(), global_position + Vector3(0, body_height * 0.6, 0), pl.global_position + Vector3(0, 1.0, 0), EnemyData.ELEMENT_COLORS["tengri"])
		"umai":
			h.tags.append("burn")
	pl.take_hit(h)
	if not inv:
		if element == "erlik":
			load("res://game/enemies/player_dot.gd").apply(pl, 3.0 * float(mods.get("dmg_mult", 1.0)), 4.0)
		elif element == "umai":
			load("res://game/enemies/player_dot.gd").apply(pl, 2.0 * float(mods.get("dmg_mult", 1.0)), 2.5)


# ================================================================ движение-приёмы
## Параболический прыжок к точке за time секунд. on_land вызывается при приземлении.
func jump_to(pos: Vector3, time := 0.7, on_land: Callable = Callable()) -> void:
	if flying:
		var d := pos - global_position
		velocity = d / maxf(time, 0.1)
		_dash_t = 0.0
		if on_land.is_valid():
			get_tree().create_timer(time, false, true).timeout.connect(func():
				if is_instance_valid(self) and not _dead:
					on_land.call())
		return
	var t := maxf(time, 0.25)
	var d := pos - global_position
	velocity.x = d.x / t
	velocity.z = d.z / t
	velocity.y = (d.y + 0.5 * GRAVITY * t * t) / t
	_jumping = true
	_jump_t = 0.0
	_jump_land = on_land
	_air_peak = global_position.y
	_was_floor = false
	var dd := Vector3(d.x, 0, d.z)
	if dd.length_squared() > 0.01:
		facing = dd.normalized()
	play_anim("leap" if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(anim_name("leap")) and anim_name("leap") != anim_name("idle") else "move")
	Sfx.play("leap", -8.0)
	# move_and_slide не сочтёт нас «на полу» в первый кадр — отрываемся
	global_position.y += 0.05


func _on_wall_in_jump() -> void:
	# карабкаемся на уступ или отскакиваем от стены (ловкие)
	var n := get_wall_normal()
	if velocity.y > -2.0 and _scramble < 2:
		_scramble += 1
		velocity.y = maxf(velocity.y, 7.0)
		return
	if agile and _wall_kicks < 1:
		_wall_kicks += 1
		var hv := Vector3(velocity.x, 0, velocity.z)
		hv = hv.bounce(Vector3(n.x, 0, n.z).normalized()) * 0.8 if hv.length() > 0.1 else Vector3(n.x, 0, n.z) * 5.0
		velocity = Vector3(hv.x, 8.0, hv.z)
		Fx3D.puff(fx_parent(), global_position + Vector3(0, 1.0, 0), Color(0.8, 0.75, 0.65, 0.7), 4)
		Sfx.play("roll", -10.0)


## Рывок (таран): летит dir*speed time секунд, задевает героя один раз.
func dash(dir: Vector3, speed: float, time: float, dmg: float, opts := {}) -> void:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	if flying:
		d = dir.normalized()
	_dash_vel = d * speed
	_dash_t = time
	_dash_hit_done = false
	_dash_dmg = dmg
	_dash_opts = opts
	facing = Vector3(d.x, 0, d.z).normalized()
	Sfx.play("dash_enemy", -4.0)


func _dash_tick(delta: float, pl: Node3D) -> void:
	_dash_t -= delta
	velocity.x = _dash_vel.x
	velocity.z = _dash_vel.z
	if flying:
		velocity.y = _dash_vel.y
	if not _dash_hit_done and pl and player_in_circle(pl, global_position, hit_radius + 0.4, float(_dash_opts.get("max_dy", 2.0))) and not _evades(pl, _dash_opts):
		_dash_hit_done = true
		var o := _dash_opts.duplicate()
		o["from"] = global_position - _dash_vel.normalized()
		deal_player(pl, _dash_dmg, o)
	if is_on_wall():
		_dash_t = 0.0
	if _dash_t <= 0.0:
		velocity.x *= 0.2
		velocity.z *= 0.2
		if not _atk.is_empty():
			_atk["phase"] = "recover"


## Ударная волна по земле: кольцо расширяется со скоростью speed до max_r; герой на земле в кольце — урон.
func shockwave(center: Vector3, max_r: float, speed: float, dmg: float, col := Color(1.0, 0.3, 0.2), opts := {}) -> Node3D:
	var parent := fx_parent()
	if parent == null:
		return null
	var w := Shockwave.new()
	w.enemy = self
	w.max_r = max_r
	w.speed = speed
	w.dmg = dmg
	w.color = col
	w.opts = opts
	parent.add_child(w)
	w.global_position = _ground_at(center) + Vector3(0, 0.05, 0)
	return w


## Выстрел снарядом из «груди» врага.
func fire(dir: Vector3, speed: float, kind := "arrow", homing := 0.0, dmg := -1.0) -> EnemyProjectile:
	var from := global_position + Vector3(0, body_height * 0.55, 0) + Vector3(dir.x, 0, dir.z).normalized() * (hit_radius + 0.2)
	var p := EnemyProjectile.fire(fx_parent(), from, Vector3(dir.x, 0, dir.z), speed, damage if dmg < 0.0 else dmg, self, kind, homing)
	Sfx.play("shoot_arrow" if kind == "arrow" else "shoot_orb", -4.0)
	return p


## Телепорт Мглой (недостижимая цель, бақсы, хан).
func mist_teleport(pos: Vector3) -> void:
	var col := Color(0.35, 0.15, 0.55, 0.85)
	Fx3D.puff(fx_parent(), global_position, col, 10)
	Fx3D.burst(fx_parent(), global_position + Vector3(0, 1.0, 0), Color(0.6, 0.3, 1.0), 10, 3.0)
	Sfx.play("teleport", -6.0)
	global_position = pos
	velocity = Vector3.ZERO
	_jumping = false
	_progress_pos = pos
	Fx3D.puff(fx_parent(), pos, col, 10)
	Fx3D.flash_light(fx_parent(), pos + Vector3(0, 1.0, 0), Color(0.6, 0.3, 1.0), 3.0, 4.0, 0.25)
	flash(Color(1.5, 0.6, 2.5), 0.2)


## Точка на полу рядом с pos (на расстоянии ~dist), без стен; иначе сам pos.
func find_floor_near(pos: Vector3, dist := 3.0) -> Vector3:
	if not is_inside_tree():
		return pos
	var space := get_world_3d().direct_space_state
	var a0 := _rng.randf() * TAU
	for i in 10:
		var a := a0 + i * TAU / 10.0
		var c := pos + Vector3(cos(a), 0, sin(a)) * dist
		var q := PhysicsRayQueryParameters3D.create(c + Vector3(0, 2.0, 0), c + Vector3(0, -4.0, 0), Combat.LAYER_WORLD)
		var r := space.intersect_ray(q)
		if r.is_empty():
			continue
		var gp: Vector3 = r["position"]
		if absf(gp.y - pos.y) > 1.0:
			continue
		if Combat.blocked(get_world_3d(), pos + Vector3(0, 0.8, 0), gp + Vector3(0, 0.8, 0)):
			continue
		return gp + Vector3(0, 0.05, 0)
	return pos + Vector3(0, 0.3, 0)


## Призвать подручного (боссы, бақсы). Возвращает врага или null.
func summon(id: String, pos: Vector3, extra_mods := {}) -> EnemyBase:
	var m := {"hp_mult": float(mods.get("hp_mult", 1.0)), "dmg_mult": float(mods.get("dmg_mult", 1.0)), "dirhams": 0, "summoned": true}
	m.merge(extra_mods, true)
	return EnemyFactory.spawn(id, fx_parent(), pos, m)


# ================================================================ уклонение от стрел
func _scan_projectiles(delta: float) -> void:
	if not agile or flying or _roll_cd > 0.0:
		return
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = 0.12
	for pr in get_tree().get_nodes_in_group("player_projectile"):
		if not (pr is Node3D) or not is_instance_valid(pr):
			continue
		var pp: Vector3 = (pr as Node3D).global_position
		var to := global_position - pp
		to.y = 0.0
		if to.length() > 7.0 or to.length() < 0.8:
			continue
		var v = pr.get("velocity")
		if not (v is Vector3):
			v = pr.get("dir")       ## WeaponProjectile (модуль B): dir + speed
		var dir: Vector3 = (v as Vector3) if v is Vector3 else -(pr as Node3D).global_transform.basis.z
		dir.y = 0.0
		if dir.length_squared() < 0.01:
			continue
		dir = dir.normalized()
		if dir.dot(to.normalized()) < 0.85:
			continue
		if _rng.randf() > 0.65:
			_roll_cd = 1.0
			return
		roll(Vector3(-dir.z, 0, dir.x) * (1.0 if _rng.randf() < 0.5 else -1.0))
		return


## Перекат (уклонение): неуязвим ~0.3 с.
func roll(dir: Vector3) -> void:
	_roll_t = 0.32
	_roll_cd = 2.2
	velocity.x = dir.x * 10.0
	velocity.z = dir.z * 10.0
	Sfx.play("roll", -6.0)
	Fx3D.puff(fx_parent(), global_position, Color(0.8, 0.75, 0.65, 0.6), 4)


# ================================================================ стихии
func _element_tick(delta: float, pl: Node3D) -> void:
	if element != "ai_mergen" or type_id == "archer":
		return
	_element_t += delta
	if _element_t >= 5.0 and _atk.is_empty():
		_element_t = 0.0
		var dir := pl.global_position - global_position
		dir.y = 0.0
		var aim := dir.normalized()
		begin_attack("spirit_arrow", 0.55, func(): fire(aim, 16.0, "arrow", 0.0, damage * 0.7), 0.3)
		tele_line(global_position, global_position + aim * 14.0, 0.5, -1.0, EnemyData.ELEMENT_COLORS["ai_mergen"])


func _trail_tick(delta: float, pl: Node3D) -> void:
	_trail_t -= delta
	if _trail_t <= 0.0 and is_on_floor() and Vector2(velocity.x, velocity.z).length() > 1.0:
		_trail_t = 0.35
		var mi := MeshInstance3D.new()
		mi.mesh = EnemyTelegraph.sector_mesh(0.0, 0.6, 0, TAU, 16)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(1.0, 0.45, 0.1, 0.7)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var par := fx_parent()
		if par:
			par.add_child(mi)
			mi.global_position = global_position + Vector3(0, 0.05, 0)
			var tw := mi.create_tween()
			tw.tween_property(mi, "transparency", 1.0, 3.0)
			tw.tween_callback(mi.queue_free)
			_trail.append({"node": mi, "t": 3.0})
	var hurt := false
	for i in range(_trail.size() - 1, -1, -1):
		var tr: Dictionary = _trail[i]
		tr["t"] = float(tr["t"]) - delta
		if float(tr["t"]) <= 0.0 or not is_instance_valid(tr["node"]):
			_trail.remove_at(i)
			continue
		if pl and not hurt and player_in_circle(pl, (tr["node"] as Node3D).global_position, 0.55, 1.0):
			hurt = true
	if hurt:
		load("res://game/enemies/player_dot.gd").apply(pl, 4.0, 1.0)


# ================================================================ урон
func take_hit(hit: Hit) -> void:
	if _dead or hit == null or not active and hit.kind != "fall":
		return
	if _roll_t > 0.0 and hit.kind in ["normal", "special", "dash"]:
		Fx3D.number(fx_parent(), global_position + Vector3(0, body_height + 0.3, 0), "Уклон", Color(0.8, 0.8, 0.8), 30)
		return
	var amount := maxf(hit.amount, 0.0)
	var was_armored := armor > 0.0
	if was_armored and hit.kind not in ["dot", "fall"]:
		var ad := hit.armor_damage if hit.armor_damage > 0.0 else amount * hit.armor_mult
		armor = maxf(0.0, armor - ad)
		Bus.damage_number.emit(global_position + Vector3(0, body_height + 0.2, 0), ad, "armor")
		if not hit.pierce_armor:
			amount *= 0.25
		if armor <= 0.0:
			_break_armor()
		else:
			Fx3D.burst(fx_parent(), global_position + Vector3(0, body_height * 0.55, 0), Color(0.8, 0.85, 1.0), 5, 3.0, 0.12)
	var armored_now := armor > 0.0
	hp -= amount
	var kind := "normal"
	if hit.kind == "dot":
		kind = "dot"
	elif hit.is_crit:
		kind = "crit"
	elif hit.kind == "special":
		kind = "special"
	if amount > 0.0:
		Bus.damage_number.emit(global_position + Vector3(0, body_height, 0), amount, kind)
	flash(Color(3, 3, 3) if not hit.is_crit else Color(3, 2.6, 1.2), 0.09)
	for st in hit.statuses:
		if st is Dictionary and st.has("id"):
			apply_status(String(st["id"]), st)
	# реакция: отбрасывание, подброс, оглушение, вздрагивание
	if hp > 0.0 and (not armored_now or hit.heavy) and hit.kind not in ["dot", "fall", "wall"]:
		if hit.launch and launchable:
			_knock_hit = hit
			launch()
		elif hit.knockback.length() > 0.1:
			_knock_hit = hit
			knock(hit.knockback)
		if _launch_t > 0.0:
			_launch_hit_t = 0.35
			velocity.y = maxf(velocity.y, 1.5)
			_launch_t = maxf(_launch_t, 0.45)
		if hit.stun > 0.0:
			apply_status("stun", {"time": hit.stun})
		if not is_boss and _flinch_imm <= 0.0 and not _atk.is_empty() and String(_atk.get("phase", "")) == "windup":
			interrupt()
			_flinch_imm = FLINCH_IMMUNITY
			_attack_cd = maxf(_attack_cd, 0.5)
		if _atk.is_empty() and not is_boss:
			_hurt_t = 0.18
			play_anim("hurt")
	elif hit.stun > 0.0 and is_boss and not armored_now:
		apply_status("stun", {"time": hit.stun * 0.3})
	_emit_health()
	Bus.hit_landed.emit(hit, self)
	if hp <= 0.0:
		_die(hit)


func _break_armor() -> void:
	armor = 0.0
	_armor_regen_t = armor_regen
	interrupt()
	apply_status("stun", {"time": ARMOR_BREAK_STUN * (1.6 if is_boss else 1.0)})
	Sfx.play("slam")
	Sfx.play("hit_heavy", -2.0)
	Bus.shake.emit(0.7, 0.25)
	Bus.hitstop.emit(0.08)
	var c := global_position + Vector3(0, body_height * 0.6, 0)
	Fx3D.burst(fx_parent(), c, Color(0.85, 0.9, 1.0), 22, 7.0, 0.22)
	Fx3D.ring(fx_parent(), global_position, hit_radius * 3.0, Color(0.8, 0.9, 1.0), 0.4)
	Fx3D.flash_light(fx_parent(), c, Color(0.8, 0.9, 1.0), 5.0, 5.0, 0.2)
	Fx3D.number(fx_parent(), c + Vector3(0, body_height * 0.6, 0), "Броня сломана!", Color(0.85, 0.92, 1.0), 44)


func _emit_health() -> void:
	_update_bars()
	health_changed.emit(hp, max_hp, armor, max_armor)


## Отбрасывание с физикой: скорость + гравитация + трение; удар о стену > 6 м/с и падение > 2.5 м наносят урон.
func knock(v: Vector3) -> void:
	if _dead:
		return
	var kv := v * knock_resist
	if kv.length() < 0.3:
		return
	if not is_boss:
		interrupt()
	velocity = Vector3(kv.x, maxf(kv.y, velocity.y if kv.y > 0.0 else 0.0), kv.z)
	_knock_t = clampf(0.2 + kv.length() * 0.03, 0.2, 0.8)
	_jumping = false
	_wall_armed = true
	_fall_armed = true
	_air_peak = global_position.y
	if _knock_hit == null:
		_knock_hit = Hit.make(0.0, null, "normal")


## Подброс (апперкот): ~1 с беспомощен в воздухе, при ударах падает медленно.
func launch(up := 10.0) -> void:
	if not launchable or _dead:
		return
	interrupt()
	velocity = Vector3(velocity.x * 0.2, up, velocity.z * 0.2)
	_launch_t = 1.1
	_jumping = false
	_fall_armed = true
	_wall_armed = true
	_air_peak = global_position.y
	global_position.y += 0.05


func heal(n: float) -> void:
	hp = minf(max_hp, hp + n)
	_emit_health()


func kill(hit: Hit = null) -> void:
	if _dead:
		return
	hp = 0.0
	_die(hit)


# ================================================================ статусы
func apply_status(id: String, params: Dictionary) -> void:
	if _dead:
		return
	var p := params.duplicate()
	p.erase("id")
	var cur: Dictionary = statuses.get(id, {})
	match id:
		"burn", "bleed":
			p["dps"] = maxf(float(p.get("dps", 4.0)), float(cur.get("dps", 0.0)))
			p["time"] = maxf(float(p.get("time", 3.0)), float(cur.get("time", 0.0)))
		"poison":
			p["stacks"] = int(cur.get("stacks", 0)) + int(p.get("stacks", 1))
			p["time"] = maxf(float(p.get("time", 6.0)), 6.0)
		"slow":
			p["mult"] = minf(float(p.get("mult", 0.6)), float(cur.get("mult", 1.0)))
			p["time"] = maxf(float(p.get("time", 2.0)), float(cur.get("time", 0.0)))
		"freeze", "stun":
			var t := float(p.get("time", 1.0)) * (0.3 if is_boss and id == "freeze" else 1.0)
			if is_boss and id == "stun" and armor > 0.0:
				return
			p["time"] = maxf(t, float(cur.get("time", 0.0)))
			if not (is_boss and armor > 0.0):
				interrupt()
			if id == "freeze":
				Sfx.play("block", -8.0)
		_:
			p["time"] = maxf(float(p.get("time", 3.0)), float(cur.get("time", 0.0)))
	statuses[id] = p


func is_stunned() -> bool:
	return statuses.has("stun") or statuses.has("freeze")


func _tick_statuses(delta: float) -> void:
	if statuses.is_empty():
		_dot_t = 0.0
		return
	for id in statuses.keys():
		var s: Dictionary = statuses[id]
		s["time"] = float(s.get("time", 0.0)) - delta
		if float(s["time"]) <= 0.0:
			statuses.erase(id)
	_dot_t += delta
	if _dot_t < 0.5:
		return
	_dot_t -= 0.5
	var dmg := 0.0
	var el := ""
	if statuses.has("burn"):
		dmg += float(statuses["burn"].get("dps", 4.0)) * 0.5
		el = "umai"
	if statuses.has("bleed"):
		dmg += float(statuses["bleed"].get("dps", 4.0)) * 0.5
		el = "kokbori"
	if statuses.has("poison"):
		dmg += float(statuses["poison"].get("stacks", 1)) * 2.0 * 0.5
		el = "erlik"
	if statuses.has("shock"):
		dmg += 1.0
		el = "tengri"
	if dmg > 0.0:
		var h := Hit.make(dmg, null, "dot")
		h.element = el
		h.no_boons = true
		h.tags = ["dot"]
		_apply_dot(h)


func _apply_dot(h: Hit) -> void:
	hp -= h.amount
	Bus.damage_number.emit(global_position + Vector3(0, body_height * 0.8, 0), h.amount, "dot")
	_emit_health()
	if hp <= 0.0:
		_die(h)


# ================================================================ смерть
func _die(hit: Hit) -> void:
	if _dead:
		return
	_dead = true
	hp = 0.0
	interrupt()
	_jumping = false
	_knock_t = 0.0
	remove_from_group("enemies")
	remove_from_group("hurtable_enemy")
	collision_layer = 0
	_update_bars()
	Bus.enemy_killed.emit(self, hit)
	Run.register_kill(self)
	died.emit(self)
	_drop_dirhams()
	var folder := String(data.get("sprite", ""))
	var snd := "death_" + folder
	Sfx.play(snd if ResourceLoader.exists("res://assets/sfx/%s.wav" % snd) else "death", -2.0)
	Fx3D.burst(fx_parent(), global_position + Vector3(0, body_height * 0.5, 0), Color(0.45, 0.2, 0.6), 14, 4.0)
	Fx3D.puff(fx_parent(), global_position, Color(0.25, 0.12, 0.35, 0.8), 8)
	play_anim("death")
	if _aura:
		_aura.visible = false
	if _outline:
		_outline.visible = false
	_on_death()
	var tw := create_tween()
	tw.tween_interval(0.7 if not is_boss else 1.6)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.45)
	tw.tween_callback(queue_free)


## Для наследников (боссы — замедление, звук и т.п.).
func _on_death() -> void:
	pass


func _drop_dirhams() -> void:
	if dirhams_drop <= 0:
		return
	Run.add_dirhams(dirhams_drop)
	var par := fx_parent()
	if par == null:
		return
	var pl := player()
	var tex: Texture2D = load("res://assets/fx/soft.png") if ResourceLoader.exists("res://assets/fx/soft.png") else null
	var n := clampi(dirhams_drop / 2, 2, 8)
	for i in n:
		var c := Sprite3D.new()
		c.texture = tex
		c.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		c.shaded = false
		c.pixel_size = 0.0035
		c.modulate = Color(2.2, 1.7, 0.4)
		c.render_priority = 5
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		par.add_child(c)
		var start := global_position + Vector3(0, body_height * 0.6, 0)
		c.global_position = start
		var up := start + Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf_range(1.0, 2.0), _rng.randf_range(-1.2, 1.2))
		var tw := c.create_tween()
		tw.tween_property(c, "global_position", up, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_interval(0.05 * i)
		if pl:
			var plw: WeakRef = weakref(pl)
			var fly := func(k: float) -> void:
				var target := plw.get_ref() as Node3D
				if target and is_instance_valid(c):
					c.global_position = up.lerp(target.global_position + Vector3(0, 1.2, 0), k)
			tw.tween_method(fly, 0.0, 1.0, 0.35).set_ease(Tween.EASE_IN)
		tw.tween_property(c, "scale", Vector3.ZERO, 0.08)
		tw.tween_callback(c.queue_free)
	Fx3D.number(par, global_position + Vector3(0, body_height + 0.5, 0), "+%d ◈" % dirhams_drop, Color(1.0, 0.85, 0.35), 34)


# ================================================================ разное
func get_facing() -> Vector3:
	return facing


func is_dead() -> bool:
	return _dead or hp <= 0.0


func player() -> Node3D:
	if not is_inside_tree():
		return null
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p and p.has_method("is_dead") and p.is_dead():
		return null
	return p


func fx_parent() -> Node:
	var p := get_parent()
	if p == null or not is_instance_valid(p) or not p.is_inside_tree():
		return null
	return p


# ================================================================ ударная волна
class Shockwave extends Node3D:
	var enemy: Node = null
	var max_r := 8.0
	var speed := 9.0
	var dmg := 10.0
	var color := Color(1.0, 0.3, 0.2)
	var opts: Dictionary = {}
	var r := 0.3
	var _done := false
	var _mi: MeshInstance3D
	var _mat: StandardMaterial3D

	func _ready() -> void:
		_mi = MeshInstance3D.new()
		_mi.mesh = EnemyTelegraph.sector_mesh(0.86, 1.0, 0, TAU, 64)
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
		_mi.material_override = _mat
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mi)
		_mi.scale = Vector3(r, 1, r)

	func _physics_process(delta: float) -> void:
		r += speed * delta
		_mi.scale = Vector3(r, 1, r)
		_mat.albedo_color.a = clampf(1.0 - r / max_r, 0.0, 1.0) * 0.9
		if not _done and is_instance_valid(enemy):
			var pl: Node3D = enemy.player()
			if pl:
				var p := pl.global_position
				var d := Vector2(p.x - global_position.x, p.z - global_position.z).length()
				var on_floor: bool = (pl as CharacterBody3D).is_on_floor() if pl is CharacterBody3D else true
				if absf(d - r) < 0.7 and on_floor and absf(p.y - global_position.y) < 1.2:
					_done = true
					var o := opts.duplicate()
					o["from"] = global_position
					o["tags"] = ["ground"]
					enemy.deal_player(pl, dmg, o)
		if r >= max_r:
			queue_free()
