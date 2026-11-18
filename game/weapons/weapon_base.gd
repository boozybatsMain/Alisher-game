class_name WeaponBase
extends Node3D
## Базовое оружие героя (дочерний узел Player). Общая логика: кулдауны, комбо-окно, скорость атаки,
## процедурная 3D-модель с цветом свечения аспекта, дуги/вспышки, звуки, хитстоп и тряска,
## отложенные удары (замах → удар), удар сверху после отскока от стены (air_special),
## комбинации с движением: рывок + обычная (dash_attack) и прыжок + обычная (air_attack) — см. try_move_attack().
## Наследники: sword.gd, spear.gd, shield.gd, bow.gd, gauntlets.gd. Создаются через WeaponFactory.create(id, aspect).

var player: Player = null
var id := ""
var aspect := 0

## --- общие параметры (наследники меняют в _init) ---
var base_damage := 12.0           ## «типичный» урон оружия (для air_special и Даров)
var combo_window := 0.6           ## сколько ждать продолжения серии после удара, с
var glow := Color(0.6, 0.9, 1.0)

## --- состояние ---
var combo := 0                    ## номер следующего удара серии (0..)
var combo_timer := 0.0
var recovery := 0.0               ## до следующей атаки, с
var special_cd := 0.0
var busy := 0.0                   ## герой занят атакой (нельзя прыжок), с
var attack_held := false
var special_held := false
var hold_time := 0.0
var special_hold_time := 0.0
var _move_mult := 1.0
var _move_mult_t := 0.0
var _pending: Array = []          ## [{t, fn}] отложенные действия (обнуляются cancel())
var _last_dash := -100.0
var _air_special_t := -100.0
var _air_attacks := 0             ## воздушных обычных ударов за текущий прыжок (зависание даётся первым двум)
var _buf := ""                    ## буфер ввода: нажали чуть раньше конца восстановления
var _buf_t := 0.0

## --- визуал ---
var pivot: Node3D = null          ## поворачивается к направлению атаки
var model: Node3D = null
var light: OmniLight3D = null
var swing_yaw := 0.0              ## доп. поворот модели при взмахе (рад)
var swing_push := 0.0             ## выдвижение модели вперёд (м)
var hold_pose := Vector3(0.32, 0.95, 0.0)   ## позиция «руки» относительно героя
var _swing_tw: Tween = null
var _model_rest := Vector3.ZERO


func _init() -> void:
	pass


## Сокращение для WeaponFactory.create (см. ARCHITECTURE.md).
static func create(p_id: String, p_aspect := 0) -> WeaponBase:
	return WeaponFactory.create(p_id, p_aspect)


## Вызывается героем после add_child (или до — тогда визуал строится в _ready).
func setup(p_player: Player, p_aspect: int) -> void:
	player = p_player
	aspect = p_aspect
	glow = WeaponData.aspect_color(id, aspect)
	if model:
		WeaponModel.set_glow(model, glow)
	if light:
		light.light_color = glow
	_on_setup()


func _ready() -> void:
	if id == "":
		id = "sword"
	glow = WeaponData.aspect_color(id, aspect)
	_build_visual()
	if not Bus.player_dashed.is_connected(_on_player_dashed):
		Bus.player_dashed.connect(_on_player_dashed)


## Наследникам: доп. настройка после setup().
func _on_setup() -> void:
	pass


func _build_visual() -> void:
	if pivot:
		return
	pivot = Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	model = WeaponModel.build(id, glow)
	pivot.add_child(model)
	light = OmniLight3D.new()
	light.light_color = glow
	light.light_energy = 0.55
	light.omni_range = 1.8
	light.shadow_enabled = false
	light.position = Vector3(0, 0, -0.5)
	pivot.add_child(light)
	_pose_model()
	_model_rest = model.position


## Наследникам: где держать модель внутри pivot (смотрит вдоль -Z).
func _pose_model() -> void:
	model.position = Vector3(0, 0, -0.15)
	model.rotation = Vector3(-0.35, 0, 0)


# ================================================================ API контракта
func attack_pressed() -> void:
	attack_held = true
	hold_time = 0.0


func attack_released() -> void:
	attack_held = false


func special_pressed() -> void:
	special_held = true
	special_hold_time = 0.0


func special_released() -> void:
	special_held = false


