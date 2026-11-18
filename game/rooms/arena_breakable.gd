class_name ArenaBreakable
extends StaticBody3D
## Разрушаемые объекты арены (модуль D): колонны и кувшины.
## Группы "hurtable_enemy" (герой бьёт их как врагов) и "destructible" (враги, отброшенные в колонну, бьют её).
## Контракт цели: take_hit(hit), hit_radius, is_dead(), get_facing(), apply_status(), knock(), statuses.
##
## Колонна: копит урон; при разрушении падает в направлении удара, разлетается на куски и наносит урон врагам
## рядом и вдоль падения (Hit kind "wall", тег "column_crush"). Остаётся пенёк.
## Кувшин: разбивается с одного удара, высыпает дирхемы (Run.add_dirhams).
## Тайная плита (kind "secret_wall"): треснувший кусок стены со светящимися прожилками; после разрушения
## room.gd ставит на её месте дверь в тайную комнату (сигнал broken).

signal broken(node: ArenaBreakable)

var kind := "column"
var hp := 60.0
var max_hp := 60.0
var hit_radius := 0.7
var height := 5.0
var statuses := {}
var dirhams := 0
var crush_damage := 45.0
var _dead := false
var _vis: Node3D
var _mat: Material
var _accent: Material
var _shake_t := 0.0


static func make_column(pal: Dictionary, stone: Material, accent: Material, h: float) -> ArenaBreakable:
	var b := ArenaBreakable.new()
	b.kind = "column"
	b.height = h
	b.hp = 60.0
	b.max_hp = 60.0
	b.hit_radius = 0.75
	b._mat = stone
	b._accent = accent
	b.name = "DestructibleColumn"
	return b


static func make_jar(pal: Dictionary, rng: RandomNumberGenerator) -> ArenaBreakable:
	var b := ArenaBreakable.new()
	b.kind = "jar"
	b.hp = 1.0
	b.max_hp = 1.0
	b.hit_radius = 0.35
	b.height = 0.8
	b.dirhams = rng.randi_range(3, 9)
	var clay := Color(0.62, 0.38, 0.24).lerp(pal.get("floor", Color(0.6, 0.4, 0.25)), 0.3)
	b._mat = RoomUtil.mat(clay, 0.85)
	b._accent = RoomUtil.mat(pal.get("accent", Color(0.3, 0.7, 0.65)), 0.7)
	b.name = "Jar"
	return b


static func make_secret_wall(stone: Material, accent: Material) -> ArenaBreakable:
	var b := ArenaBreakable.new()
	b.kind = "secret_wall"
	b.hp = 40.0
	b.max_hp = 40.0
	b.hit_radius = 1.3
	b.height = 3.4
	b._mat = stone
	b._accent = accent
	b.name = "SecretWall"
	return b


func _ready() -> void:
	add_to_group("hurtable_enemy")
	add_to_group("destructible")
	if kind == "jar":
		add_to_group("jar")
		collision_layer = Combat.LAYER_DESTRUCTIBLE
	else:
		collision_layer = Combat.LAYER_WORLD | Combat.LAYER_DESTRUCTIBLE
	collision_mask = 0
	_build()


