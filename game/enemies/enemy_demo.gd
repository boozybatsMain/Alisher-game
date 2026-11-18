extends Node3D
## Демо-арена модуля C: пол, ярус, стена, колонны, герой (Run.spawn_player) и волны врагов всех типов.
## Запуск: godot --path . res://game/enemies/enemy_demo.tscn [-- boss=0|1|2]  (F1 — следующая волна, F2 — босс)

var _wave := 0
var _boss := 0


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.27, 0.34)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.68, 0.62)
	e.ambient_light_energy = 0.6
	e.fog_enabled = true
	e.fog_light_color = Color(0.45, 0.35, 0.5)
	e.fog_density = 0.008
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.88, 0.7)
	add_child(sun)
	_block(Vector3(0, -0.5, 0), Vector3(30, 1, 24), Color(0.62, 0.5, 0.33))
	_block(Vector3(-10, 1.5, -7), Vector3(9, 3, 8), Color(0.38, 0.36, 0.38))
	_block(Vector3(15.5, 2.5, 0), Vector3(1, 6, 24), Color(0.3, 0.28, 0.3))
	_block(Vector3(0, 2.5, -12.5), Vector3(30, 6, 1), Color(0.3, 0.28, 0.3))
	for p in [Vector3(5, 1.5, 4), Vector3(-4, 1.5, 5)]:
		_block(p, Vector3(1.2, 3, 1.2), Color(0.55, 0.5, 0.45))
	Run.spawn_player(self, Vector3(0, 0.2, 3))
	if Run.has_method("spawn_hud") and ResourceLoader.exists(Run.HUD_SCENE):
		Run.spawn_hud(self)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("boss="):
			EnemyFactory.spawn_boss(int(a.substr(5)), self, Vector3(0, 0.2, -4))
			return
	_next_wave()


func _block(pos: Vector3, size: Vector3, col: Color) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	m.material = mat
	mi.mesh = m
	b.add_child(mi)
	add_child(b)
	b.position = pos


func _next_wave() -> void:
	_wave += 1
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 6:
		var pos := Vector3(rng.randf_range(-12, 12), 0.2, rng.randf_range(-4, 10))
		EnemyFactory.spawn_random(mini(_wave - 1, 2), self, pos, {"elite": i == 0 and _wave > 1}, rng)


func _process(_delta: float) -> void:
	if get_tree().get_nodes_in_group("enemies").is_empty() and get_tree().get_nodes_in_group("boss").is_empty():
		_next_wave()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed:
		if (ev as InputEventKey).keycode == KEY_F1:
			_next_wave()
		elif (ev as InputEventKey).keycode == KEY_F2:
			EnemyFactory.spawn_boss(_boss % 3, self, Vector3(0, 0.2, -4))
			_boss += 1
