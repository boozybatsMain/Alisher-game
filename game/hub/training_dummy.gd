class_name TrainingDummy
extends Node3D
## «Чучело батыра» — бессмертный манекен в оружейном шатре. Группа "hurtable_enemy" (НЕ "enemies").
## Реагирует на удары (пружинный наклон), отбрасывание (смещается и возвращается), оглушение (звёздочки),
## подброс (launch), статусы (горение/яд/кровотечение тикают уроном и показываются подписью).
## Всплывающие числа урона: Bus.damage_number (kind normal/special/crit/dot) + своя подпись «ОСОБАЯ» / «КРИТ!».
## Над манекеном — DPS за последние 5 секунд (скользящее окно).
##
## API (контракт цели): take_hit(hit), hit_radius, is_dead() == false, get_facing(), apply_status(id, params),
##   knock(velocity), statuses: Dictionary.
## Сверх контракта: dps() -> float, total_window() -> float, hits_count, reset_stats(), last_kind: String

const WINDOW := 5.0

var hit_radius := 0.6
var statuses := {}
var hits_count := 0
var last_kind := ""

var _log: Array = []          ## [[время_с, урон], ...]
var _pivot: Node3D             ## наклоняется пружиной
var _slide: Node3D             ## смещение при отбрасывании / подбросе
var _tilt := Vector2.ZERO      ## наклон (x — вокруг X, y — вокруг Z), рад
var _tilt_v := Vector2.ZERO
var _offset := Vector3.ZERO
var _offset_v := Vector3.ZERO
var _stun := 0.0
var _stars: Node3D
var _dps_label: Label3D
var _status_label: Label3D
var _body_mat: StandardMaterial3D
var _flash := 0.0
var _dot_acc := 0.0
var _time := 0.0


func _ready() -> void:
	add_to_group("hurtable_enemy")
	add_to_group("training_dummy")
	_build()


func _build() -> void:
	# Коллизия-столб, чтобы герой не проходил сквозь.
	HubProps.solid_cyl(self, 0.35, 2.0, Vector3(0, 1.0, 0))
	# Подставка (не качается)
	HubProps.cyl(self, 0.55, 0.65, 0.18, Vector3(0, 0.09, 0), HubProps.WOOD_DARK)
	HubProps.cyl(self, 0.09, 0.09, 0.5, Vector3(0, 0.4, 0), HubProps.WOOD)
	_slide = Node3D.new()
	add_child(_slide)
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 0.55, 0)
	_slide.add_child(_pivot)
	HubProps.cyl(_pivot, 0.07, 0.08, 1.5, Vector3(0, 0.75, 0), HubProps.WOOD)
	_body_mat = HubProps.mat(Color(0.78, 0.64, 0.36)).duplicate()
	# туловище из соломы, перехваченное верёвками
	HubProps.capsule(_pivot, 0.3, 0.95, Vector3(0, 0.95, 0), _body_mat)
	for y in [0.65, 1.0, 1.3]:
		HubProps.torus(_pivot, 0.27, 0.33, Vector3(0, y, 0), HubProps.WOOD_DARK)
	# войлочный халат-накидка (красный с золотом)
	HubProps.cyl(_pivot, 0.33, 0.42, 0.45, Vector3(0, 0.62, 0), HubProps.FELT_RED)
	HubProps.torus(_pivot, 0.38, 0.43, Vector3(0, 0.42, 0), HubProps.GOLD)
	# руки-перекладина
	HubProps.cyl(_pivot, 0.06, 0.06, 1.5, Vector3(0, 1.22, 0), HubProps.WOOD, Vector3(0, 0, 90))
	HubProps.sphere(_pivot, 0.11, Vector3(0.76, 1.22, 0), _body_mat)
	HubProps.sphere(_pivot, 0.11, Vector3(-0.76, 1.22, 0), _body_mat)
	# голова-мешок + шапка батыра (конус с околышем)
	HubProps.sphere(_pivot, 0.23, Vector3(0, 1.62, 0), Color(0.82, 0.72, 0.5))
	HubProps.cyl(_pivot, 0.04, 0.24, 0.32, Vector3(0, 1.92, 0), HubProps.FELT_BROWN)
	HubProps.torus(_pivot, 0.2, 0.27, Vector3(0, 1.79, 0), Color(0.15, 0.12, 0.1))
	# нарисованная мишень на груди (лицо к +Z)
	HubProps.cyl(_pivot, 0.17, 0.17, 0.02, Vector3(0, 1.0, 0.3), HubProps.FELT_WHITE, Vector3(90, 0, 0))
	HubProps.cyl(_pivot, 0.09, 0.09, 0.025, Vector3(0, 1.0, 0.305), HubProps.FELT_RED, Vector3(90, 0, 0))
	# звёздочки оглушения
	_stars = Node3D.new()
	_stars.position = Vector3(0, 2.25, 0)
	_stars.visible = false
	_pivot.add_child(_stars)
	for i in 4:
		var s := HubProps.sphere(_stars, 0.07, Vector3(cos(i * TAU / 4) * 0.35, 0, sin(i * TAU / 4) * 0.35), HubProps.glow_mat(Color(1, 0.9, 0.3), 3.0), Vector3.ONE, 8)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dps_label = HubProps.label(self, "DPS: 0", Vector3(0, 3.15, 0), Color(1, 0.9, 0.6), 44)
	_dps_label.no_depth_test = true
	_status_label = HubProps.label(self, "", Vector3(0, 2.8, 0), Color(0.7, 1, 0.8), 32)
	_status_label.no_depth_test = true
	HubProps.label(self, "Чучело батыра", Vector3(0, -0.1, 0.8), Color(0.85, 0.78, 0.65), 30)


