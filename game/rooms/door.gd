class_name RoomDoor
extends Interactable
## Дверь в следующую комнату (модуль D): каменная арка у северной кромки + символ награды над ней
## (вращающаяся мини-модель, огонь цвета духа/награды, надпись). Заперта (тёмная) до зачистки, затем горит.
## Вход: interact рядом или просто шагнуть в арку → Run.enter_room(room_data).
##
## API: setup(room: Dictionary), unlock(), lock(), room_data, is_open; сигнал entered(room)

signal entered(room: Dictionary)

var room_data: Dictionary = {}
var is_open := false
var biome := 0
var _used := false
var _info: Dictionary = {}
var _portal: MeshInstance3D
var _portal_mat: StandardMaterial3D
var _light: OmniLight3D
var _flames: Array[Sprite3D] = []
var _label: Label3D
var _sub: Label3D
var _icon: Node3D
var _threshold: Area3D
var _t := 0.0


func setup(room: Dictionary) -> void:
	room_data = room
	_info = RoomRewards.info(room)
	prompt = "Войти: " + String(_info["title"])


func _ready() -> void:
	radius = 2.2
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = radius
	cs.shape = sh
	cs.position = Vector3(0, 1.0, 1.0)
	add_child(cs)
	super._ready()
	if _info.is_empty():
		_info = RoomRewards.info(room_data)
	_build()
	lock()


func _build() -> void:
	var stones: Array[Color] = [Color(0.45, 0.4, 0.36), Color(0.3, 0.36, 0.36), Color(0.25, 0.22, 0.28)]
	var stone := RoomUtil.mat(stones[clampi(biome, 0, 2)], 0.9)
	var dark := RoomUtil.mat(Color(0.16, 0.13, 0.12), 1.0)
	var col: Color = _info["color"]
	# арка: два столба, перемычка, ступень
	for sx: float in [-1.7, 1.7]:
		var body := RoomUtil.solid_box(self, Vector3(sx, 2.1, 0), Vector3(0.8, 4.2, 0.9), stone)
		RoomUtil.mesh(body, RoomUtil.box_mesh(Vector3(0.95, 0.3, 1.0)), Vector3(0, -1.95, 0), stone)
		RoomUtil.mesh(body, RoomUtil.box_mesh(Vector3(0.06, 3.0, 0.06)), Vector3(sx * -0.2, 0, 0.46), RoomUtil.mat(col.darkened(0.3), 0.6, col, 0.8), false)
	RoomUtil.solid_box(self, Vector3(0, 4.55, 0), Vector3(4.5, 0.7, 1.1), stone)
	RoomUtil.mesh(self, RoomUtil.box_mesh(Vector3(3.6, 0.12, 0.08)), Vector3(0, 4.55, 0.56), RoomUtil.mat(col.darkened(0.2), 0.6, col, 1.0), false)
	RoomUtil.mesh(self, RoomUtil.box_mesh(Vector3(2.8, 0.12, 1.4)), Vector3(0, 0.06, 0.2), stone)
	# портал (полог)
	_portal = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 4.2)
	_portal.mesh = q
	_portal.position = Vector3(0, 2.1, -0.25)
	_portal_mat = StandardMaterial3D.new()
	_portal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_portal_mat.albedo_color = Color(0.05, 0.04, 0.04)
	_portal_mat.emission_enabled = true
	_portal_mat.emission = col
	_portal_mat.emission_energy_multiplier = 0.0
	_portal.material_override = _portal_mat
	_portal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_portal)
	RoomUtil.mesh(self, RoomUtil.box_mesh(Vector3(2.7, 4.3, 0.2)), Vector3(0, 2.1, -0.45), dark, false)
	# огни на столбах
	for sx: float in [-1.7, 1.7]:
		RoomUtil.mesh(self, RoomUtil.cyl_mesh(0.3, 0.2, 0.2, 8), Vector3(sx, 5.0, 0.2), dark)
		var f := RoomUtil.flame_sprite(col, 0.007)
		f.position = Vector3(sx, 5.3, 0.2)
		add_child(f)
		_flames.append(f)
	_light = OmniLight3D.new()
	_light.light_color = col
	_light.light_energy = 0.0
	_light.omni_range = 7.0
	_light.position = Vector3(0, 3.0, 1.2)
	add_child(_light)
	# символ награды
	_icon = RoomRewards.make_icon(String(_info["icon"]), col, String(room_data.get("god", "")), String(room_data.get("god2", "")))
	_icon.position = Vector3(0, 5.75, 0.3)
	_icon.scale = Vector3.ONE * 1.25
	add_child(_icon)
	_label = RoomUtil.label3d(String(_info["title"]), col.lerp(Color.WHITE, 0.35), 52, 0.0065)
	_label.position = Vector3(0, 6.85, 0.3)
	add_child(_label)
	if String(_info.get("sub", "")) != "":
		_sub = RoomUtil.label3d(String(_info["sub"]), Color(0.92, 0.86, 0.76), 34, 0.0055)
		_sub.position = Vector3(0, 6.45, 0.3)
		add_child(_sub)
	# порог: шагнуть в арку = войти
	_threshold = Area3D.new()
	_threshold.collision_layer = 0
	_threshold.collision_mask = Combat.LAYER_PLAYER
	_threshold.monitoring = true
	_threshold.monitorable = false
	var tcs := CollisionShape3D.new()
	var tsh := BoxShape3D.new()
	tsh.size = Vector3(2.4, 2.4, 1.0)
	tcs.shape = tsh
	tcs.position = Vector3(0, 1.2, 0.0)
	_threshold.add_child(tcs)
	add_child(_threshold)
	_threshold.body_entered.connect(_on_threshold)