func _build() -> void:
	_vis = Node3D.new()
	add_child(_vis)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	if kind == "jar":
		sh.radius = 0.32
		sh.height = 0.8
		cs.position = Vector3(0, 0.4, 0)
		RoomUtil.mesh(_vis, RoomUtil.cyl_mesh(0.22, 0.18, 0.12, 10), Vector3(0, 0.06, 0), _mat)
		var body := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.32
		sm.height = 0.6
		sm.radial_segments = 12
		sm.rings = 6
		body.mesh = sm
		body.material_override = _mat
		body.position = Vector3(0, 0.38, 0)
		_vis.add_child(body)
		RoomUtil.mesh(_vis, RoomUtil.cyl_mesh(0.12, 0.17, 0.22, 10), Vector3(0, 0.74, 0), _mat)
		RoomUtil.mesh(_vis, RoomUtil.cyl_mesh(0.325, 0.325, 0.05, 12), Vector3(0, 0.45, 0), _accent, false)
	elif kind == "secret_wall":
		var box := BoxShape3D.new()
		box.size = Vector3(2.6, height, 0.7)
		cs.shape = box
		cs.position = Vector3(0, height * 0.5, 0)
		add_child(cs)
		# кладка из плит, одна — с трещинами и холодным светом изнутри
		for i in 3:
			var blk := RoomUtil.mesh(_vis, RoomUtil.box_mesh(Vector3(2.6, height / 3.0 - 0.05, 0.7)), Vector3(0, height / 3.0 * (i + 0.5), 0), _mat)
			blk.rotation.y = (i - 1) * 0.03
		for i in 4:
			var cr := RoomUtil.mesh(_vis, RoomUtil.box_mesh(Vector3(0.06, 0.9, 0.04)), Vector3(-0.7 + i * 0.45, 0.9 + (i % 2) * 1.1, 0.37), _accent, false)
			cr.rotation.z = 0.6 * (1 if i % 2 == 0 else -1)
		var glow := OmniLight3D.new()
		glow.light_color = (_accent as StandardMaterial3D).albedo_color if _accent is StandardMaterial3D else Color(0.5, 1, 0.9)
		glow.light_energy = 0.8
		glow.omni_range = 3.0
		glow.position = Vector3(0, 1.6, 0.8)
		_vis.add_child(glow)
		return
	else:
		sh.radius = 0.68
		sh.height = height
		cs.position = Vector3(0, height * 0.5, 0)
		RoomUtil.mesh(_vis, RoomUtil.box_mesh(Vector3(1.6, 0.45, 1.6)), Vector3(0, 0.22, 0), _mat)
		# колонна из барабанов с трещинами — видно, что её можно обрушить
		var drums := int(height / 1.1)
		for i in drums:
			var h := height / drums
			var d := RoomUtil.mesh(_vis, RoomUtil.cyl_mesh(0.6, 0.64, h - 0.04, 9), Vector3(0, h * (i + 0.5), 0), _mat)
			d.rotation.y = i * 0.4
		RoomUtil.mesh(_vis, RoomUtil.box_mesh(Vector3(1.5, 0.35, 1.5)), Vector3(0, height + 0.17, 0), _mat)
		# светящиеся трещины-метки
		for i in 3:
			var cr := RoomUtil.mesh(_vis, RoomUtil.box_mesh(Vector3(0.05, 0.7, 0.05)), Vector3(0.0, 1.0 + i * 1.3, 0.63), _accent, false)
			cr.rotation.z = 0.5 * (1 if i % 2 == 0 else -1)
	cs.shape = sh
	add_child(cs)


# ---------------------------------------------------------------- контракт цели
func is_dead() -> bool:
	return _dead


func get_facing() -> Vector3:
	return Vector3(0, 0, 1)


func apply_status(_id: String, _params: Dictionary) -> void:
	pass


func knock(_v: Vector3) -> void:
	pass


func take_hit(hit: Hit) -> void:
	if _dead or hit == null:
		return
	var amount := hit.amount
	if kind == "column" or kind == "secret_wall":
		# тяжёлые удары и удары об колонну рушат быстрее
		if hit.heavy or hit.kind == "wall" or "wall_slam" in hit.tags:
			amount *= 2.0
		amount = maxf(amount, 4.0)
	hp -= amount
	Bus.hit_landed.emit(hit, self)
	if kind == "column" or kind == "secret_wall":
		Sfx.play("hit_heavy", -6.0)
		Fx3D.burst(_fx_parent(), global_position + Vector3(0, 1.2, 0), Color(0.8, 0.75, 0.65), 8, 4.0)
		_shake_t = 0.2
	if hp <= 0.0:
		_break(hit)


func _fx_parent() -> Node:
	return get_tree().current_scene if get_tree().current_scene else get_parent()


func _process(delta: float) -> void:
	if _shake_t > 0.0 and _vis:
		_shake_t -= delta
		_vis.position = Vector3(randf_range(-0.05, 0.05), 0, randf_range(-0.05, 0.05)) if _shake_t > 0.0 else Vector3.ZERO


func _break(hit: Hit) -> void:
	_dead = true
	remove_from_group("hurtable_enemy")
	remove_from_group("destructible")
	broken.emit(self)
	if kind == "jar":
		_break_jar()
	elif kind == "secret_wall":
		_break_secret()
	else:
		_break_column(hit)


func _break_secret() -> void:
	Sfx.play("slam")
	Sfx.play("door", -2.0)
	Bus.shake.emit(0.6, 0.3)
	var fx := _fx_parent()
	Fx3D.puff(fx, global_position + Vector3(0, 1.0, 0), Color(0.75, 0.68, 0.58, 0.9), 16)
	_spawn_chunks(12, 0.4, 2.0, global_position + Vector3(0, 1.2, 0))
	queue_free()


func _break_jar() -> void:
	Sfx.play("hit", -4.0, 0.2)
	var fx := _fx_parent()
	Fx3D.burst(fx, global_position + Vector3(0, 0.4, 0), Color(0.7, 0.45, 0.3), 10, 3.5, 0.14)
	if dirhams > 0:
		Run.add_dirhams(dirhams)
		Fx3D.burst(fx, global_position + Vector3(0, 0.5, 0), RoomUtil.GOLD, 8, 3.0, 0.12)
		Fx3D.number(fx, global_position + Vector3(0, 1.2, 0), "+%d" % dirhams, RoomUtil.GOLD, 40)
		Sfx.play("buy", -10.0)
	_spawn_chunks(6, 0.18, 0.5)
	queue_free()


