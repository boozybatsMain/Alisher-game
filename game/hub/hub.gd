extends Node3D
## Стойбище Предков (Хаб). Вечер, закат над степью. Всё строится процедурно:
##  - центр: родовой костёр (частицы + мерцающий OmniLight3D), войлочные ковры, домбра на ковре (режим домбры);
##  - юрта героя (стены-кереге, купол, орнамент) с Сандыком у входа;
##  - оружейный шатёр: 5 стоек + «Чучело батыра» с DPS; кузнец Ұста;
##  - гигантские корни Байтерека на севере (светящиеся прожилки) и ворота-арка с туманом «Выйти на тропу»;
##  - 2D-задник заката (assets/bg/sky_day.jpg) и силуэты курганов/руин на дальних плоскостях с параллаксом.
## NPC: Әже у костра, Дух-Корень у ворот, Ұста у оружейной. Сюжетные сценки — Story.on_hub_enter().
##
## API для тестов/других модулей: player, armory, dummy, racks, chest, dombra_model, dombra_mode, gate,
##   open_dombra(p := player) -> DombraMode, leave_to_trail()

const GAME_CAMERA := "res://game/player/game_camera.gd"
const SPAWN := Vector3(0.0, 0.1, 3.6)

var player: Node3D
var cam: Camera3D
var armory: Armory
var dummy: TrainingDummy
var racks: Array = []
var chest: AncestorChest
var dombra_model: DombraModel
var dombra_mode: DombraMode
var gate: Interactable
var npcs := {}

var _fire: Node3D
var _fire_light: OmniLight3D
var _fire_base := 2.6
var _t := 0.0
var _bg_rig: Node3D
var _bg_layers: Array = []      ## [[node, distance, follow]]
var _fallback_cam := false
var _leaving := false
var _gate_fog: CPUParticles3D
var _faders: Array = []          ## [{meshes, aabb, cur}] — объекты, которые становятся прозрачными, если закрывают героя


func _ready() -> void:
	Run.active = false
	Run.weapon = Meta.equipped_weapon
	Run.aspect = Meta.equipped_aspect
	Run.hp = Run.max_hp()
	var reason := Run.hub_reason
	_env()
	_ground()
	_campfire()
	_yurt(Vector3(-9.0, 0, -2.5), deg_to_rad(40.0))
	_armory(Vector3(8.5, 0, -3.5), deg_to_rad(-25.0))
	_bayterek()
	_gate(Vector3(0, 0, -12.0))
	_npcs()
	_decor()
	_backdrop()
	add_fader(armory.roof, 2.5)
	var yurt_meshes: Array = []
	for c in get_node("Yurt").get_children():
		if c is MeshInstance3D:
			yurt_meshes.append(c)
	add_fader(yurt_meshes)
	var spawn := SPAWN
	if reason == "death":
		spawn = Vector3(1.5, 0.1, -9.0)   # корни приносят героя к воротам
	player = Run.spawn_player(self, spawn)
	_attach_camera()
	if reason == "death":
		Fx3D.ring(self, spawn, 2.5, Color(0.35, 0.95, 0.75), 0.8)
		Fx3D.flash_light(self, spawn + Vector3(0, 1, 0), Color(0.35, 0.95, 0.75), 6.0, 7.0, 0.6)
		Sfx.play("revive", -4.0)
	Run.spawn_hud(self)
	Sfx.music("yurt")
	Bus.hp_changed.emit(Run.hp, Run.max_hp())
	Bus.ash_changed.emit(Meta.ash)
	_story_on_enter.call_deferred()


func _story_on_enter() -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	var lines := Story.on_hub_enter()
	if not lines.is_empty():
		Bus.dialogue_requested.emit(lines)


# ================================================================ окружение
func _env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.27, 0.45)
	sm.sky_horizon_color = Color(1.0, 0.58, 0.3)
	sm.ground_horizon_color = Color(0.7, 0.42, 0.25)
	sm.ground_bottom_color = Color(0.18, 0.12, 0.12)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.35
	env.ambient_light_color = Color(0.55, 0.45, 0.6)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.42, 0.34)
	env.fog_light_energy = 0.55
	env.fog_density = 0.0055
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.08
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sunset"
	sun.rotation_degrees = Vector3(-24, -125, 0)   # низкое закатное солнце с запада-северо-запада
	sun.light_color = Color(1.0, 0.68, 0.42)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 55.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-50, 60, 0)
	fill.light_color = Color(0.45, 0.5, 0.8)
	fill.light_energy = 0.25
	add_child(fill)


