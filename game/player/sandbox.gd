extends Node3D
## Песочница модуля A: простая арена с ярусами, стеной для отскока, уступом, пропастью и манекенами-целями.
## Запуск: godot --path . res://game/player/sandbox.tscn  (или smoke: -- scene=res://game/player/sandbox.tscn secs=6)
## Показывает героя, камеру, HUD, эффекты. Клавиша F1 — тестовый тост/диалог, F2 — телеграфы.

const STONE := Color(0.33, 0.31, 0.33)
const OCHRE := Color(0.72, 0.52, 0.3)
const FELT := Color(0.45, 0.22, 0.16)
const TEAL := Color(0.25, 0.62, 0.6)

var player: Player
var cam: GameCamera


func _ready() -> void:
	_env()
	_box(Vector3(0, -0.5, 0), Vector3(30, 1, 24), OCHRE)
	# стена (запад) и стена (север)
	_box(Vector3(-15.5, 3, 0), Vector3(1, 6, 24), STONE)
	_box(Vector3(0, 3, -12.5), Vector3(30, 6, 1), STONE)
	# ярус 3 м (северо-восток) и ярус 6 м
	_box(Vector3(9, 1.5, -7), Vector3(12, 3, 10), FELT.lightened(0.15))
	_box(Vector3(12, 4.5, -9.5), Vector3(6, 3, 5), FELT)
	# колонны и низкая перекладина для подката
	for x in [-8.0, -3.0]:
		_cyl(Vector3(x, 2.0, -6), 0.6, 4.0, STONE.lightened(0.1))
	_box(Vector3(-5.5, 1.45, 2), Vector3(4, 0.5, 0.5), TEAL)
	_box(Vector3(-7.25, 0.6, 2), Vector3(0.5, 1.2, 0.5), STONE)
	_box(Vector3(-3.75, 0.6, 2), Vector3(0.5, 1.2, 0.5), STONE)
	# пропасть: островок
	_box(Vector3(0, -0.5, 18), Vector3(6, 1, 6), OCHRE.darkened(0.1))
	Run.set_hp(Run.max_hp())
	player = Run.spawn_player(self, Vector3(0, 0.2, 4)) as Player
	cam = GameCamera.attach(self, player)
	Run.spawn_hud(self)
	for i in 3:
		var d := _Target.new()
		add_child(d)
		d.global_position = Vector3(4 + i * 2.0, 0, 3)
	Sfx.music("calm")


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match (e as InputEventKey).keycode:
			KEY_F1:
				Bus.toast.emit("Духи степи слышат тебя", UiKit.TEAL)
				Bus.dialogue_requested.emit([{"speaker": "Дух предка", "text": "Кайсар, корни Байтерека стонут. Мгла Кара-Тұман ползёт с востока."},
					{"speaker": "Кайсар", "text": "Тогда я пойду ей навстречу."}])
			KEY_F2:
				Fx3D.telegraph_circle(self, player.global_position + Vector3(3, 0, 0), 2.0, 0.5)
				Fx3D.telegraph_cone(self, player.global_position, player.facing, 4.0, 70.0, 0.5)
				Fx3D.telegraph_line(self, player.global_position, player.global_position + Vector3(-6, 0, -2), 1.2, 0.5)


func _env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.36, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.68, 0.6)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.55, 0.5)
	env.fog_density = 0.008
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func _box(pos: Vector3, size: Vector3, color: Color) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	m.material = mat
	mi.mesh = m
	b.add_child(mi)
	add_child(b)
	b.position = pos


func _cyl(pos: Vector3, r: float, h: float, color: Color) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r * 1.1
	m.height = h
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material = mat
	mi.mesh = m
	b.add_child(mi)
	add_child(b)
	b.position = pos


## Простая цель: принимает удары, показывает числа урона.
class _Target extends Node3D:
	var hit_radius := 0.5
	var _mesh: MeshInstance3D

	func _ready() -> void:
		add_to_group("hurtable_enemy")
		_mesh = MeshInstance3D.new()
		var m := CylinderMesh.new()
		m.top_radius = 0.25
		m.bottom_radius = 0.4
		m.height = 1.6
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.7, 0.45)
		m.material = mat
		_mesh.mesh = m
		_mesh.position.y = 0.8
		add_child(_mesh)

	func take_hit(h: Hit) -> void:
		var kind := "crit" if h.is_crit else ("special" if h.kind == "special" else "normal")
		Bus.damage_number.emit(global_position + Vector3(0, 1.9, 0), h.amount, kind)
		Bus.hit_landed.emit(h, self)
		Fx3D.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(1, 0.8, 0.5), 8)

	func get_facing() -> Vector3:
		return Vector3(0, 0, 1)

	func is_dead() -> bool:
		return false

	func apply_status(_id: String, _p: Dictionary) -> void:
		pass

	func knock(_v: Vector3) -> void:
		pass