func tick(delta: float) -> void:
	recovery = maxf(0.0, recovery - delta)
	if _air_attacks > 0 and player and player.is_on_floor():
		_air_attacks = 0
	special_cd = maxf(0.0, special_cd - delta)
	busy = maxf(0.0, busy - delta)
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0
	if attack_held:
		hold_time += delta
	if special_held:
		special_hold_time += delta
	if _move_mult_t > 0.0:
		_move_mult_t -= delta
		if _move_mult_t <= 0.0:
			_move_mult = 1.0
	# отложенные удары
	if not _pending.is_empty():
		var due: Array = []
		for p in _pending:
			p["t"] -= delta
			if p["t"] <= 0.0:
				due.append(p)
		for p in due:
			_pending.erase(p)
			var fn: Callable = p["fn"]
			if fn.is_valid():
				fn.call()
	if _buf != "":
		_buf_t -= delta
		if _buf_t <= 0.0:
			_buf = ""
		elif recovery <= 0.0:
			var k := _buf
			_buf = ""
			_buffered(k)
	_update_visual(delta)
	_tick(delta)


## Запомнить нажатие, если оружие ещё восстанавливается (0.25 с).
func buffer(kind: String) -> void:
	_buf = kind
	_buf_t = 0.25


## Наследникам: выполнить отложенное нажатие ("attack" / "special").
func _buffered(_kind: String) -> void:
	pass


## Наследникам: логика кадра.
func _tick(_delta: float) -> void:
	pass


func is_busy() -> bool:
	return busy > 0.0


func cancel() -> void:
	_pending.clear()
	_buf = ""
	busy = 0.0
	combo = 0
	combo_timer = 0.0
	_move_mult = 1.0
	_move_mult_t = 0.0
	if player and player.blocking:
		player.blocking = false
	_on_cancel()


func _on_cancel() -> void:
	pass


func move_mult() -> float:
	return _move_mult


## ---------------------------------------------------------------- рывок / прыжок + обычная
const DASH_ATTACK_WINDOW := 0.3   ## сколько после рывка обычная атака считается «рывковой», с
const AIR_HOVER_HITS := 2         ## сколько воздушных ударов за прыжок притормаживают падение


## Вызывать в начале обычной атаки наследника: рывок + обычная → dash_attack(), в воздухе → air_attack().
## true — комбинированный удар выполнен, обычную серию запускать не нужно.
func try_move_attack() -> bool:
	if player == null:
		return false
	if after_dash(DASH_ATTACK_WINDOW) and combo == 0 and dash_attack():
		_last_dash = -100.0   # один рывок — одна рывковая атака
		return true
	if airborne() and air_attack():
		return true
	return false


## Наследникам: атака сразу после рывка. true — выполнена.
func dash_attack() -> bool:
	return false


## Наследникам: обычная атака в воздухе (прыжок + обычная). true — выполнена.
func air_attack() -> bool:
	return false


## Воздушный удар притормаживает падение (первые AIR_HOVER_HITS ударов за прыжок): можно бить в прыжке серией.
func air_hover(up := 1.5) -> void:
	if player == null:
		return
	if _air_attacks < AIR_HOVER_HITS:
		player.velocity.y = maxf(player.velocity.y, up)
	_air_attacks += 1


## Точка под героем, куда направлены воздушные удары (враги на земле под прыгнувшим героем).
func air_point(forward := 1.0) -> Vector3:
	var p := feet() + aim() * forward
	p.y = feet().y - 0.6
	return p


## Удар сверху вниз после отскока от стены: ×1.8 урона, ×2.5 по броне, тяжёлый, радиус 2.2 под героем.
func air_special() -> void:
	var now := _now()
	if now - _air_special_t < 0.5 or player == null:
		return
	_air_special_t = now
	cancel()
	busy = 0.45
	special_cd = maxf(special_cd, 0.3)
	Sfx.play("leap")
	anim("attack_down", 1.4)
	player.velocity = Vector3(player.velocity.x * 0.2, -20.0, player.velocity.z * 0.2)
	swing_to(-1.2, 0.0, 0.12)
	_air_slam_wait(0.0)