func _ground() -> void:
	# плато стойбища: диск травы-охры с шумовой текстурой, край-обрыв, за ним — задник
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.30, 0.32, 0.17))
	ramp.set_color(1, Color(0.62, 0.46, 0.26))
	ramp.add_point(0.5, Color(0.48, 0.42, 0.22))
	nt.color_ramp = ramp
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = nt
	gm.uv1_scale = Vector3(6, 6, 6)
	gm.roughness = 0.95
	var disc := CylinderMesh.new()
	disc.top_radius = 17.5
	disc.bottom_radius = 15.0
	disc.height = 6.0
	disc.radial_segments = 48
	var g := MeshInstance3D.new()
	g.mesh = disc
	g.material_override = gm
	g.position = Vector3(0, -3.0, 0)
	add_child(g)
	# скальное основание плато
	var rock := CylinderMesh.new()
	rock.top_radius = 15.2
	rock.bottom_radius = 6.0
	rock.height = 30.0
	rock.radial_segments = 24
	var r := MeshInstance3D.new()
	r.mesh = rock
	r.material_override = HubProps.mat(Color(0.25, 0.2, 0.2))
	r.position = Vector3(0, -21.0, 0)
	add_child(r)
	HubProps.solid_box(self, Vector3(40, 1, 40), Vector3(0, -0.5, 0))
	# невидимая ограда по краю плато
	for i in 24:
		var a := i * TAU / 24.0
		HubProps.solid_box(self, Vector3(4.2, 4, 0.6), Vector3(cos(a), 0, sin(a)) * 15.6 + Vector3(0, 2, 0), Vector3(0, -rad_to_deg(a) + 90, 0))
	# тропинки к юрте, оружейной и воротам
	var path := HubProps.mat(Color(0.62, 0.5, 0.34), 1.0)
	for seg in [[Vector3(0, 0, 0), Vector3(-8, 0, -1)], [Vector3(0, 0, 0), Vector3(7.5, 0, -1.5)], [Vector3(0, 0, 0), Vector3(0, 0, -11)]]:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var len := a.distance_to(b)
		var mi := HubProps.box(self, Vector3(1.6, 0.02, len), (a + b) * 0.5 + Vector3(0, 0.01, 0), path)
		mi.look_at_from_position(mi.position, b + Vector3(0, 0.01, 0), Vector3.UP)


