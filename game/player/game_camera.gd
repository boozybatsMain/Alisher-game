class_name GameCamera
extends Camera3D
## Изометрическая камера «как в Hades»: наклон 40° вниз, азимут 45° (смотрит с юго-востока на северо-запад),
## перспектива с малым FOV. Плавно следует за героем с опережением по движению, отдаляется/поднимается
## при подъёме героя на ярусы, трясётся по Bus.shake, делает хитстоп по Bus.hitstop.
##
## API:
##   GameCamera.attach(parent: Node, target: Node3D) -> GameCamera   — создать камеру, сделать текущей, сразу встать на цель
##   GameCamera.current_cam(tree) -> GameCamera                       — текущая камера игры (или null)
##   cam.target = node                — кого вести
##   cam.set_bounds(aabb: AABB)       — ограничить точку фокуса границами арены (XZ); set_bounds(AABB()) — снять
##   cam.snap()                       — мгновенно встать на цель (после телепорта)
##   cam.add_shake(strength, secs)    — тряска (то же, что Bus.shake)
##   cam.zoom_mult = 1.0              — доп. множитель дистанции (крупный план домбры в Хабе: 0.4 и т.п.)
##   cam.focus_override = Vector3/null — смотреть на точку вместо героя (кат-сцены, домбра)
##   cam.screen_right() / screen_up() -> Vector3 — оси экрана на плоскости XZ (для управления относительно камеры)
##   GameCamera.PITCH_DEG, YAW_DEG

const PITCH_DEG := 40.0
const YAW_DEG := 45.0
const BASE_DIST := 18.5
const LEAD := 1.6               ## опережение по скорости героя, м
const FOLLOW := 6.0             ## жёсткость следования
const HEIGHT_ZOOM := 0.55       ## на сколько метров отдаляться за метр высоты героя над «полом» комнаты

var target: Node3D = null
var zoom_mult := 1.0
var focus_override = null       ## Vector3 или null
var floor_y := 0.0              ## базовая высота пола арены

var _focus := Vector3.ZERO
var _dist := BASE_DIST
var _lead := Vector3.ZERO
var _bounds := AABB()
var _has_bounds := false
var _shake := 0.0
var _shake_time := 0.0
var _shake_total := 0.0
var _hitstop_until := 0
var _hitstop_active := false


static func attach(parent: Node, p_target: Node3D) -> GameCamera:
	var cam := GameCamera.new()
	cam.name = "GameCamera"
	cam.target = p_target
	parent.add_child(cam)
	cam.make_current()
	cam.snap()
	return cam


static func current_cam(tree: SceneTree) -> GameCamera:
	if tree == null or tree.root == null:
		return null
	var c := tree.root.get_viewport().get_camera_3d()
	return c as GameCamera


func _init() -> void:
	fov = 32.0
	near = 0.5
	far = 220.0
	rotation_degrees = Vector3(-PITCH_DEG, YAW_DEG, 0.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game_camera")
	Bus.shake.connect(add_shake)
	Bus.hitstop.connect(_on_hitstop)
	if target:
		floor_y = target.global_position.y


func set_bounds(aabb: AABB) -> void:
	_bounds = aabb
	_has_bounds = aabb.size != Vector3.ZERO


func screen_right() -> Vector3:
	var r := global_transform.basis.x
	return Vector3(r.x, 0, r.z).normalized()


func screen_up() -> Vector3:
	var f := -global_transform.basis.z
	return Vector3(f.x, 0, f.z).normalized()


func _goal_focus() -> Vector3:
	if focus_override is Vector3:
		return focus_override
	if target == null or not is_instance_valid(target):
		return _focus
	var p := target.global_position + Vector3(0, 0.9, 0)
	var v = target.get("velocity")
	if v is Vector3:
		var hv := Vector3(v.x, 0, v.z)
		_lead = _lead.lerp(hv.limit_length(9.0) / 9.0 * LEAD, 0.08)
	p += _lead
	if _has_bounds:
		p.x = clampf(p.x, _bounds.position.x, _bounds.end.x)
		p.z = clampf(p.z, _bounds.position.z, _bounds.end.z)
	return p


func _goal_dist() -> float:
	var h := 0.0
	if target and is_instance_valid(target) and not (focus_override is Vector3):
		h = maxf(0.0, target.global_position.y - floor_y)
	return (BASE_DIST + h * HEIGHT_ZOOM * 2.0) * zoom_mult


func snap() -> void:
	_focus = _goal_focus()
	_dist = _goal_dist()
	_apply(Vector3.ZERO)


func add_shake(strength: float, secs: float) -> void:
	if strength >= _shake * (_shake_time / maxf(_shake_total, 0.001)):
		_shake = strength
		_shake_time = secs
		_shake_total = secs


func _on_hitstop(secs: float) -> void:
	if secs <= 0.0:
		return
	if Run.time_scale_lock and not _hitstop_active:
		return   # идёт замедление времени (идеальное уклонение) — не перебиваем
	_hitstop_until = maxi(_hitstop_until, Time.get_ticks_msec() + int(secs * 1000.0))
	if not _hitstop_active:
		_hitstop_active = true
		Engine.time_scale = 0.05


func _exit_tree() -> void:
	if _hitstop_active:
		Engine.time_scale = 1.0
		_hitstop_active = false


func _process(delta: float) -> void:
	# delta масштабирована временем; камере нужно реальное время
	var real := delta / maxf(Engine.time_scale, 0.01)
	real = minf(real, 0.1)
	if _hitstop_active and Time.get_ticks_msec() >= _hitstop_until:
		_hitstop_active = false
		if not Run.time_scale_lock:
			Engine.time_scale = 1.0
	if get_tree().paused:
		return
	var k := 1.0 - exp(-FOLLOW * real)
	var gf := _goal_focus()
	# вертикаль ведём мягче — прыжки не должны «качать» кадр
	_focus.x = lerpf(_focus.x, gf.x, k)
	_focus.z = lerpf(_focus.z, gf.z, k)
	_focus.y = lerpf(_focus.y, gf.y, 1.0 - exp(-2.5 * real))
	_dist = lerpf(_dist, _goal_dist(), 1.0 - exp(-2.0 * real))
	var off := Vector3.ZERO
	if _shake_time > 0.0:
		_shake_time -= real
		var s := _shake * clampf(_shake_time / maxf(_shake_total, 0.001), 0.0, 1.0) * 0.12
		off = (global_transform.basis.x * randf_range(-1, 1) + global_transform.basis.y * randf_range(-1, 1)) * s
	_apply(off)


func _apply(off: Vector3) -> void:
	var back := global_transform.basis.z   # камера смотрит вдоль -Z
	global_position = _focus + back * _dist + off