func lock() -> void:
	is_open = false
	enabled = false
	for f in _flames:
		f.visible = false
	if _light:
		_light.light_energy = 0.0
	if _portal_mat:
		_portal_mat.emission_energy_multiplier = 0.0
	if _label:
		_label.modulate.a = 0.45
	if _icon:
		_icon.visible = true
		_icon.scale = Vector3.ONE * 0.9


func unlock() -> void:
	if is_open:
		return
	is_open = true
	enabled = true
	for f in _flames:
		f.visible = true
	if _label:
		_label.modulate.a = 1.0
	if _icon:
		_icon.scale = Vector3.ONE * 1.25
	var tw := create_tween()
	tw.set_parallel(true)
	if _light:
		tw.tween_property(_light, "light_energy", 2.4, 0.6)
	if _portal_mat:
		tw.tween_property(_portal_mat, "emission_energy_multiplier", 1.1, 0.8)
	if is_inside_tree():
		Fx3D.burst(get_parent(), global_position + Vector3(0, 5.3, 0.3), _info["color"], 14, 3.0)


func _process(delta: float) -> void:
	_t += delta
	if is_open:
		for i in _flames.size():
			var k := 1.0 + 0.15 * sin(_t * 9.0 + i * 2.0)
			_flames[i].scale = Vector3(k, k * 1.2, 1)
		if _light:
			_light.light_energy = 2.3 + 0.3 * sin(_t * 7.0)
		if _portal_mat:
			_portal_mat.emission_energy_multiplier = 0.9 + 0.25 * sin(_t * 2.5)


func can_activate(_player: Node) -> bool:
	return enabled and is_open and not _used


func activate(player: Node) -> void:
	if not can_activate(player):
		return
	activated.emit(player)
	_enter()


func _on_threshold(body: Node) -> void:
	if body.is_in_group("player") and can_activate(body):
		_enter()


func _enter() -> void:
	if _used:
		return
	_used = true
	Sfx.play("door")
	Sfx.play("teleport", -6.0)
	if is_inside_tree():
		Fx3D.flash_light(get_parent(), global_position + Vector3(0, 2, 1), _info["color"], 6.0, 8.0, 0.4)
		Fx3D.burst(get_parent(), global_position + Vector3(0, 2, 0.5), _info["color"], 20, 5.0)
	var p := RoomUtil.player(get_tree()) if is_inside_tree() else null
	if p and p.has_method("set_input_enabled"):
		p.set_input_enabled(false)
	entered.emit(room_data)
	Run.enter_room(room_data)