func _campfire() -> void:
	# круг камней, поленья, огонь
	for i in 10:
		var a := i * TAU / 10.0
		var s := HubProps.sphere(self, 0.22, Vector3(cos(a) * 0.95, 0.1, sin(a) * 0.95), HubProps.STONE.lightened(randf() * 0.15), Vector3(1.2, 0.7, 1.0), 8)
		s.rotation.y = a
	for i in 4:
		var a := i * TAU / 4.0 + 0.4
		HubProps.cyl(self, 0.08, 0.1, 1.1, Vector3(cos(a) * 0.25, 0.22, sin(a) * 0.25), HubProps.WOOD_DARK, Vector3(65, rad_to_deg(-a), 0))
	HubProps.cyl(self, 0.7, 0.75, 0.04, Vector3(0, 0.02, 0), Color(0.12, 0.08, 0.06))
	_fire = HubProps.fire(self, Vector3(0, 0.15, 0), 1.0)
	_fire_light = _fire.get_meta("light")
	HubProps.solid_cyl(self, 0.9, 1.0, Vector3(0, 0.5, 0))
	# ковры-сырмақ вокруг огня и бревна-сиденья
	for d in [[Vector3(2.0, 0.02, 1.0), 20.0, HubProps.FELT_RED], [Vector3(-2.0, 0.02, 1.3), -25.0, Color(0.2, 0.35, 0.5)], [Vector3(0.2, 0.02, 2.3), 0.0, Color(0.5, 0.3, 0.15)]]:
		var rug := HubProps.box(self, Vector3(1.8, 0.03, 1.1), d[0], d[2], Vector3(0, d[1], 0))
		rug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		HubProps.box(self, Vector3(1.6, 0.035, 0.9), d[0] + Vector3(0, 0.002, 0), (d[2] as Color).lightened(0.25), Vector3(0, d[1], 0))
		HubProps.box(self, Vector3(1.4, 0.04, 0.7), d[0] + Vector3(0, 0.004, 0), d[2], Vector3(0, d[1], 0))
	HubProps.cyl(self, 0.2, 0.2, 1.6, Vector3(-1.2, 0.2, -1.6), HubProps.WOOD, Vector3(0, 30, 90))
	HubProps.cyl(self, 0.2, 0.2, 1.4, Vector3(1.4, 0.2, -1.4), HubProps.WOOD, Vector3(0, -40, 90))
	# домбра на ковре
	dombra_model = DombraModel.new()
	dombra_model.name = "Dombra"
	add_child(dombra_model)
	var rest_b := Basis(Vector3.UP, deg_to_rad(-20)) * Basis(Vector3.RIGHT, -PI / 2.0)
	dombra_model.rest_xform = Transform3D(rest_b, Vector3(1.6, 0.12, 0.95))
	var play_b := Basis(Vector3.UP, PI / 4.0) * Basis(Vector3(0, 0, 1), deg_to_rad(28))
	dombra_model.play_xform = Transform3D(play_b, Vector3(2.2, 1.0, 1.7))
	dombra_model.transform = dombra_model.rest_xform
	var it := Interactable.new()
	it.name = "DombraSpot"
	it.prompt = "Сесть у костра (домбра)"
	it.radius = 1.3
	it.position = Vector3(1.9, 0.0, 1.0)
	add_child(it)
	it.activated.connect(func(p: Node): open_dombra(p))


func _yurt(pos: Vector3, yaw: float) -> void:
	var y := Node3D.new()
	y.name = "Yurt"
	y.position = pos
	y.rotation.y = yaw
	add_child(y)
	var felt := HubProps.FELT_WHITE
	# стены (кереге) и купол (шаңырақ)
	HubProps.cyl(y, 3.2, 3.25, 2.1, Vector3(0, 1.05, 0), felt, Vector3.ZERO, 32)
	HubProps.cyl(y, 0.6, 3.35, 1.7, Vector3(0, 2.95, 0), felt.darkened(0.06), Vector3.ZERO, 32)
	HubProps.torus(y, 0.45, 0.65, Vector3(0, 3.8, 0), HubProps.WOOD_DARK)
	HubProps.cyl(y, 0.5, 0.5, 0.1, Vector3(0, 3.82, 0), HubProps.glow_mat(Color(1.0, 0.65, 0.3), 1.5))
	# орнамент: красная лента с ромбами по кругу и бирюзовая полоса
	HubProps.cyl(y, 3.27, 3.27, 0.35, Vector3(0, 1.75, 0), HubProps.FELT_RED, Vector3.ZERO, 32)
	HubProps.cyl(y, 3.28, 3.28, 0.08, Vector3(0, 1.5, 0), HubProps.TURQ, Vector3.ZERO, 32)
	for i in 20:
		var a := i * TAU / 20.0
		var p := Vector3(cos(a) * 3.3, 1.75, sin(a) * 3.3)
		var d := HubProps.box(y, Vector3(0.22, 0.22, 0.03), p, HubProps.GOLD, Vector3(0, -rad_to_deg(a) + 90, 45))
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# перехваты-баулы (белые ленты по куполу)
	for i in 8:
		var a := i * TAU / 8.0
		var band := HubProps.box(y, Vector3(0.1, 0.04, 2.9), Vector3(cos(a) * 2.0, 3.0, sin(a) * 2.0), HubProps.FELT_RED)
		band.look_at_from_position(y.to_global(Vector3(cos(a) * 2.0, 3.0, sin(a) * 2.0)), y.to_global(Vector3(0, 3.85, 0)), Vector3.UP)
	# резная дверь (на +Z) и полог
	HubProps.box(y, Vector3(1.1, 1.7, 0.2), Vector3(0, 0.85, 3.2), HubProps.WOOD)
	HubProps.box(y, Vector3(0.9, 1.5, 0.05), Vector3(0, 0.85, 3.31), Color(0.75, 0.3, 0.12))
	for k in 3:
		HubProps.box(y, Vector3(0.6, 0.06, 0.02), Vector3(0, 0.5 + k * 0.4, 3.34), HubProps.GOLD)
	HubProps.solid_cyl(y, 3.3, 4.0, Vector3(0, 2.0, 0))
	# тёплый свет из шаңырака
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.65, 0.35)
	l.light_energy = 1.0
	l.omni_range = 4.0
	l.position = Vector3(0, 4.3, 0)
	y.add_child(l)
	HubProps.label(y, "Юрта Кайсара", Vector3(0, 4.8, 0), Color(1, 0.88, 0.6), 46)
	# Сандык у входа
	chest = AncestorChest.new()
	chest.name = "AncestorChest"
	y.add_child(chest)
	chest.position = Vector3(1.5, 0, 4.0)
	chest.rotation.y = deg_to_rad(-15)