# ================================================================ контракт цели
func is_dead() -> bool:
	return false


func get_facing() -> Vector3:
	return Vector3(0, 0, 1)


func take_hit(hit: Hit) -> void:
	if hit == null:
		return
	var amount := maxf(0.0, hit.amount)
	var kind := "normal"
	if hit.is_crit:
		kind = "crit"
	elif hit.kind == "special":
		kind = "special"
	elif hit.kind == "dot":
		kind = "dot"
	last_kind = kind
	hits_count += 1
	_record(amount)
	# пружинный наклон в сторону удара
	var dir := hit.direction
	if hit.source is Node3D and is_instance_valid(hit.source):
		var d: Vector3 = global_position - (hit.source as Node3D).global_position
		d.y = 0
		if d.length() > 0.05:
			dir = d.normalized()
	dir.y = 0
	if dir.length() < 0.01:
		dir = Vector3(0, 0, -1)
	dir = dir.normalized()
	var power := clampf(0.6 + amount / 25.0, 0.6, 3.0) * (1.6 if hit.heavy else 1.0)
	_tilt_v += Vector2(dir.z, -dir.x) * power * 3.5
	_flash = 0.12
	for st in hit.statuses:
		if st is Dictionary and st.has("id"):
			apply_status(str(st["id"]), st)
	if hit.knockback.length() > 0.1:
		knock(hit.knockback)
	if hit.stun > 0.0:
		apply_status("stun", {"time": hit.stun})
	if hit.launch:
		_offset_v.y = maxf(_offset_v.y, 5.5)
	Bus.hit_landed.emit(hit, self)
	var top := global_position + Vector3(randf_range(-0.3, 0.3), 2.3, randf_range(-0.2, 0.2))
	Bus.damage_number.emit(top, amount, kind)
	_tag(kind, hit)
	if kind != "dot":
		Sfx.play("hit_heavy" if hit.heavy or kind == "crit" else "hit", -4.0)


func apply_status(id: String, params: Dictionary) -> void:
	var p := params.duplicate()
	if id == "poison":
		var prev: Dictionary = statuses.get("poison", {})
		p["stacks"] = int(prev.get("stacks", 0)) + int(params.get("stacks", 1))
		p["time"] = maxf(float(params.get("time", 5.0)), 5.0)
	elif not p.has("time"):
		p["time"] = 3.0
	if id == "stun" or id == "freeze":
		_stun = maxf(_stun, float(p["time"]))
	statuses[id] = p
	_refresh_status()


func knock(velocity: Vector3) -> void:
	var v := velocity
	_offset_v += Vector3(v.x, maxf(v.y, 0.0), v.z) * 0.6
	_tilt_v += Vector2(v.z, -v.x) * 0.35


# ================================================================ DPS
func _record(amount: float) -> void:
	_log.append([_time, amount])
	_trim()


func _trim() -> void:
	while _log.size() > 0 and _time - float(_log[0][0]) > WINDOW:
		_log.pop_front()


func total_window() -> float:
	var s := 0.0
	for e in _log:
		s += float(e[1])
	return s


## Урон в секунду за последние 5 секунд.
func dps() -> float:
	if _log.is_empty():
		return 0.0
	var span := clampf(_time - float(_log[0][0]), 1.0, WINDOW)
	return total_window() / span


func reset_stats() -> void:
	_log.clear()
	hits_count = 0