func _break_column(hit: Hit) -> void:
	Sfx.play("slam")
	Bus.shake.emit(0.9, 0.35)
	var fx := _fx_parent()
	var dir := Vector3(hit.direction.x, 0, hit.direction.z)
	if dir.length() < 0.1 and hit.source is Node3D:
		dir = global_position - (hit.source as Node3D).global_position
		dir.y = 0
	if dir.length() < 0.1:
		dir = Vector3(1, 0, 0)
	dir = dir.normalized()
	Fx3D.puff(fx, global_position, Color(0.75, 0.68, 0.58, 0.9), 14)
	# урон врагам: вокруг основания и вдоль падения
	var hitlist := {}
	for n in Combat.in_radius(get_tree(), global_position, 2.2, "enemies"):
		hitlist[n] = true
	for n in Combat.along_line(get_tree(), global_position, global_position + dir * height, 1.1, "enemies"):
		hitlist[n] = true
	for n in hitlist:
		if not is_instance_valid(n) or n == self:
			continue
		var h := Hit.make(crush_damage, hit.source, "wall")
		h.tags = ["column_crush", "wall_slam"]
		h.heavy = true
		h.armor_mult = 2.0
		h.stun = 0.8
		h.no_boons = true
		h.position = (n as Node3D).global_position
		h.direction = dir
		h.knockback = dir * 5.0 + Vector3(0, 3, 0)
		Combat.player_hit(n, h)
	# падающий ствол (визуальный)
	var fall := Node3D.new()
	fx.add_child(fall)
	fall.global_position = global_position
	var trunk := RoomUtil.mesh(fall, RoomUtil.cyl_mesh(0.55, 0.6, height * 0.8, 9), Vector3(0, height * 0.4 + 0.6, 0), _mat)
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var axis := Vector3.UP.cross(dir).normalized()
	var tw := fall.create_tween()
	tw.tween_method(func(a: float): fall.basis = Basis(axis, a), 0.0, PI * 0.5 * 0.97, 0.55).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		Sfx.play("slam", -3.0)
		Bus.shake.emit(0.6, 0.25)
		Fx3D.puff(fx, global_position + dir * height * 0.6, Color(0.75, 0.68, 0.58, 0.9), 16)
		_spawn_chunks(10, 0.35, 1.5, global_position + dir * height * 0.5))
	tw.tween_interval(0.4)
	tw.tween_property(fall, "scale", Vector3(0.9, 0.05, 0.9), 0.5)
	tw.tween_callback(fall.queue_free)
	# пенёк остаётся: перестраиваем визуал и коллизию
	for c in get_children():
		c.queue_free()
	var stump_h := 1.1
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.68
	sh.height = stump_h
	cs.shape = sh
	cs.position = Vector3(0, stump_h * 0.5, 0)
	add_child(cs)
	collision_layer = Combat.LAYER_WORLD
	_vis = Node3D.new()
	add_child(_vis)
	RoomUtil.mesh(_vis, RoomUtil.box_mesh(Vector3(1.6, 0.45, 1.6)), Vector3(0, 0.22, 0), _mat)
	var st := RoomUtil.mesh(_vis, RoomUtil.cyl_mesh(0.5, 0.64, stump_h, 7), Vector3(0, stump_h * 0.5, 0), _mat)
	st.rotation = Vector3(0.1, 0, 0.12)


func _spawn_chunks(n: int, size: float, spread: float, at := Vector3.INF) -> void:
	var fx := _fx_parent()
	if fx == null:
		return
	var origin := global_position if at == Vector3.INF else at
	for i in n:
		var rb := RigidBody3D.new()
		rb.collision_layer = 0
		rb.collision_mask = Combat.LAYER_WORLD
		rb.mass = 0.3
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		var s := size * randf_range(0.6, 1.3)
		sh.size = Vector3(s, s, s)
		cs.shape = sh
		rb.add_child(cs)
		var mi := RoomUtil.mesh(rb, RoomUtil.box_mesh(sh.size), Vector3.ZERO, _mat)
		fx.add_child(rb)
		rb.global_position = origin + Vector3(randf_range(-spread, spread) * 0.3, randf_range(0.3, 1.5), randf_range(-spread, spread) * 0.3)
		rb.linear_velocity = Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-3, 3))
		rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		var tw := rb.create_tween()
		tw.tween_interval(2.0 + randf())
		tw.tween_property(mi, "scale", Vector3(0.01, 0.01, 0.01), 0.5)
		tw.tween_callback(rb.queue_free)