func _armory(pos: Vector3, yaw: float) -> void:
	armory = Armory.new()
	armory.name = "Armory"
	armory.position = pos
	armory.rotation.y = yaw
	add_child(armory)
	dummy = armory.dummy
	racks = armory.racks


func _bayterek() -> void:
	# гигантские корни, выползающие из-за края плато на севере, с бирюзовыми прожилками
	var bark := HubProps.mat(Color(0.24, 0.17, 0.13), 0.95)
	var vein := HubProps.glow_mat(Color(0.3, 0.95, 0.8), 1.4)
	var curves := [
		[Vector3(-30, -14, -34), Vector3(-18, -4, -22), Vector3(-11, 0.3, -15.5), Vector3(-7, 0.4, -12), Vector3(-4.5, 0.2, -9.5)],
		[Vector3(-8, -18, -40), Vector3(-4, -6, -26), Vector3(-3.0, 0.5, -16.0), Vector3(-2.2, 1.6, -13.2), Vector3(-1.8, 0.4, -10.5)],
		[Vector3(18, -18, -40), Vector3(10, -6, -25), Vector3(4.5, 0.6, -16.0), Vector3(2.5, 1.5, -13.0), Vector3(2.2, 0.3, -10.0)],
		[Vector3(30, -12, -26), Vector3(18, -3, -18), Vector3(12, 0.4, -12.5), Vector3(9.5, 0.3, -10.5)],
		[Vector3(-34, -8, -14), Vector3(-22, -2, -9), Vector3(-15.0, 0.3, -6.5), Vector3(-13, 0.2, -5.5)],
	]
	for c in curves:
		_root_curve(c, 1.6, 0.25, bark, vein)
	# сам Байтерек вдали — колоссальный ствол в дымке обрыва
	var trunk := Node3D.new()
	trunk.name = "Bayterek"
	trunk.position = Vector3(-34, -50, -75)
	add_child(trunk)
	HubProps.cyl(trunk, 7.0, 11.0, 90.0, Vector3(0, 45, 0), HubProps.mat(Color(0.12, 0.09, 0.08), 1.0), Vector3.ZERO, 20)
	for i in 6:
		var a := i * TAU / 6.0
		HubProps.cyl(trunk, 0.4, 0.6, 80.0, Vector3(cos(a) * 9.0, 40, sin(a) * 9.0), vein, Vector3(0, 0, 3), 6)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.3, 0.95, 0.8)
	glow.light_energy = 2.0
	glow.omni_range = 9.0
	glow.position = Vector3(0, 0.8, -14.5)
	add_child(glow)