# ================================================================ кадр
func _process(delta: float) -> void:
	_time += delta
	_trim()
	# пружина наклона
	_tilt_v += (-_tilt * 38.0 - _tilt_v * 5.0) * delta
	_tilt += _tilt_v * delta
	_tilt = _tilt.limit_length(0.9)
	_pivot.rotation = Vector3(_tilt.x, 0, _tilt.y)
	# смещение: возврат на место + подброс с гравитацией
	if _offset.y > 0.0 or _offset_v.y > 0.0:
		_offset_v.y -= 18.0 * delta
	var horiz := Vector3(_offset.x, 0, _offset.z)
	var hv := Vector3(_offset_v.x, 0, _offset_v.z)
	hv += (-horiz * 14.0 - hv * 6.0) * delta
	_offset_v.x = hv.x
	_offset_v.z = hv.z
	_offset += _offset_v * delta
	if _offset.y < 0.0:
		_offset.y = 0.0
		if _offset_v.y < -3.0:
			_tilt_v += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 2.0
		_offset_v.y = 0.0
	_offset = Vector3(clampf(_offset.x, -2.5, 2.5), minf(_offset.y, 3.0), clampf(_offset.z, -2.5, 2.5))
	_slide.position = _offset
	# оглушение — звёздочки
	if _stun > 0.0:
		_stun -= delta
		_stars.visible = true
		_stars.rotation.y += delta * 6.0
	else:
		_stars.visible = false
	# вспышка
	_flash = maxf(0.0, _flash - delta)
	_body_mat.albedo_color = Color(0.78, 0.64, 0.36).lerp(Color(1.6, 1.4, 1.1), _flash / 0.12)
	# статусы
	_tick_statuses(delta)
	if _dps_label:
		_dps_label.text = "DPS: %d   (5 с: %d)" % [roundi(dps()), roundi(total_window())]


func _tick_statuses(delta: float) -> void:
	if statuses.is_empty():
		return
	var dot := 0.0
	var changed := false
	for id in statuses.keys():
		var st: Dictionary = statuses[id]
		st["time"] = float(st.get("time", 0.0)) - delta
		match id:
			"burn", "bleed":
				dot += float(st.get("dps", 4.0))
			"poison":
				dot += float(st.get("stacks", 1)) * 2.0
		if float(st["time"]) <= 0.0:
			statuses.erase(id)
			changed = true
	_dot_acc += delta
	if _dot_acc >= 0.5:
		_dot_acc -= 0.5
		var n := dot * 0.5
		if n > 0.0:
			_record(n)
			Bus.damage_number.emit(global_position + Vector3(randf_range(-0.3, 0.3), 2.0, 0), n, "dot")
	if changed:
		_refresh_status()


const STATUS_NAMES := {"burn": "ГОРЕНИЕ", "poison": "СКВЕРНА", "bleed": "КРОВОТЕЧЕНИЕ", "slow": "ЗАМЕДЛЕНИЕ",
	"freeze": "ЛЁД", "stun": "ОГЛУШЕНИЕ", "curse": "ПРОКЛЯТИЕ", "shock": "РАЗРЯД"}


func _refresh_status() -> void:
	if _status_label == null:
		return
	var parts: Array = []
	for id in statuses:
		var t: String = STATUS_NAMES.get(id, str(id).to_upper())
		if id == "poison":
			t += " ×%d" % int(statuses[id].get("stacks", 1))
		parts.append(t)
	_status_label.text = "  ".join(parts)


## Подпись типа атаки рядом с числом.
func _tag(kind: String, hit: Hit) -> void:
	var text := ""
	var col := Color(1, 1, 1)
	match kind:
		"crit":
			text = "КРИТ!"
			col = Color(1, 0.35, 0.25)
		"special":
			text = "ОСОБАЯ"
			col = Color(0.55, 0.85, 1.0)
		"normal":
			text = "обычная"
			col = Color(0.9, 0.85, 0.75)
		_:
			return
	if hit.from_behind:
		text += " · В СПИНУ"
	var pos := global_position + Vector3(0.9, 2.0, 0)
	if is_inside_tree():
		if Fx3D.number(get_parent(), pos, text, col, 34, 0.9, 0.8) != null:
			return
		var l := HubProps.label(get_parent() as Node3D, text, pos, col, 34)
		l.top_level = true
		l.global_position = pos
		var tw := l.create_tween()
		tw.tween_property(l, "global_position:y", pos.y + 0.9, 0.8)
		tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8)
		tw.tween_callback(l.queue_free)
