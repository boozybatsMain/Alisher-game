class_name EnemyFactory
extends RefCounted
## Создание врагов по id (EnemyData.TYPES) с эффектом появления: столб Мглы и тёмные частицы.
## Враг активируется через ~0.6 с (до этого неуязвим и не атакует — честное появление).
##
## spawn(type_id, parent, pos, mods := {}) -> EnemyBase
##   mods: {"elite": bool, "element": String, "hp_mult": float, "dmg_mult": float,
##          "spawn_delay": float (по умолчанию 0.6), "dirhams": int (переопределить выпадение), "scale": float,
##          "no_fx": bool (без столба Мглы)}
## spawn_random(biome, parent, pos, mods, rng) -> EnemyBase — случайный тип из пула биома.
## spawn_boss(biome, parent, pos, mods) -> EnemyBase

const DEFAULT_DELAY := 0.6


static func spawn(type_id: String, parent: Node, pos: Vector3, mods := {}) -> EnemyBase:
	var d := EnemyData.data(type_id)
	var script_path := String(d.get("script", "res://game/enemies/enemy_base.gd"))
	var e: EnemyBase = null
	if ResourceLoader.exists(script_path):
		e = load(script_path).new() as EnemyBase
	if e == null:
		e = EnemyBase.new()
	e.type_id = type_id if EnemyData.TYPES.has(type_id) else "wolf"
	e.data = d
	e.mods = mods.duplicate()
	e.spawn_delay = float(mods.get("spawn_delay", DEFAULT_DELAY))
	e.name = "%s_%d" % [type_id, e.get_instance_id()]
	if parent == null:
		return e
	parent.add_child(e)
	e.global_position = pos
	if not bool(mods.get("no_fx", false)) and parent.is_inside_tree():
		spawn_fx(parent, pos, e.spawn_delay, e.body_height, e.elite or e.is_boss)
	return e


static func spawn_random(biome: int, parent: Node, pos: Vector3, mods := {}, rng: RandomNumberGenerator = null) -> EnemyBase:
	return spawn(EnemyData.pick(biome, rng), parent, pos, mods)


static func spawn_boss(biome: int, parent: Node, pos: Vector3, mods := {}) -> EnemyBase:
	var m := mods.duplicate()
	if not m.has("spawn_delay"):
		m["spawn_delay"] = 1.2
	return spawn(EnemyData.boss_for(biome), parent, pos, m)


## Столб Мглы: тёмно-фиолетовый цилиндр растёт и тает, частицы поднимаются вверх, кольцо на земле.
static func spawn_fx(parent: Node, pos: Vector3, time := DEFAULT_DELAY, height := 2.0, big := false) -> void:
	var root := Node3D.new()
	root.name = "MistPillar"
	parent.add_child(root)
	root.global_position = pos
	var r := 0.9 if not big else 1.6
	var cyl := CylinderMesh.new()
	cyl.top_radius = r * 0.6
	cyl.bottom_radius = r
	cyl.height = height * 2.2
	cyl.radial_segments = 20
	cyl.cap_top = false
	cyl.cap_bottom = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.45, 0.18, 0.75, 0.55)
	if ResourceLoader.exists("res://assets/fx/soft.png"):
		mat.albedo_texture = load("res://assets/fx/soft.png")
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = cyl.height * 0.5
	mi.scale = Vector3(0.1, 0.05, 0.1)
	root.add_child(mi)
	# тёмные частицы
	var pt := CPUParticles3D.new()
	pt.amount = 24 if not big else 48
	pt.lifetime = 0.9
	pt.one_shot = false
	pt.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	pt.emission_sphere_radius = r
	pt.direction = Vector3.UP
	pt.spread = 25.0
	pt.gravity = Vector3(0, 2.5, 0)
	pt.initial_velocity_min = 1.0
	pt.initial_velocity_max = 3.0
	pt.scale_amount_min = 0.6
	pt.scale_amount_max = 1.4
	pt.color = Color(0.2, 0.08, 0.3, 0.9)
	var qm := QuadMesh.new()
	qm.size = Vector2(0.35, 0.35)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.vertex_color_use_as_albedo = true
	if ResourceLoader.exists("res://assets/fx/puff.png"):
		pm.albedo_texture = load("res://assets/fx/puff.png")
	qm.material = pm
	pt.mesh = qm
	root.add_child(pt)
	# кольцо на земле
	EnemyTelegraph.ring(parent, pos, r * 1.1, r * 1.35, time, Color(0.6, 0.25, 1.0))
	Sfx.play("summon", -8.0)
	var tw := root.create_tween()
	tw.tween_property(mi, "scale", Vector3(1, 1, 1), time * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(time * 0.4)
	tw.tween_callback(func(): pt.emitting = false)
	tw.tween_property(mi, "scale", Vector3(0.05, 1.3, 0.05), 0.35).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(mi, "transparency", 1.0, 0.35)
	tw.tween_interval(0.6)
	tw.tween_callback(root.queue_free)
	Fx3D.flash_light(parent, pos + Vector3(0, 1.2, 0), Color(0.55, 0.25, 1.0), 3.0, 5.0, time)