## Корень — цепочка цилиндров вдоль ломаной, сужающаяся к концу, с тонкой светящейся жилкой.
func _root_curve(pts: Array, r0: float, r1: float, bark: Material, vein: Material) -> void:
	var n := pts.size() - 1
	for i in n:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var ra := lerpf(r0, r1, float(i) / n)
		var rb := lerpf(r0, r1, float(i + 1) / n)
		var len := a.distance_to(b) + rb * 0.8
		var mid := (a + b) * 0.5
		var dir := (b - a).normalized()
		var cm := CylinderMesh.new()
		cm.top_radius = rb
		cm.bottom_radius = ra
		cm.height = len
		cm.radial_segments = 10
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = bark
		mi.position = mid
		mi.basis = Basis(Quaternion(Vector3.UP, dir))
		add_child(mi)
		HubProps.sphere(self, rb * 1.05, b, bark, Vector3.ONE, 10)
		var vm := CylinderMesh.new()
		vm.top_radius = maxf(0.03, rb * 0.12)
		vm.bottom_radius = maxf(0.04, ra * 0.12)
		vm.height = len
		vm.radial_segments = 6
		var vi := MeshInstance3D.new()
		vi.mesh = vm
		vi.material_override = vein
		vi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var side := dir.cross(Vector3.UP).normalized()
		if side.length() < 0.1:
			side = Vector3.RIGHT
		vi.position = mid + (Vector3.UP * 0.7 + side * 0.7).normalized() * ((ra + rb) * 0.5 * 0.96)
		vi.basis = mi.basis
		add_child(vi)
		if b.y > -1.0:
			HubProps.solid_cyl(self, rb, 3.0, Vector3(b.x, 0.5, b.z))


func _gate(pos: Vector3) -> void:
	var g := Node3D.new()
	g.name = "TrailGate"
	g.position = pos
	add_child(g)
	var stone := HubProps.mat(Color(0.36, 0.33, 0.35), 0.9)
	for x in [-1.8, 1.8]:
		HubProps.box(g, Vector3(0.7, 3.6, 0.7), Vector3(x, 1.8, 0), stone)
		HubProps.box(g, Vector3(0.9, 0.3, 0.9), Vector3(x, 0.15, 0), stone)
		HubProps.solid_box(g, Vector3(0.7, 3.6, 0.7), Vector3(x, 1.8, 0))
		# руны-тамги, светятся бирюзой
		for k in 3:
			HubProps.box(g, Vector3(0.25, 0.25, 0.02), Vector3(x, 1.0 + k * 0.8, 0.36), HubProps.glow_mat(Color(0.3, 0.95, 0.8), 1.8), Vector3(0, 0, 45))
	HubProps.box(g, Vector3(4.9, 0.45, 0.9), Vector3(0, 3.75, 0), stone)
	HubProps.prism(g, Vector3(5.2, 0.6, 0.95), Vector3(0, 4.27, 0), Color(0.3, 0.27, 0.3))
	# туги-бунчуки
	for x in [-1.8, 1.8]:
		HubProps.cyl(g, 0.03, 0.03, 1.6, Vector3(x, 4.8, 0), HubProps.WOOD)
		HubProps.cyl(g, 0.02, 0.18, 0.6, Vector3(x, 5.3, 0), Color(0.15, 0.12, 0.1))
	# туман в проёме
	var plane := QuadMesh.new()
	plane.size = Vector2(3.0, 3.4)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.albedo_color = Color(0.3, 0.8, 0.75, 0.35)
	if ResourceLoader.exists("res://assets/fx/soft.png"):
		pm.albedo_texture = load("res://assets/fx/soft.png")
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pmi := MeshInstance3D.new()
	pmi.mesh = plane
	pmi.material_override = pm
	pmi.position = Vector3(0, 1.75, 0)
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(pmi)
	_gate_fog = CPUParticles3D.new()
	_gate_fog.amount = 30
	_gate_fog.lifetime = 3.0
	_gate_fog.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_gate_fog.emission_box_extents = Vector3(1.4, 0.2, 0.6)
	_gate_fog.direction = Vector3(0, 1, 0.3)
	_gate_fog.spread = 30.0
	_gate_fog.gravity = Vector3(0, 0.15, 0)
	_gate_fog.initial_velocity_min = 0.1
	_gate_fog.initial_velocity_max = 0.4
	_gate_fog.scale_amount_min = 1.0
	_gate_fog.scale_amount_max = 2.2
	var grad := Gradient.new()
	grad.set_color(0, Color(0.6, 0.9, 0.85, 0.0))
	grad.add_point(0.3, Color(0.6, 0.9, 0.85, 0.35))
	grad.set_color(1, Color(0.6, 0.9, 0.85, 0.0))
	_gate_fog.color_ramp = grad
	var fq := QuadMesh.new()
	fq.size = Vector2(1, 1)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.vertex_color_use_as_albedo = true
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	if ResourceLoader.exists("res://assets/fx/puff.png"):
		fm.albedo_texture = load("res://assets/fx/puff.png")
	fq.material = fm
	_gate_fog.mesh = fq
	_gate_fog.position = Vector3(0, 0.3, 0)
	g.add_child(_gate_fog)
	var gl := OmniLight3D.new()
	gl.light_color = Color(0.35, 0.95, 0.85)
	gl.light_energy = 1.8
	gl.omni_range = 5.0
	gl.position = Vector3(0, 2.0, 0.8)
	g.add_child(gl)
	HubProps.label(g, "Тропа в Корни", Vector3(0, 5.0, 0.6), Color(0.6, 1.0, 0.9), 46)
	gate = Interactable.new()
	gate.name = "TrailExit"
	gate.prompt = "Выйти на тропу"
	gate.radius = 1.8
	gate.position = Vector3(0, 0, 0.6)
	g.add_child(gate)
	gate.activated.connect(func(_p: Node): leave_to_trail())