func _air_slam_wait(waited: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if waited < 0.6 and not player.is_on_floor():
		schedule(0.03, _air_slam_wait.bind(waited + 0.03))
		return
	var pos := player.global_position
	var h := make_hit(base_damage * 1.8, "special")
	h.armor_mult = 2.5
	h.heavy = true
	h.stun = 0.5
	h.tags.append("air_slam")
	h.tags.append("wall_kick_strike")
	strike_radius(pos, 2.2, h, 7.0, 4.0)
	WeaponFx.ring(self, pos, 2.6, glow, 0.35)
	WeaponFx.flash(self, pos + Vector3(0, 0.4, 0), glow, 2.5, 0.25)
	WeaponFx.light_pop(self, pos, glow, 3.0, 5.0, 0.25)
	Sfx.play("slam")
	Bus.shake.emit(0.5, 0.25)
	Bus.hitstop.emit(0.08)


# ================================================================ помощники для наследников
static func _now() -> float:
	return Time.get_ticks_msec() * 0.001


## Скорость атаки (Дары Көкбөрі, Сандык, кюй).
func aspd() -> float:
	return maxf(0.3, Run.stat("attack_speed_mult"))


func ready_to_attack() -> bool:
	return recovery <= 0.0


## Следующий удар серии; возвращает индекс текущего удара.
func next_combo(length: int) -> int:
	var i := combo % length
	combo = (i + 1) % length
	combo_timer = combo_window / aspd() + 0.2
	return i


func set_recovery(t: float) -> void:
	recovery = t / aspd()
	busy = maxf(busy, recovery * 0.8)


func slow_move(mult: float, t: float) -> void:
	_move_mult = mult
	_move_mult_t = t


func schedule(delay: float, fn: Callable) -> void:
	_pending.append({"t": delay, "fn": fn})


## Направление атаки (XZ, единичное).
func aim() -> Vector3:
	var d := Vector3.FORWARD
	if player:
		d = player.aim_dir()
		if d.length() < 0.1:
			d = player.facing
	d.y = 0.0
	if d.length() < 0.01:
		return Vector3(0, 0, 1)
	return d.normalized()


## Точка удара: грудь героя.
func origin() -> Vector3:
	if player == null:
		return global_position
	return player.global_position + Vector3(0, 0.9, 0)


func feet() -> Vector3:
	return player.global_position if player else global_position


func moving() -> bool:
	if player == null:
		return false
	var v: Vector3 = player.velocity
	return Vector2(v.x, v.z).length() > 1.5


func airborne() -> bool:
	if player == null:
		return false
	return player.airborne or not player.is_on_floor()


## Был ли отскок от стены только что (для удара сверху).
func after_wall_kick() -> bool:
	if player == null:
		return false
	var wk := float(player.wall_kick_time)
	var now := _now()
	return airborne() and now - wk < 0.6 and now - wk >= 0.0


func after_dash(window := 0.3) -> bool:
	return _now() - _last_dash < window


func _on_player_dashed(_from: Vector3, _to: Vector3) -> void:
	_last_dash = _now()


func _player_has_anim(anim: String) -> bool:
	if player == null or player.sprite == null or player.sprite.sprite_frames == null:
		return false
	return player.sprite.sprite_frames.has_animation(anim)


## Логические имена анимаций → кадры спрайта батыра (attack1/2/3, block, parry...).
const ANIM_MAP := {"attack": "attack1", "attack_heavy": "attack3", "special": "attack3", "aim": "attack1",
	"shoot": "attack2", "block": "block", "attack_down": "attack3"}


func anim(name_: String, speed := 1.0) -> void:
	if player == null:
		return
	var n := name_
	if not _player_has_anim(n):
		n = String(ANIM_MAP.get(name_, name_))
		if name_ == "attack" and combo % 2 == 0:
			n = "attack2"
	player.play_anim(n, speed * aspd())


## Новый удар героя с тегами оружия.
func make_hit(amount: float, kind := "normal") -> Hit:
	var h := Hit.make(amount, player, kind)
	h.tags.append("weapon:" + id)
	h.tags.append("aspect:%d" % aspect)
	h.direction = aim()
	h.position = origin()
	return h


## Нанести удар цели (через Дары). Тяжёлые — хитстоп и тряска.
func deal(target: Node, h: Hit) -> void:
	if not is_instance_valid(target):
		return
	if target == player:
		return
	Combat.player_hit(target, h)
	var pos: Vector3 = (target as Node3D).global_position + Vector3(0, 0.9, 0) if target is Node3D else h.position
	WeaponFx.flash(self, pos, glow if not h.is_crit else Color(1, 0.9, 0.4), 1.4 if h.heavy else 0.9, 0.14)
	if h.heavy:
		_fx3d_burst(pos, glow)
		Bus.hitstop.emit(0.07)
		Bus.shake.emit(0.35, 0.18)
		Sfx.play("hit_heavy")
	else:
		Bus.hitstop.emit(0.025)
		Sfx.play("hit", -3.0)


## Общие эффекты game/fx/fx.gd (Fx3D), если модуль есть: искры на тяжёлых ударах.
const FX3D := "res://game/fx/fx.gd"
static var _fx3d_script: Variant = false


func _fx3d_burst(pos: Vector3, color: Color) -> void:
	if typeof(_fx3d_script) == TYPE_BOOL:
		_fx3d_script = load(FX3D) if ResourceLoader.exists(FX3D) else null
	var fx = _fx3d_script
	if fx != null and fx.has_method("burst"):
		var host := WeaponFx.host(self)
		if host:
			fx.call("burst", host, pos, color, 10, 5.0)


func _apply_knock(h: Hit, from: Vector3, target: Node, force: float, up := 0.0) -> void:
	if force <= 0.0 and up <= 0.0:
		return
	var tp: Vector3 = (target as Node3D).global_position
	var d := tp - from
	d.y = 0.0
	if d.length() < 0.05:
		d = h.direction
	h.knockback = d.normalized() * force + Vector3(0, up, 0)


## Удар по конусу. Возвращает число поражённых целей.
func strike_cone(center: Vector3, dir: Vector3, radius: float, angle: float, proto: Hit, knock := 0.0, up := 0.0) -> int:
	var n := 0
	for t in Combat.in_cone(get_tree(), center, dir, radius, angle):
		if t == player or (t.has_method("is_dead") and t.is_dead()):
			continue
		var h := proto.duplicate_hit()
		h.position = (t as Node3D).global_position
		_apply_knock(h, center, t, knock, up)
		deal(t, h)
		n += 1
	return n


func strike_radius(center: Vector3, radius: float, proto: Hit, knock := 0.0, up := 0.0) -> int:
	var n := 0
	for t in Combat.in_radius(get_tree(), center, radius):
		if t == player or (t.has_method("is_dead") and t.is_dead()):
			continue
		var h := proto.duplicate_hit()
		h.position = (t as Node3D).global_position
		_apply_knock(h, center, t, knock, up)
		deal(t, h)
		n += 1
	return n


func strike_line(a: Vector3, b: Vector3, width: float, proto: Hit, knock := 0.0, up := 0.0) -> int:
	var n := 0
	var dir := (b - a)
	dir.y = 0.0
	dir = dir.normalized()
	for t in Combat.along_line(get_tree(), a, b, width):
		if t == player or (t.has_method("is_dead") and t.is_dead()):
			continue
		var h := proto.duplicate_hit()
		h.position = (t as Node3D).global_position
		if knock > 0.0 or up > 0.0:
			h.knockback = dir * knock + Vector3(0, up, 0)
		deal(t, h)
		n += 1
	return n


## Создать снаряд героя в сцене.
func spawn_projectile(pos: Vector3, dir: Vector3, spd: float, h: Hit, vis: Node3D = null) -> WeaponProjectile:
	var p := WeaponProjectile.new()
	p.deal = deal
	var host := WeaponFx.host(self)
	if host == null:
		return null
	host.add_child(p)
	if vis:
		p.set_visual(vis)
	p.launch(pos, dir, spd, h)
	return p


## Отбить вражеские снаряды в радиусе (вихрь меча, блок Абылая).
func reflect_projectiles(center: Vector3, radius: float, front_dir := Vector3.ZERO, max_angle_deg := 360.0) -> int:
	var n := 0
	for pr in get_tree().get_nodes_in_group("enemy_projectile"):
		if not (pr is Node3D) or not is_instance_valid(pr) or not pr.has_method("reflect"):
			continue
		var d: Vector3 = (pr as Node3D).global_position - center
		d.y = 0.0
		if d.length() > radius:
			continue
		if front_dir != Vector3.ZERO and max_angle_deg < 360.0:
			if rad_to_deg(absf(Vector2(front_dir.x, front_dir.z).angle_to(Vector2(d.x, d.z)))) > max_angle_deg * 0.5:
				continue
		var out := d.normalized() if d.length() > 0.05 else aim()
		pr.reflect(player, out)
		n += 1
	if n > 0:
		Sfx.play("parry")
		WeaponFx.flash(self, center, Color(1, 1, 0.8), 2.0, 0.2)
	return n


# ================================================================ визуал
func _update_visual(_delta: float) -> void:
	if pivot == null:
		return
	pivot.position = hold_pose
	var d := aim()
	var yaw := atan2(-d.x, -d.z) + swing_yaw   # -Z модели смотрит в направлении d
	pivot.global_rotation = Vector3(0, yaw, 0)
	if model:
		model.position = _model_rest + Vector3(0, 0, -swing_push)


## Анимация взмаха: от угла a0 к a1 (рад, относительно направления атаки) за time.
func swing_to(a0: float, a1: float, time: float, push := 0.0) -> void:
	if _swing_tw and _swing_tw.is_valid():
		_swing_tw.kill()
	swing_yaw = a0
	swing_push = 0.0
	_swing_tw = create_tween()
	_swing_tw.set_parallel(true)
	_swing_tw.tween_property(self, "swing_yaw", a1, time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if push != 0.0:
		_swing_tw.tween_property(self, "swing_push", push, time * 0.5)
		_swing_tw.chain().tween_property(self, "swing_push", 0.0, time * 1.2)
	_swing_tw.chain().tween_property(self, "swing_yaw", 0.0, 0.25)


func thrust(push: float, time: float) -> void:
	swing_to(0.0, 0.0, time, push)


func show_model(v: bool) -> void:
	if model:
		model.visible = v
	if light:
		light.visible = v