func _npcs() -> void:
	for d in [["aje", Vector3(-1.9, 0.0, 1.4)], ["root", Vector3(4.2, 0.0, -10.0)], ["usta", Vector3(13.2, 0.0, -0.8)]]:
		var n := HubNpc.new()
		n.npc_id = d[0]
		n.name = "Npc_" + str(d[0])
		n.position = d[1]
		add_child(n)
		npcs[d[0]] = n


func _decor() -> void:
	# коновязь, бочонок кумыса, камни, балбал, трава-спрайты, кураи
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	HubProps.cyl(self, 0.35, 0.4, 0.9, Vector3(-4.0, 0.45, 3.5), Color(0.35, 0.22, 0.14))
	HubProps.torus(self, 0.33, 0.4, Vector3(-4.0, 0.7, 3.5), HubProps.IRON)
	for x in [-6.5, -4.5]:
		HubProps.cyl(self, 0.08, 0.1, 1.5, Vector3(x, 0.75, 6.0), HubProps.WOOD)
	HubProps.cyl(self, 0.05, 0.05, 2.2, Vector3(-5.5, 1.35, 6.0), HubProps.WOOD, Vector3(0, 0, 90))
	# балбал предка у края (смотрит на восток — сюжетная деталь)
	var bb := Node3D.new()
	bb.position = Vector3(-12.5, 0, 4.5)
	bb.rotation.y = PI / 2.0
	add_child(bb)
	HubProps.box(bb, Vector3(0.6, 2.0, 0.4), Vector3(0, 1.0, 0), HubProps.STONE.lightened(0.1))
	HubProps.sphere(bb, 0.32, Vector3(0, 2.2, 0), HubProps.STONE.lightened(0.1), Vector3(1, 1.1, 0.8))
	HubProps.solid_box(bb, Vector3(0.6, 2.0, 0.4), Vector3(0, 1.0, 0))
	for i in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(4.0, 14.5)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if p.distance_to(Vector3(-9, 0, -2.5)) < 4.0 or p.distance_to(Vector3(8.5, 0, -3.5)) < 5.5 or absf(p.x) < 1.5 and p.z < 0:
			continue
		if rng.randf() < 0.65:
			var tex := "res://assets/bg/grass_%d.png" % rng.randi_range(0, 5)
			var s := HubProps.sprite(self, tex, p + Vector3(0, 0.3, 0), 0.006, true, Color(0.85, 0.8, 0.6))
			if s:
				s.offset = Vector2(0, s.texture.get_height() * 0.5) if s.texture else Vector2.ZERO
				s.position.y = 0.0
				s.shaded = true
		else:
			var st := HubProps.sphere(self, rng.randf_range(0.2, 0.5), p, HubProps.STONE.lightened(rng.randf() * 0.2), Vector3(1.3, 0.6, 1.0), 8)
			st.rotation.y = rng.randf() * TAU
	# курган с камнями-рунами у западного края (спрайт)
	var k := HubProps.sprite(self, "res://assets/bg/kurgan_0.png", Vector3(-11.5, 0, -9.0), 0.018, true, Color(0.95, 0.85, 0.85))
	if k and k.texture:
		k.offset = Vector2(0, k.texture.get_height() * 0.5)
		k.shaded = true


func _backdrop() -> void:
	# закатное небо и силуэты — плоскости перед камерой «на бесконечности» (без тумана), курганы/руины — с параллаксом
	_bg_rig = Node3D.new()
	_bg_rig.name = "Backdrop"
	_bg_rig.top_level = true
	add_child(_bg_rig)
	_add_bg_layer("res://assets/bg/sky_day.jpg", 140.0, 1.0, 150.0, Vector2(0, 0.08), Color(1, 0.92, 0.9))
	_add_bg_layer("res://assets/bg/ruins_far_0.png", 100.0, 0.8, 70.0, Vector2(-0.18, -0.2), Color(0.75, 0.5, 0.45))
	_add_bg_layer("res://assets/bg/kurgan_0.png", 85.0, 0.7, 30.0, Vector2(0.3, -0.24), Color(0.7, 0.5, 0.5))


func _add_bg_layer(path: String, dist: float, follow: float, width: float, offs: Vector2, tint: Color) -> void:
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	var q := QuadMesh.new()
	var h := width * float(tex.get_height()) / float(tex.get_width())
	q.size = Vector2(width, h)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.albedo_color = tint
	m.disable_fog = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if path.ends_with(".png") else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.render_priority = -10
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bg_rig.add_child(mi)
	# offs — смещение в долях высоты видимой области (x — вправо, y — вверх)
	_bg_layers.append([mi, dist, follow, offs])


func _update_backdrop() -> void:
	var c := get_viewport().get_camera_3d()
	if c == null or _bg_rig == null:
		return
	var b := c.global_basis.orthonormalized()
	for L in _bg_layers:
		var mi: MeshInstance3D = L[0]
		var dist: float = L[1]
		var follow: float = L[2]
		var offs: Vector2 = L[3]
		var vis_h := 2.0 * dist * tan(deg_to_rad(c.fov * 0.5))
		var home := Vector3(10.0, 12.8, 13.6)   # примерное положение камеры, когда герой у костра
		var p := c.global_position + (-b.z) * dist + b.x * offs.x * vis_h + b.y * offs.y * vis_h
		p -= (c.global_position - home) * (1.0 - follow)
		mi.global_transform = Transform3D(b, p)


# ================================================================ прозрачность заслоняющих объектов
## Меши становятся полупрозрачными, когда закрывают героя от камеры или герой стоит под ними (кровля оружейной).
func add_fader(meshes: Array, near := 0.0) -> void:
	if meshes.is_empty():
		return
	_faders.append({"meshes": meshes, "aabb": AABB(), "cur": 0.0, "ready": false, "near": near})


func _update_faders(delta: float) -> void:
	var c := get_viewport().get_camera_3d()
	if c == null or player == null or not is_instance_valid(player) or not player.visible:
		return
	var a := c.global_position
	var targets := [player.global_position + Vector3(0, 1.0, 0), player.global_position + Vector3(0, 0.2, 0)]
	for f in _faders:
		if not f["ready"]:
			var box := AABB()
			var first := true
			for m in f["meshes"]:
				if not is_instance_valid(m):
					continue
				var bb: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
				box = bb if first else box.merge(bb)
				first = false
			f["aabb"] = box.grow(0.4)
			f["ready"] = true
		var box2: AABB = f["aabb"]
		var hide := false
		for b in targets:
			if box2.intersects_segment(a, b):
				hide = true
		var p := player.global_position
		var near: float = f.get("near", 0.0)
		if p.x > box2.position.x - near and p.x < box2.end.x + near and p.z > box2.position.z - near and p.z < box2.end.z + near and p.y < box2.position.y:
			hide = true
		var goal := 0.8 if hide else 0.0
		var cur: float = f["cur"]
		if absf(cur - goal) < 0.005:
			continue
		cur = move_toward(cur, goal, delta * 3.0)
		f["cur"] = cur
		for m in f["meshes"]:
			if is_instance_valid(m):
				_set_fade(m as MeshInstance3D, cur)


## Прозрачность через копию материала (работает и в Forward+, и в Compatibility); при 0 — исходный материал.
func _set_fade(m: MeshInstance3D, amount: float) -> void:
	if not m.has_meta("orig_mat"):
		m.set_meta("orig_mat", m.material_override)
	var orig: Material = m.get_meta("orig_mat")
	if amount <= 0.001:
		m.material_override = orig
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		return
	var fm: StandardMaterial3D
	if m.has_meta("fade_mat"):
		fm = m.get_meta("fade_mat")
	else:
		fm = (orig as StandardMaterial3D).duplicate() if orig is StandardMaterial3D else StandardMaterial3D.new()
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		m.set_meta("fade_mat", fm)
	var c := fm.albedo_color
	c.a = 1.0 - amount
	fm.albedo_color = c
	m.material_override = fm


# ================================================================ камера
func _attach_camera() -> void:
	if ResourceLoader.exists(GAME_CAMERA):
		var scr = load(GAME_CAMERA)
		if scr is GDScript and (scr as GDScript).can_instantiate():
			var c = scr.attach(self, player)
			if c is Camera3D:
				cam = c
				if cam.has_method("set_bounds"):
					cam.set_bounds(AABB(Vector3(-11, -2, -11), Vector3(23, 6, 21)))
				return
	# запасная камера: 40° сверху, азимут 45°, следует за героем
	_fallback_cam = true
	cam = Camera3D.new()
	cam.name = "HubCamera"
	cam.fov = 32.0
	cam.rotation_degrees = Vector3(-40, 45, 0)
	add_child(cam)
	cam.make_current()
	_follow_fallback(1.0)


func _follow_fallback(k: float) -> void:
	if cam == null or player == null or not is_instance_valid(player):
		return
	var focus := player.global_position + Vector3(0, 0.9, 0)
	var back := cam.global_basis.z.normalized()
	var goal := focus + back * 18.5
	cam.global_position = cam.global_position.lerp(goal, k)


# ================================================================ домбра и выход
func open_dombra(p: Node = null) -> DombraMode:
	if dombra_mode and is_instance_valid(dombra_mode):
		return dombra_mode
	if p == null:
		p = player
	dombra_mode = DombraMode.open(self, dombra_model, p)
	if p is Node3D:
		(p as Node3D).visible = false
	dombra_mode.kui_done.connect(_on_kui_done)
	dombra_mode.closed.connect(func():
		if p and is_instance_valid(p):
			(p as Node3D).visible = true
		dombra_mode = null)
	return dombra_mode


func _on_kui_done(_id: String) -> void:
	# костёр вспыхивает бирюзой
	if _fire_light:
		var tw := create_tween()
		_fire_light.light_color = Color(0.4, 1.0, 0.85)
		tw.tween_property(_fire_light, "light_color", Color(1.0, 0.62, 0.28), 2.5)
	Fx3D.ring(self, Vector3(0, 0.1, 0), 3.0, Color(0.4, 1.0, 0.85), 0.8)


func leave_to_trail() -> void:
	if _leaving:
		return
	_leaving = true
	if Meta.kui_prepared != "":
		Bus.toast.emit("Музыкальный заряд «%s» звучит в тебе" % KuiData.title(Meta.kui_prepared), Color(0.4, 0.95, 0.85))
	else:
		Bus.toast.emit("Тропа в Корни Байтерека", Color(0.88, 0.72, 0.36))
	Sfx.play("door")
	Sfx.play("teleport", -6.0)
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(false)
	if player:
		Fx3D.ring(self, player.global_position, 2.0, Color(0.35, 0.95, 0.8), 0.6)
	await get_tree().create_timer(0.7).timeout
	Run.start_run()


# ================================================================ кадр
func _process(delta: float) -> void:
	_t += delta
	if _fire_light:
		var f := sin(_t * 9.0) * 0.25 + sin(_t * 23.0 + 1.3) * 0.15 + randf_range(-0.12, 0.12)
		_fire_light.light_energy = _fire_base + f
	if _fallback_cam and not (dombra_mode and is_instance_valid(dombra_mode)):
		_follow_fallback(1.0 - exp(-delta * 6.0))
	_update_backdrop()
	_update_faders(delta)
