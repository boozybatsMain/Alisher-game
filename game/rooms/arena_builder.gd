class_name ArenaBuilder
extends Node3D
## Процедурная модульная арена (модуль D) по шаблону (ArenaLayouts), биому и seed.
## Биомы: 0 — Осквернённая степь (охра, трава, курганы, закат), 1 — Корни Байтерека (гигантские корни,
## бирюзово-тёмные, светящиеся), 2 — Чертог Ерлика (тёмный камень, фиолетовая Мгла).
##
## Арена стоит на «плато»: северная и западная кромки — низкие парапеты с кусками высоких резных стен
## (для бега по стене/отскока, плиты "wall_plate"), за ними обрыв в туман и 2D-задники степи (слои с параллаксом).
## Южная и восточная (ближние к камере) стены — низкие, коллизия у всех краёв высокая (невидимая).
##
## Использование:
##   var arena := ArenaBuilder.create(parent, "terraces", biome, seed)
##   arena.spawn_player, arena.spawn_points (Array[Vector3] на разных ярусах), arena.door_slots, arena.reward_point,
##   arena.bounds (AABB), arena.layout_id, arena.layout (Dictionary шаблона)
## Сверх: height_at(x, z) -> float (высота пола/яруса; -INF над пропастью), is_pit(x, z, margin),
##   tier_points(min_h) — точки спавна на ярусах ≥ min_h, random_floor_point(rng, min_dist_from, dist),
##   BIOME_COLORS — палитры биомов, extra_points (merchant/goods/well/boss из шаблона).

const WALL_LAYER := 1
const COLLIDER_H := 14.0
const PARAPET_H := 1.1
const VOID_Y := -34.0

## Палитры биомов.
const BIOME_COLORS := [
	{   # 0 — Осквернённая степь: охра, войлок, закат
		"floor": Color(0.6, 0.47, 0.34), "floor2": Color(0.44, 0.34, 0.25), "stone": Color(0.48, 0.43, 0.39),
		"dark": Color(0.27, 0.22, 0.2), "accent": Color(0.25, 0.68, 0.64), "felt": Color(0.58, 0.22, 0.15),
		"wood": Color(0.42, 0.28, 0.17), "glow": Color(1.0, 0.62, 0.3), "fire": Color(1.0, 0.6, 0.25),
		"sun": Color(1.0, 0.8, 0.62), "sun_energy": 1.1, "sun_rot": Vector3(-38, -115, 0),
		"bg": Color(0.42, 0.27, 0.24), "fog": Color(0.78, 0.5, 0.36), "fog_density": 0.006,
		"ambient": Color(0.55, 0.5, 0.56), "ambient_energy": 0.45, "particles": Color(1.0, 0.75, 0.5, 0.55),
		"sky": "res://assets/bg/sky_day.jpg", "ruins": "ruins_far_%d", "grass": true,
	},
	{   # 1 — Корни Байтерека: бирюза, тёмная кора, светящиеся жилы
		# пол — тёплая тёмная кора, ярусы — светлый серо-зелёный камень, бирюза только в акцентах/свете:
		# так уровни высоты и пропасти читаются, а не сливаются в один оттенок.
		"floor": Color(0.3, 0.24, 0.18), "floor2": Color(0.22, 0.17, 0.13), "stone": Color(0.5, 0.55, 0.52),
		"dark": Color(0.1, 0.11, 0.12), "accent": Color(0.3, 1.0, 0.88), "felt": Color(0.3, 0.2, 0.15),
		"wood": Color(0.33, 0.23, 0.17), "glow": Color(0.35, 1.0, 0.9), "fire": Color(0.35, 0.95, 0.85),
		"sun": Color(0.92, 0.9, 0.86), "sun_energy": 1.1, "sun_rot": Vector3(-50, -140, 0),
		"bg": Color(0.07, 0.15, 0.17), "fog": Color(0.08, 0.16, 0.18), "fog_density": 0.006,
		"ambient": Color(0.36, 0.42, 0.44), "ambient_energy": 0.42, "particles": Color(0.45, 1.0, 0.9, 0.7),
		"plat_light": 0.25, "edge_glow": true,
		"sky": "res://assets/bg/sky_night.jpg", "ruins": "ruins_night_%d", "grass": false,
	},
	{   # 2 — Чертог Ерлика: тёмный камень, фиолетовая Мгла
		"floor": Color(0.26, 0.25, 0.28), "floor2": Color(0.17, 0.16, 0.19), "stone": Color(0.32, 0.3, 0.34),
		"dark": Color(0.1, 0.08, 0.12), "accent": Color(0.7, 0.35, 1.0), "felt": Color(0.35, 0.12, 0.2),
		"wood": Color(0.25, 0.18, 0.16), "glow": Color(0.72, 0.35, 1.0), "fire": Color(0.75, 0.4, 1.0),
		"sun": Color(0.85, 0.78, 1.0), "sun_energy": 0.85, "sun_rot": Vector3(-55, -100, 0),
		"bg": Color(0.1, 0.05, 0.14), "fog": Color(0.26, 0.12, 0.36), "fog_density": 0.007,
		"ambient": Color(0.38, 0.33, 0.45), "ambient_energy": 0.5, "particles": Color(0.8, 0.45, 1.0, 0.7),
		"sky": "res://assets/bg/sky_night.jpg", "ruins": "ruins_night_%d", "grass": false,
	},
]

var layout_id := ""
var layout: Dictionary = {}
var biome := 0
var arena_seed := 0
var pal: Dictionary = {}
var rng := RandomNumberGenerator.new()

var spawn_player := Vector3.ZERO
var spawn_points: Array[Vector3] = []
var door_slots: Array[Vector3] = []
var reward_point := Vector3.ZERO
var bounds := AABB()
var extra_points := {}

var _hx := 15.0
var _hz := 12.0
var _round := false
var _radius := 13.0
var _blocks: Array = []        ## [x0, z0, x1, z1, h] — всё, что задаёт высоту пола (ярусы + ступени)
var _pits: Array = []
var _obstacles: Array = []     ## [x, z, r] — колонны, столбы
var _parallax: Array = []      ## [{node, base, factor}]
var _cam_origin = null
var _anchor_screen = null      ## экранная позиция центра арены в первом кадре (для 2D-параллакса)
var backdrop_2d: ArenaBackdrop = null
var _m := {}                   ## материалы биома


static func create(parent: Node, p_layout: String, p_biome: int, p_seed: int) -> ArenaBuilder:
	var a := ArenaBuilder.new()
	a.name = "Arena"
	a.build(p_layout, p_biome, p_seed)
	if parent:
		parent.add_child(a)
	return a


func build(p_layout: String, p_biome: int, p_seed: int) -> void:
	layout_id = p_layout if ArenaLayouts.T.has(p_layout) else "terraces"
	layout = ArenaLayouts.get_layout(layout_id)
	biome = clampi(p_biome, 0, BIOME_COLORS.size() - 1)
	arena_seed = p_seed
	rng.seed = p_seed
	pal = BIOME_COLORS[biome]
	_hx = float(layout["half"][0])
	_hz = float(layout["half"][1])
	_round = String(layout.get("shape", "rect")) == "round"
	_radius = float(layout.get("radius", 13.0))
	_make_materials()
	_collect_blocks()
	_build_env()
	_build_floor()
	_build_edges()
	_build_plats()
	_build_pits()
	_build_cols()
	_build_bridges()
	_build_bars()
	_build_tall_walls()
	_build_decor()
	_build_torches()
	_build_jars()
	_build_backdrop()
	_build_particles()
	_compute_points()


# ================================================================ материалы
func _noise_tex(c1: Color, c2: Color, freq := 0.04, size := 256) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = arena_seed % 10000
	n.frequency = freq
	n.fractal_octaves = 4
	var g := Gradient.new()
	g.set_color(0, c2)
	g.set_color(1, c1)
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.color_ramp = g
	return t


func _tri_mat(c1: Color, c2: Color, scale := 0.25, rough := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex(c1, c2)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.roughness = rough
	return m


func _make_materials() -> void:
	var p := pal
	_m["floor"] = _tri_mat(p["floor"], p["floor2"], 0.12)
	_m["stone"] = _tri_mat(p["stone"], (p["stone"] as Color).darkened(0.3), 0.3)
	_m["dark"] = _tri_mat(p["dark"], (p["dark"] as Color).darkened(0.4), 0.3)
	var plat_top := (p["stone"] as Color).lerp(p["floor"], 0.35).lightened(float(p.get("plat_light", 0.0)))
	_m["plat"] = _tri_mat(plat_top, (p["dark"] as Color).lerp(p["stone"], 0.4), 0.22)
	_m["wood"] = RoomUtil.mat(p["wood"], 0.85)
	_m["rope"] = RoomUtil.mat(Color(0.62, 0.52, 0.36), 1.0)
	_m["accent"] = RoomUtil.mat(p["accent"], 0.6, p["accent"], 0.6 if biome == 0 else 1.8)
	_m["felt"] = RoomUtil.mat(p["felt"], 1.0)
	_m["glow"] = RoomUtil.glow_mat(p["glow"], 2.2)
	_m["void"] = RoomUtil.mat(p["dark"], 1.0)


# ================================================================ разметка
func _collect_blocks() -> void:
	_blocks.clear()
	for b in layout.get("plats", []):
		_blocks.append([float(b[0]), float(b[1]), float(b[2]), float(b[3]), float(b[4])])
	for s in layout.get("stairs", []):
		for st in _stair_steps(s):
			_blocks.append(st)
	_pits.clear()
	for pt in layout.get("pits", []):
		_pits.append([float(pt[0]), float(pt[1]), float(pt[2]), float(pt[3])])


## Ступени: [x, z, dx, dz, h_top, width] → блоки [x0, z0, x1, z1, h].
func _stair_steps(s: Array) -> Array:
	var out := []
	var x := float(s[0])
	var z := float(s[1])
	var dx := float(s[2])
	var dz := float(s[3])
	var top := float(s[4])
	var w := float(s[5])
	var n := int(roundf(top)) - 1
	var base := top - float(n) - 1.0   # если ступени стоят на ярусе — их низ всё равно на земле
	for i in range(n):
		var h := top - float(i + 1)
		if h <= base:
			break
		var cx := x + dx * (i + 0.5)
		var cz := z + dz * (i + 0.5)
		var sx := 1.0 if absf(dx) > 0.5 else w
		var sz := 1.0 if absf(dz) > 0.5 else w
		out.append([cx - sx * 0.5, cz - sz * 0.5, cx + sx * 0.5, cz + sz * 0.5, h])
	return out


func in_bounds(x: float, z: float, margin := 0.0) -> bool:
	if _round:
		return Vector2(x, z).length() <= _radius - margin
	return absf(x) <= _hx - margin and absf(z) <= _hz - margin


func is_pit(x: float, z: float, margin := 0.0) -> bool:
	for p in _pits:
		if x > p[0] - margin and x < p[2] + margin and z > p[1] - margin and z < p[3] + margin:
			return true
	return false


## Высота поверхности в точке (0 — пол, 3/6 — ярусы); -INF над пропастью или вне арены.
func height_at(x: float, z: float) -> float:
	if not in_bounds(x, z) or is_pit(x, z):
		return -INF
	var h := 0.0
	for b in _blocks:
		if x >= b[0] and x <= b[2] and z >= b[1] and z <= b[3]:
			h = maxf(h, b[4])
	return h


func _near_obstacle(x: float, z: float, r: float) -> bool:
	for o in _obstacles:
		if Vector2(x - o[0], z - o[1]).length() < r + o[2]:
			return true
	return false


## Ровное место (все точки в радиусе r на одной высоте).
func _flat(x: float, z: float, r: float) -> bool:
	var h := height_at(x, z)
	if h == -INF:
		return false
	for o in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r), Vector2(r, r) * 0.7, Vector2(-r, -r) * 0.7, Vector2(r, -r) * 0.7, Vector2(-r, r) * 0.7]:
		if not is_equal_approx(height_at(x + o.x, z + o.y), h):
			return false
	return true


# ================================================================ окружение и свет
func _build_env() -> void:
	var we := WorldEnvironment.new()
	we.name = "Env"
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = ArenaBackdrop.LAYER
	env.background_color = pal["bg"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = pal["ambient"]
	env.ambient_light_energy = float(pal["ambient_energy"])
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT if biome == 0 else Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_light_color = pal["fog"]
	env.fog_density = float(pal["fog_density"])
	env.fog_sky_affect = 0.0
	env.fog_height = -3.0
	env.fog_height_density = 0.12
	env.fog_aerial_perspective = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.05
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = pal["sun"]
	sun.light_energy = float(pal["sun_energy"])
	sun.rotation_degrees = pal["sun_rot"]
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	# мягкая контровая подсветка цвета Мглы/неба
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.light_color = (pal["accent"] as Color).lerp(pal["fog"], 0.5)
	rim.light_energy = 0.25
	rim.rotation_degrees = Vector3(-25, 60, 0)
	rim.shadow_enabled = false
	add_child(rim)


# ================================================================ пол, кромки, стены
func _build_floor() -> void:
	if _round:
		return
	var root := Node3D.new()
	root.name = "Floor"
	add_child(root)
	var x0 := -_hx
	var x1 := _hx
	var z0 := -_hz
	var z1 := _hz
	# разбиение на клетки по краям пропастей; клетки внутри пропастей пропускаются, ряды склеиваются
	var xs := [x0, x1]
	var zs := [z0, z1]
	for p in _pits:
		xs.append_array([clampf(p[0], x0, x1), clampf(p[2], x0, x1)])
		zs.append_array([clampf(p[1], z0, z1), clampf(p[3], z0, z1)])
	xs = _uniq_sorted(xs)
	zs = _uniq_sorted(zs)
	for j in range(zs.size() - 1):
		var za: float = zs[j]
		var zb: float = zs[j + 1]
		var run_start := NAN
		for i in range(xs.size() - 1):
			var xa: float = xs[i]
			var xb: float = xs[i + 1]
			var pit := is_pit((xa + xb) * 0.5, (za + zb) * 0.5)
			if not pit and is_nan(run_start):
				run_start = xa
			if pit and not is_nan(run_start):
				_floor_slab(root, run_start, za, xa, zb)
				run_start = NAN
		if not is_nan(run_start):
			_floor_slab(root, run_start, za, x1, zb)


func _uniq_sorted(a: Array) -> Array:
	a.sort()
	var out := []
	for v in a:
		if out.is_empty() or absf(float(v) - float(out[-1])) > 0.01:
			out.append(v)
	return out


func _floor_slab(root: Node3D, xa: float, za: float, xb: float, zb: float) -> void:
	var size := Vector3(xb - xa, 1.0, zb - za)
	RoomUtil.solid_box(root, Vector3((xa + xb) * 0.5, -0.5, (za + zb) * 0.5), size, _m["floor"], WALL_LAYER)


func _build_edges() -> void:
	var root := Node3D.new()
	root.name = "Edges"
	add_child(root)
	if _round:
		_build_round_edges(root)
		return
	var hx := _hx
	var hz := _hz
	# невидимые высокие коллайдеры по периметру
	RoomUtil.solid_box(root, Vector3(0, COLLIDER_H * 0.5 - 1, -hz - 0.5), Vector3(hx * 2 + 2, COLLIDER_H, 1), null, WALL_LAYER, false)
	RoomUtil.solid_box(root, Vector3(0, COLLIDER_H * 0.5 - 1, hz + 0.5), Vector3(hx * 2 + 2, COLLIDER_H, 1), null, WALL_LAYER, false)
	RoomUtil.solid_box(root, Vector3(-hx - 0.5, COLLIDER_H * 0.5 - 1, 0), Vector3(1, COLLIDER_H, hz * 2 + 2), null, WALL_LAYER, false)
	RoomUtil.solid_box(root, Vector3(hx + 0.5, COLLIDER_H * 0.5 - 1, 0), Vector3(1, COLLIDER_H, hz * 2 + 2), null, WALL_LAYER, false)
	# видимые парапеты: север/запад — каменные зубцы, юг/восток — низкий бортик
	_parapet(root, Vector3(-hx - 0.5, 0, -hz - 0.5), Vector3(hx + 0.5, 0, -hz - 0.5), PARAPET_H, true)
	_parapet(root, Vector3(-hx - 0.5, 0, -hz - 0.5), Vector3(-hx - 0.5, 0, hz + 0.5), PARAPET_H, true)
	_parapet(root, Vector3(-hx - 0.5, 0, hz + 0.5), Vector3(hx + 0.5, 0, hz + 0.5), 0.45, false)
	_parapet(root, Vector3(hx + 0.5, 0, -hz - 0.5), Vector3(hx + 0.5, 0, hz + 0.5), 0.45, false)
	# обрыв (утёс) под плато
	_cliff(root, Vector3(-hx - 1, 0, -hz - 1), Vector3(hx + 1, 0, -hz - 1))
	_cliff(root, Vector3(-hx - 1, 0, -hz - 1), Vector3(-hx - 1, 0, hz + 1))
	_cliff(root, Vector3(-hx - 1, 0, hz + 1), Vector3(hx + 1, 0, hz + 1))
	_cliff(root, Vector3(hx + 1, 0, -hz - 1), Vector3(hx + 1, 0, hz + 1))


func _build_round_edges(root: Node3D) -> void:
	var segs := 28
	var r := _radius + 0.5
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var mid := (p0 + p1) * 0.5
		var length := p0.distance_to(p1) + 0.3
		var body := StaticBody3D.new()
		body.collision_layer = WALL_LAYER
		body.position = mid + Vector3(0, COLLIDER_H * 0.5 - 1, 0)
		body.rotation.y = -atan2(mid.z, mid.x) + PI * 0.5
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(length, COLLIDER_H, 1.0)
		cs.shape = sh
		body.add_child(cs)
		root.add_child(body)
		# видимая часть: север/запад — высокие обломки стен, юг/восток — низкий бортик
		var far_side := mid.z < 2.0 and mid.x < 6.0 or mid.z < -6.0
		var h := PARAPET_H if far_side else 0.45
		if far_side and i % 3 == 0:
			h = rng.randf_range(4.0, 7.0)
		var vis := MeshInstance3D.new()
		vis.mesh = RoomUtil.box_mesh(Vector3(length, h + 1.0, 1.0))
		vis.material_override = _m["stone"]
		vis.position = Vector3(0, -COLLIDER_H * 0.5 + 1 + (h + 1.0) * 0.5 - 1.0, 0)
		body.add_child(vis)
		if far_side and h > 3.0:
			body.add_to_group("wall_plate")
			_plate_ornament(vis, Vector3(0, (h + 1.0) * 0.5 - 1.6, 0.52), Vector2(minf(length - 0.6, 2.2), 2.0))
	# пол — круг (снаружи — утёс)
	_cliff_ring(root)


func _parapet(root: Node3D, a: Vector3, b: Vector3, h: float, crenel: bool) -> void:
	var mid := (a + b) * 0.5
	var length := a.distance_to(b) + 1.0
	var along_x := absf(b.x - a.x) > absf(b.z - a.z)
	var size := Vector3(length, h + 1.0, 1.0) if along_x else Vector3(1.0, h + 1.0, length)
	RoomUtil.mesh(root, RoomUtil.box_mesh(size), mid + Vector3(0, (h + 1.0) * 0.5 - 1.0, 0), _m["stone"])
	if crenel:
		var n := int(length / 1.6)
		for i in n:
			if rng.randf() < 0.25:
				continue
			var t := (i + 0.5) / n
			var p := a.lerp(b, t)
			var cs := Vector3(0.7, 0.5, 1.05) if along_x else Vector3(1.05, 0.5, 0.7)
			RoomUtil.mesh(root, RoomUtil.box_mesh(cs), p + Vector3(0, h + 0.25, 0), _m["stone"])
	else:
		# узкая бирюзовая/войлочная кайма
		var trim := Vector3(length, 0.08, 1.05) if along_x else Vector3(1.05, 0.08, length)
		RoomUtil.mesh(root, RoomUtil.box_mesh(trim), mid + Vector3(0, h + 0.04, 0), _m["dark"], false)


func _cliff(root: Node3D, a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	var dir := (b - a).normalized()
	var n := int(length / 3.0) + 1
	for i in n:
		var t0 := float(i) / n
		var p := a.lerp(b, t0 + 0.5 / n)
		var depth := rng.randf_range(12.0, 26.0)
		var w := length / n + 0.6
		var th := rng.randf_range(2.0, 3.5)
		var size := Vector3(w, depth, th) if absf(dir.x) > 0.5 else Vector3(th, depth, w)
		var out := Vector3(-dir.z, 0, dir.x)
		# смещаем «наружу» арены
		if out.dot(p) < 0.0:
			out = -out
		RoomUtil.mesh(root, RoomUtil.box_mesh(size), p + out * (th * 0.5 - 0.6) + Vector3(0, -depth * 0.5 - 0.2, 0), _m["dark"], false)
		if biome == 1 and rng.randf() < 0.6:
			_hanging_root(root, p + out * 0.4 + Vector3(0, -0.8, 0))


func _cliff_ring(root: Node3D) -> void:
	# снаружи круга — сплошной каменный пояс на уровне пола (чтобы углы квадратного пола не выглядели пустыми)
	var segs := 20
	for i in segs:
		var a := TAU * (i + 0.5) / segs
		var p := Vector3(cos(a), 0, sin(a)) * (_radius + 2.5)
		var ch := rng.randf_range(16.0, 26.0)
		var mi := RoomUtil.mesh(root, RoomUtil.box_mesh(Vector3(5.5, ch, 4.0)), p + Vector3(0, -ch * 0.5 - 0.3, 0), _m["dark"], false)
		mi.rotation.y = -a + PI * 0.5
	# круглый пол: коллизия — цилиндр, видимый — цилиндр-меш
	var body := StaticBody3D.new()
	body.collision_layer = WALL_LAYER
	body.position = Vector3(0, -0.5, 0)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = _radius + 1.0
	sh.height = 1.0
	cs.shape = sh
	body.add_child(cs)
	RoomUtil.mesh(body, RoomUtil.cyl_mesh(_radius + 1.0, _radius + 1.0, 1.0, 48), Vector3.ZERO, _m["floor"])
	root.add_child(body)
	# мозаика-круги на полу
	for k in 3:
		var ring := RoomUtil.mesh(root, RoomUtil.cyl_mesh(4.0 + k * 3.5, 4.0 + k * 3.5, 0.02, 48), Vector3(0, 0.005 + k * 0.002, 0),
			RoomUtil.mat((pal["accent"] as Color).darkened(0.5 - k * 0.1), 0.8, pal["accent"], 0.3 if biome == 0 else 0.9), false)
		ring.scale = Vector3(1, 1, 1)
		var inner := RoomUtil.mesh(root, RoomUtil.cyl_mesh(3.6 + k * 3.5, 3.6 + k * 3.5, 0.03, 48), Vector3(0, 0.006 + k * 0.002, 0), _m["floor"], false)
		inner.scale = Vector3(1, 1, 1)


# ================================================================ ярусы, ступени
func _build_plats() -> void:
	var root := Node3D.new()
	root.name = "Tiers"
	add_child(root)
	for b in layout.get("plats", []):
		var x0 := float(b[0])
		var z0 := float(b[1])
		var x1 := float(b[2])
		var z1 := float(b[3])
		var h := float(b[4])
		var size := Vector3(x1 - x0, h, z1 - z0)
		var body := RoomUtil.solid_box(root, Vector3((x0 + x1) * 0.5, h * 0.5, (z0 + z1) * 0.5), size, _m["plat"], WALL_LAYER)
		body.add_to_group("tier")
		# карниз-уступ по кромке (визуально подчёркивает край для зацепа)
		var lip := RoomUtil.mesh(body, RoomUtil.box_mesh(Vector3(size.x + 0.16, 0.18, size.z + 0.16)), Vector3(0, h * 0.5 - 0.09, 0), _m["stone"])
		lip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if pal.get("edge_glow", false):
			_edge_strips(body, size, h * 0.5 + 0.005)
		# орнамент на южной и восточной гранях (видимы камере)
		if h >= 2.5:
			var band := RoomUtil.mesh(body, RoomUtil.box_mesh(Vector3(size.x * 0.9, 0.12, 0.04)), Vector3(0, h * 0.5 - 0.6, size.z * 0.5 + 0.02), _m["accent"], false)
			band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var band2 := RoomUtil.mesh(body, RoomUtil.box_mesh(Vector3(0.04, 0.12, size.z * 0.9)), Vector3(size.x * 0.5 + 0.02, h * 0.5 - 0.6, 0), _m["accent"], false)
			band2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# опорные пилястры по углам
			for c in [Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1)]:
				RoomUtil.mesh(body, RoomUtil.box_mesh(Vector3(0.5, h, 0.5)), Vector3(c.x * size.x * 0.5, 0, c.y * size.z * 0.5), _m["stone"])
		if biome == 0 and h >= 2.5 and rng.randf() < 0.7:
			# войлочный полог/ковёр на балконе
			var rug := RoomUtil.mesh(body, RoomUtil.box_mesh(Vector3(minf(size.x - 1.0, 3.0), 0.04, minf(size.z - 1.0, 2.0))), Vector3(0, h * 0.5 + 0.02, 0), _m["felt"], false)
			rug.rotation.y = rng.randf_range(-0.2, 0.2)
	for s in layout.get("stairs", []):
		for st in _stair_steps(s):
			var size := Vector3(st[2] - st[0], st[4], st[3] - st[1])
			var body := RoomUtil.solid_box(root, Vector3((st[0] + st[2]) * 0.5, st[4] * 0.5, (st[1] + st[3]) * 0.5), size, _m["stone"], WALL_LAYER)
			body.add_to_group("tier")


## Светящиеся accent-полосы по верхним кромкам яруса (как у плит для отскока): читается высота и край.
func _edge_strips(body: Node3D, size: Vector3, y: float) -> void:
	var t := 0.09
	for e in [
		[Vector3(size.x + 0.16, 0.05, t), Vector3(0, y, size.z * 0.5 + 0.08)],
		[Vector3(size.x + 0.16, 0.05, t), Vector3(0, y, -size.z * 0.5 - 0.08)],
		[Vector3(t, 0.05, size.z + 0.16), Vector3(size.x * 0.5 + 0.08, y, 0)],
		[Vector3(t, 0.05, size.z + 0.16), Vector3(-size.x * 0.5 - 0.08, y, 0)],
	]:
		var m := RoomUtil.mesh(body, RoomUtil.box_mesh(e[0]), e[1], _m["accent"], false)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ================================================================ пропасти
func _build_pits() -> void:
	var root := Node3D.new()
	root.name = "Pits"
	add_child(root)
	var soft := RoomUtil.tex("res://assets/fx/soft.png")
	for p in _pits:
		var x0: float = p[0]
		var z0: float = p[1]
		var x1: float = p[2]
		var z1: float = p[3]
		var c := Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
		var w := x1 - x0
		var d := z1 - z0
		var depth := 14.0
		# стенки провала
		RoomUtil.mesh(root, RoomUtil.box_mesh(Vector3(w, depth, 0.4)), Vector3(c.x, -depth * 0.5, z0 + 0.2), _m["dark"], false)
		RoomUtil.mesh(root, RoomUtil.box_mesh(Vector3(w, depth, 0.4)), Vector3(c.x, -depth * 0.5, z1 - 0.2), _m["dark"], false)
		RoomUtil.mesh(root, RoomUtil.box_mesh(Vector3(0.4, depth, d)), Vector3(x0 + 0.2, -depth * 0.5, c.z), _m["dark"], false)
		RoomUtil.mesh(root, RoomUtil.box_mesh(Vector3(0.4, depth, d)), Vector3(x1 - 0.2, -depth * 0.5, c.z), _m["dark"], false)
		if pal.get("edge_glow", false):
			# светящаяся кромка провала — пропасть видна издалека
			for e in [[Vector3(w, 0.04, 0.08), Vector3(c.x, 0.03, z0)], [Vector3(w, 0.04, 0.08), Vector3(c.x, 0.03, z1)],
					[Vector3(0.08, 0.04, d), Vector3(x0, 0.03, c.z)], [Vector3(0.08, 0.04, d), Vector3(x1, 0.03, c.z)]]:
				RoomUtil.mesh(root, RoomUtil.box_mesh(e[0]), e[1], _m["accent"], false)
		# кромка-обломки
		for i in int((w + d) * 0.8):
			var e := Vector3(rng.randf_range(x0, x1), 0.02, z0 if rng.randf() < 0.5 else z1)
			if rng.randf() < 0.5:
				e = Vector3(x0 if rng.randf() < 0.5 else x1, 0.02, rng.randf_range(z0, z1))
			var sz := rng.randf_range(0.2, 0.45)
			var ch := RoomUtil.mesh(root, RoomUtil.box_mesh(Vector3(sz, sz * 0.6, sz)), e, _m["stone"], false)
			ch.rotation = Vector3(rng.randf() * 0.5, rng.randf() * TAU, rng.randf() * 0.5)
		# туман снизу: слои светящейся дымки
		for k in 3:
			var q := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(w - 0.4, d - 0.4)
			q.mesh = pm
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var fc: Color = (pal["fog"] as Color).lerp(pal["glow"], 0.25)
			fc.a = 0.38 + 0.12 * k
			m.albedo_color = fc
			m.disable_fog = true
			q.material_override = m
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			q.position = c + Vector3(0, -2.5 - k * 3.0, 0)
			root.add_child(q)
		var parts := CPUParticles3D.new()
		parts.amount = int(clampf(w * d * 0.8, 8, 40))
		parts.lifetime = 4.0
		parts.preprocess = 4.0
		parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		parts.emission_box_extents = Vector3(w * 0.45, 0.5, d * 0.45)
		parts.direction = Vector3(0, 1, 0)
		parts.spread = 20.0
		parts.gravity = Vector3(0, 0.25, 0)
		parts.initial_velocity_min = 0.2
		parts.initial_velocity_max = 0.6
		parts.scale_amount_min = 1.5
		parts.scale_amount_max = 3.0
		var qm := QuadMesh.new()
		qm.size = Vector2(1, 1)
		var fcol: Color = (pal["fog"] as Color).lerp(pal["glow"], 0.3)
		fcol.a = 0.35
		qm.material = RoomUtil.additive_mat(soft, fcol, true, true)
		parts.mesh = qm
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 0))
		grad.add_point(0.4, Color(1, 1, 1, 1))
		grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0))
		parts.color_ramp = grad
		parts.position = c + Vector3(0, -3.5, 0)
		root.add_child(parts)
		var light := OmniLight3D.new()
		light.light_color = pal["glow"]
		light.light_energy = 1.2
		light.omni_range = maxf(w, d) + 2.0
		light.position = c + Vector3(0, -2.0, 0)
		root.add_child(light)


# ================================================================ колонны
func _build_cols() -> void:
	var root := Node3D.new()
	root.name = "Columns"
	add_child(root)
	for c in layout.get("cols", []):
		var x := float(c[0])
		var z := float(c[1])
		var kind := String(c[2])
		# рандомизация по seed: часть целых колонн становится разрушаемой и наоборот
		if kind == "full" and rng.randf() < 0.3:
			kind = "destr"
		elif kind == "destr" and rng.randf() < 0.15:
			kind = "broken"
		var y := maxf(0.0, height_at(x, z))
		_obstacles.append([x, z, 0.9])
		if kind == "destr":
			var b := ArenaBreakable.make_column(pal, _m["stone"], _m["accent"], rng.randf_range(4.5, 6.5))
			root.add_child(b)
			b.position = Vector3(x, y, z)
			b.rotation.y = rng.randf() * TAU
		else:
			_static_column(root, Vector3(x, y, z), kind == "broken")


func _static_column(root: Node3D, pos: Vector3, broken: bool) -> void:
	var h := rng.randf_range(2.2, 3.8) if broken else rng.randf_range(6.5, 8.0)
	var r := 0.65
	var body := StaticBody3D.new()
	body.collision_layer = WALL_LAYER
	body.position = pos
	body.rotation.y = rng.randf() * TAU
	root.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	cs.position = Vector3(0, h * 0.5, 0)
	body.add_child(cs)
	RoomUtil.mesh(body, RoomUtil.box_mesh(Vector3(1.7, 0.5, 1.7)), Vector3(0, 0.25, 0), _m["stone"])
	RoomUtil.mesh(body, RoomUtil.cyl_mesh(r * 0.9, r, h, 10), Vector3(0, h * 0.5, 0), _m["stone"])
	if not broken:
		RoomUtil.mesh(body, RoomUtil.box_mesh(Vector3(1.6, 0.4, 1.6)), Vector3(0, h + 0.2, 0), _m["stone"])
		RoomUtil.mesh(body, RoomUtil.cyl_mesh(r * 0.92, r * 0.92, 0.12, 10), Vector3(0, h * 0.72, 0), _m["accent"], false)
	else:
		var top := RoomUtil.mesh(body, RoomUtil.cyl_mesh(r * 0.6, r * 0.88, 0.7, 7), Vector3(0.1, h + 0.2, 0), _m["stone"])
		top.rotation = Vector3(0.35, 0, 0.25)
		for i in 3:
			var ch := RoomUtil.mesh(body, RoomUtil.box_mesh(Vector3(0.5, 0.35, 0.4)), Vector3(rng.randf_range(-1.4, 1.4), 0.17, rng.randf_range(-1.4, 1.4)), _m["stone"])
			ch.rotation.y = rng.randf() * TAU
	if biome == 1:
		_wrap_root(body, h)


# ================================================================ мосты и перекладины
func _build_bridges() -> void:
	var root := Node3D.new()
	root.name = "Bridges"
	add_child(root)
	for b in layout.get("bridges", []):
		var a := Vector3(float(b[0]), float(b[4]), float(b[1]))
		var e := Vector3(float(b[2]), float(b[4]), float(b[3]))
		var w := float(b[5])
		var dir := (e - a)
		var length := dir.length()
		dir = dir.normalized()
		var yaw := atan2(-dir.z, dir.x)
		var node := Node3D.new()
		node.position = (a + e) * 0.5
		node.rotation.y = yaw
		root.add_child(node)
		# коллизия — тонкая полоса
		var body := StaticBody3D.new()
		body.collision_layer = WALL_LAYER
		body.add_to_group("bridge")
		node.add_child(body)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(length, 0.25, w)
		cs.shape = sh
		cs.position = Vector3(0, -0.125, 0)
		body.add_child(cs)
		# доски с лёгким провисанием (визуально) и разной шириной
		var n := int(length / 0.42)
		for i in n:
			var t := (i + 0.5) / n
			var x := -length * 0.5 + t * length
			var sag := -0.12 * sin(PI * t)
			var plank := RoomUtil.mesh(node, RoomUtil.box_mesh(Vector3(0.36, 0.08, w * rng.randf_range(0.9, 1.0))), Vector3(x, sag - 0.05, rng.randf_range(-0.05, 0.05)), _m["wood"])
			plank.rotation.y = rng.randf_range(-0.04, 0.04)
		# верёвки и столбы
		for side: float in [-1.0, 1.0]:
			var z: float = side * w * 0.5
			for end: float in [-1.0, 1.0]:
				RoomUtil.mesh(node, RoomUtil.cyl_mesh(0.07, 0.09, 1.4, 6), Vector3(end * length * 0.5, 0.6, z), _m["wood"])
			var segs := 8
			for k in segs:
				var t0 := float(k) / segs
				var t1 := float(k + 1) / segs
				var p0 := Vector3(-length * 0.5 + t0 * length, 1.15 - 0.35 * sin(PI * t0), z)
				var p1 := Vector3(-length * 0.5 + t1 * length, 1.15 - 0.35 * sin(PI * t1), z)
				var rope := RoomUtil.mesh(node, RoomUtil.cyl_mesh(0.025, 0.025, p0.distance_to(p1), 4), (p0 + p1) * 0.5, _m["rope"], false)
				rope.rotation.z = atan2(p1.y - p0.y, p1.x - p0.x) - PI * 0.5
		# если мост на земле над пропастью — тени и туман уже есть; если на высоте — опорные канаты вниз нет


func _build_bars() -> void:
	var root := Node3D.new()
	root.name = "Bars"
	add_child(root)
	for b in layout.get("bars", []):
		var a := Vector3(float(b[0]), 0, float(b[1]))
		var e := Vector3(float(b[2]), 0, float(b[3]))
		var h := float(b[4])
		var length := a.distance_to(e)
		var dir := (e - a).normalized()
		_obstacles.append([a.x, a.z, 0.4])
		_obstacles.append([e.x, e.z, 0.4])
		for p in [a, e]:
			RoomUtil.solid_box(root, p + Vector3(0, (h + 0.3) * 0.5, 0), Vector3(0.35, h + 0.3, 0.35), _m["wood"], WALL_LAYER)
		var body := StaticBody3D.new()
		body.collision_layer = WALL_LAYER
		body.add_to_group("bar")
		body.position = (a + e) * 0.5 + Vector3(0, h + 0.05, 0)
		body.rotation.y = atan2(-dir.z, dir.x)
		root.add_child(body)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(length, 0.3, 0.3)
		cs.shape = sh
		body.add_child(cs)
		var pole := RoomUtil.mesh(body, RoomUtil.cyl_mesh(0.12, 0.12, length, 8), Vector3.ZERO, _m["wood"])
		pole.rotation.z = PI * 0.5
		# цветные ленточки-жалау
		for i in 4:
			var rib := RoomUtil.mesh(body, RoomUtil.box_mesh(Vector3(0.08, 0.5, 0.02)), Vector3(-length * 0.4 + i * length * 0.27, -0.3, 0.13), RoomUtil.mat([pal["accent"], pal["felt"], Color(0.95, 0.85, 0.5)][i % 3], 1.0), false)
			rib.rotation.z = rng.randf_range(-0.2, 0.2)


# ================================================================ высокие стены и плиты для отскока
func _build_tall_walls() -> void:
	var root := Node3D.new()
	root.name = "TallWalls"
	add_child(root)
	for w in layout.get("walls", []):
		var x0 := float(w[0])
		var z0 := float(w[1])
		var x1 := float(w[2])
		var z1 := float(w[3])
		var h := float(w[4])
		var along_x := absf(x1 - x0) > absf(z1 - z0)
		var center: Vector3
		var size: Vector3
		var inward: Vector3
		if along_x:
			var zz := z0 - 0.5 if z0 < 0 else z0 + 0.5
			center = Vector3((x0 + x1) * 0.5, h * 0.5, zz)
			size = Vector3(absf(x1 - x0) + 1.0, h, 1.0)
			inward = Vector3(0, 0, 1) if z0 < 0 else Vector3(0, 0, -1)
		else:
			var xx := x0 - 0.5 if x0 < 0 else x0 + 0.5
			center = Vector3(xx, h * 0.5, (z0 + z1) * 0.5)
			size = Vector3(1.0, h, absf(z1 - z0) + 1.0)
			inward = Vector3(1, 0, 0) if x0 < 0 else Vector3(-1, 0, 0)
		var body := RoomUtil.solid_box(root, center, size, _m["stone"], WALL_LAYER)
		body.add_to_group("tall_wall")
		# зубцы сверху
		var length := maxf(size.x, size.z)
		var n := int(length / 1.5)
		for i in n:
			if i % 2 == 1:
				continue
			var off := -length * 0.5 + (i + 0.5) * length / n
			var cpos := Vector3(off, h * 0.5 + 0.3, 0) if along_x else Vector3(0, h * 0.5 + 0.3, off)
			RoomUtil.mesh(body, RoomUtil.box_mesh(Vector3(0.8, 0.6, 1.0) if along_x else Vector3(1.0, 0.6, 0.8)), cpos, _m["stone"])
		# резные плиты для отскока (видимые, группа wall_plate)
		var plates := maxi(1, int(length / 4.0))
		for i in plates:
			var t := (i + 0.5) / plates
			var off := -length * 0.5 + t * length
			var py := rng.randf_range(2.0, minf(h - 1.8, 4.5))
			var ppos := center + (Vector3(off, 0, 0) if along_x else Vector3(0, 0, off))
			ppos.y = py
			_wall_plate(root, ppos + inward * 0.58, inward, along_x)
		if biome == 1:
			_wrap_root(body, h)


func _wall_plate(root: Node3D, pos: Vector3, inward: Vector3, along_x: bool) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = WALL_LAYER
	body.position = pos
	body.add_to_group("wall_plate")
	root.add_child(body)
	var size := Vector3(1.8, 2.2, 0.16) if along_x else Vector3(0.16, 2.2, 1.8)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	RoomUtil.mesh(body, RoomUtil.box_mesh(size), Vector3.ZERO, _m["plat"])
	_plate_ornament(body, inward * 0.09, Vector2(1.5, 1.9), along_x)


## Орнамент «қошқар мүйіз» (светящиеся рёбра-рога) на плите.
func _plate_ornament(parent: Node3D, pos: Vector3, size: Vector2, along_x := true) -> void:
	var m: Material = _m["accent"]
	var frame := Node3D.new()
	frame.position = pos
	if not along_x:
		frame.rotation.y = PI * 0.5
	parent.add_child(frame)
	var t := 0.07
	RoomUtil.mesh(frame, RoomUtil.box_mesh(Vector3(size.x, t, t)), Vector3(0, size.y * 0.5, 0), m, false)
	RoomUtil.mesh(frame, RoomUtil.box_mesh(Vector3(size.x, t, t)), Vector3(0, -size.y * 0.5, 0), m, false)
	RoomUtil.mesh(frame, RoomUtil.box_mesh(Vector3(t, size.y, t)), Vector3(size.x * 0.5, 0, 0), m, false)
	RoomUtil.mesh(frame, RoomUtil.box_mesh(Vector3(t, size.y, t)), Vector3(-size.x * 0.5, 0, 0), m, false)
	# рога: две дуги из коротких сегментов
	for side: float in [-1.0, 1.0]:
		var prev := Vector3(0, -0.35, 0)
		for k in 7:
			var a := (k + 1) * 0.42
			var r := 0.18 + 0.05 * k
			var p := Vector3(side * (0.05 + absf(sin(a)) * r), cos(a) * r * 0.9 + 0.05 - 0.3, 0)
			var seg := RoomUtil.mesh(frame, RoomUtil.box_mesh(Vector3(maxf(prev.distance_to(p), 0.05), t, t)), (prev + p) * 0.5, m, false)
			seg.rotation.z = atan2(p.y - prev.y, p.x - prev.x)
			prev = p
	# ромб в центре
	var dia := RoomUtil.mesh(frame, RoomUtil.box_mesh(Vector3(0.22, 0.22, t)), Vector3(0, -0.55, 0), m, false)
	dia.rotation.z = PI * 0.25


# ================================================================ декор биомов
func _build_decor() -> void:
	var root := Node3D.new()
	root.name = "Decor"
	add_child(root)
	var tries := 0
	var placed := 0
	var want := 26 if biome == 0 else 18
	while placed < want and tries < 300:
		tries += 1
		var x := rng.randf_range(-_hx + 0.8, _hx - 0.8)
		var z := rng.randf_range(-_hz + 0.8, _hz - 0.8)
		var h := height_at(x, z)
		if h == -INF or is_pit(x, z, 0.6) or _near_obstacle(x, z, 0.6):
			continue
		placed += 1
		match biome:
			0:
				if rng.randf() < 0.65:
					_grass_tuft(root, Vector3(x, h, z))
				else:
					_rubble(root, Vector3(x, h, z))
			1:
				if rng.randf() < 0.5:
					_glow_moss(root, Vector3(x, h, z))
				else:
					_rubble(root, Vector3(x, h, z))
			_:
				if rng.randf() < 0.45:
					_crystal(root, Vector3(x, h, z))
				else:
					_rubble(root, Vector3(x, h, z))
	if biome == 1:
		# гигантские корни, перекинутые через арену высоко над головой и вдоль северной кромки
		for i in 3:
			var a := Vector3(-_hx - 2.0, rng.randf_range(7.0, 10.0), rng.randf_range(-_hz, -_hz * 0.2))
			var b := Vector3(rng.randf_range(-4.0, 6.0), -1.0, -_hz - 2.0)
			_root_arc(root, a, b, rng.randf_range(0.9, 1.4))
		for i in 2:
			var a2 := Vector3(rng.randf_range(-_hx, -_hx * 0.4), -1.0, -_hz - 1.5)
			var b2 := Vector3(-_hx - 1.5, -1.0, rng.randf_range(-_hz * 0.3, _hz * 0.6))
			_root_arc(root, a2, b2, rng.randf_range(0.7, 1.1), 5.0)
	if biome == 2:
		# обелиски Ерлика с фиолетовыми рунами у северной кромки
		for i in 4:
			var x := -_hx + 2.0 + i * (_hx * 2.0 - 4.0) / 3.0 + rng.randf_range(-1, 1)
			var p := Vector3(x, 0, -_hz - 2.4)
			var ob := RoomUtil.mesh(root, RoomUtil.box_mesh(Vector3(1.2, 7.0, 1.2)), p + Vector3(0, 2.5, 0), _m["dark"])
			ob.rotation.y = rng.randf() * 0.6
			RoomUtil.mesh(ob, RoomUtil.box_mesh(Vector3(0.2, 3.0, 1.25)), Vector3(0, 0.5, 0), RoomUtil.glow_mat(pal["glow"], 2.5), false)


func _grass_tuft(root: Node3D, p: Vector3) -> void:
	var tex := RoomUtil.tex("res://assets/bg/grass_%d.png" % rng.randi_range(0, 5))
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = 0.006 * rng.randf_range(0.7, 1.1)
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.centered = true
	s.offset = Vector2(0, tex.get_height() * 0.5 if tex else 0.0)
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.modulate = Color(1, 0.92, 0.8).lerp(pal["floor"], 0.25)
	s.position = p
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(s)


func _rubble(root: Node3D, p: Vector3) -> void:
	for i in rng.randi_range(1, 3):
		var sz := rng.randf_range(0.18, 0.5)
		var ch := RoomUtil.mesh(root, RoomUtil.box_mesh(Vector3(sz, sz * 0.55, sz * 0.8)), p + Vector3(rng.randf_range(-0.4, 0.4), sz * 0.25, rng.randf_range(-0.4, 0.4)), _m["stone"])
		ch.rotation = Vector3(rng.randf() * 0.3, rng.randf() * TAU, rng.randf() * 0.3)


func _glow_moss(root: Node3D, p: Vector3) -> void:
	for i in rng.randi_range(2, 4):
		var r := rng.randf_range(0.08, 0.2)
		RoomUtil.mesh(root, RoomUtil.cyl_mesh(r * 0.4, r, r * 1.6, 6), p + Vector3(rng.randf_range(-0.35, 0.35), r * 0.8, rng.randf_range(-0.35, 0.35)), RoomUtil.glow_mat(pal["glow"], 1.6), false)


func _crystal(root: Node3D, p: Vector3) -> void:
	for i in rng.randi_range(1, 3):
		var h := rng.randf_range(0.4, 1.2)
		var pm := PrismMesh.new()
		pm.size = Vector3(0.3, h, 0.3)
		var c := RoomUtil.mesh(root, pm, p + Vector3(rng.randf_range(-0.3, 0.3), h * 0.5, rng.randf_range(-0.3, 0.3)), RoomUtil.mat((pal["glow"] as Color).darkened(0.4), 0.3, pal["glow"], 1.5), false)
		c.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))


func _root_mat() -> Material:
	if not _m.has("root"):
		_m["root"] = _tri_mat(Color(0.36, 0.26, 0.19), Color(0.2, 0.14, 0.11), 0.4)
	return _m["root"]


## Толстый корень-дуга из сегментов цилиндров со светящимися жилами.
func _root_arc(root: Node3D, a: Vector3, b: Vector3, thick: float, lift := 3.0) -> void:
	var segs := 10
	var prev := a
	for k in segs:
		var t := float(k + 1) / segs
		var p := a.lerp(b, t) + Vector3(0, sin(PI * t) * lift, 0)
		var length := prev.distance_to(p)
		var r := thick * (1.0 - 0.4 * t)
		var seg := MeshInstance3D.new()
		seg.mesh = RoomUtil.cyl_mesh(r * 0.9, r, length + r * 0.6, 8)
		seg.material_override = _root_mat()
		root.add_child(seg)
		seg.position = (prev + p) * 0.5
		var up := (p - prev).normalized()
		seg.basis = _basis_up(up)
		if k % 3 == 1:
			var vein := MeshInstance3D.new()
			vein.mesh = RoomUtil.box_mesh(Vector3(0.08, length * 0.8, r * 2.05))
			vein.material_override = RoomUtil.glow_mat(pal["glow"], 2.0)
			vein.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			seg.add_child(vein)
		prev = p


func _basis_up(up: Vector3) -> Basis:
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z)


func _wrap_root(body: Node3D, h: float) -> void:
	# корень, обвивающий колонну/стену
	var seg := RoomUtil.mesh(body, RoomUtil.cyl_mesh(0.25, 0.32, h * 0.9, 6), Vector3(0.6, h * 0.45, 0.2), _root_mat())
	seg.rotation.z = 0.12
	RoomUtil.mesh(seg, RoomUtil.box_mesh(Vector3(0.06, h * 0.6, 0.66)), Vector3.ZERO, RoomUtil.glow_mat(pal["glow"], 1.8), false)


func _hanging_root(root: Node3D, p: Vector3) -> void:
	var length := rng.randf_range(3.0, 8.0)
	var seg := RoomUtil.mesh(root, RoomUtil.cyl_mesh(0.3, 0.08, length, 6), p + Vector3(0, -length * 0.5, 0), _root_mat(), false)
	seg.rotation.z = rng.randf_range(-0.15, 0.15)


# ================================================================ факелы и костры
func _build_torches() -> void:
	var root := Node3D.new()
	root.name = "Torches"
	add_child(root)
	var spots := []
	if _round:
		for i in 6:
			var a := PI + i * PI / 5.0 + rng.randf_range(-0.1, 0.1)
			spots.append(Vector3(cos(a) * (_radius - 1.0), 0, sin(a) * (_radius - 1.0)))
	else:
		var n := 3 if _hx < 12 else 4
		for i in n:
			spots.append(Vector3(-_hx + 1.0 + (i + 0.5) * (2.0 * _hx - 2.0) / n + rng.randf_range(-1.0, 1.0), 0, -_hz + 0.9))
		for i in 2:
			spots.append(Vector3(-_hx + 0.9, 0, -_hz * 0.3 + i * _hz * 0.9 + rng.randf_range(-1.0, 1.0)))
		spots.append(Vector3(_hx - 1.0, 0, _hz - 1.0))
	var doors := []
	for d in layout.get("doors", []):
		doors.append(Vector2(float(d[0]), float(d[2])))
	for s in spots:
		var p: Vector3 = s
		var blocked := false
		for d in doors:
			if Vector2(p.x, p.z).distance_to(d) < 2.6:
				blocked = true
		if blocked:
			p.x += 2.8 if p.x < 10 else -2.8
		var h := height_at(p.x, p.z)
		if h == -INF:
			continue
		p.y = h
		_torch(root, p)
	# костёр-очаг (кроме босса — там свой свет)
	if not _round and String(layout_id) != "caravan":
		for t in 8:
			var x := rng.randf_range(-_hx + 3, _hx - 3)
			var z := rng.randf_range(-_hz + 3, _hz - 3)
			if height_at(x, z) == 0.0 and _flat(x, z, 1.2) and not _near_obstacle(x, z, 2.0) and not is_pit(x, z, 1.5):
				_campfire(root, Vector3(x, 0, z))
				break


func _torch(root: Node3D, p: Vector3) -> void:
	var t := Node3D.new()
	t.position = p
	root.add_child(t)
	_obstacles.append([p.x, p.z, 0.3])
	RoomUtil.mesh(t, RoomUtil.cyl_mesh(0.08, 0.12, 2.0, 6), Vector3(0, 1.0, 0), _m["wood"])
	RoomUtil.mesh(t, RoomUtil.cyl_mesh(0.28, 0.14, 0.25, 8), Vector3(0, 2.1, 0), _m["dark"])
	var fire := RoomUtil.flame_sprite(pal["fire"], 0.007)
	fire.position = Vector3(0, 2.45, 0)
	t.add_child(fire)
	var core := RoomUtil.flame_sprite(Color(1, 0.95, 0.8), 0.0035)
	core.position = Vector3(0, 2.35, 0)
	t.add_child(core)
	var l := OmniLight3D.new()
	l.light_color = pal["fire"]
	l.light_energy = 1.6
	l.omni_range = 7.0
	l.omni_attenuation = 1.2
	l.position = Vector3(0, 2.6, 0)
	t.add_child(l)
	_flicker.append([l, fire, rng.randf() * 10.0])


func _campfire(root: Node3D, p: Vector3) -> void:
	var t := Node3D.new()
	t.position = p
	root.add_child(t)
	_obstacles.append([p.x, p.z, 1.0])
	for i in 7:
		var a := TAU * i / 7.0
		var st := RoomUtil.mesh(t, RoomUtil.box_mesh(Vector3(0.35, 0.25, 0.3)), Vector3(cos(a) * 0.65, 0.12, sin(a) * 0.65), _m["stone"])
		st.rotation.y = -a
	for i in 3:
		var log := RoomUtil.mesh(t, RoomUtil.cyl_mesh(0.08, 0.08, 1.0, 6), Vector3(0, 0.15, 0), _m["wood"])
		log.rotation = Vector3(PI * 0.5, i * PI / 3.0, 0)
	var fire := RoomUtil.flame_sprite(pal["fire"], 0.012)
	fire.position = Vector3(0, 0.6, 0)
	t.add_child(fire)
	var l := OmniLight3D.new()
	l.light_color = pal["fire"]
	l.light_energy = 2.2
	l.omni_range = 9.0
	l.shadow_enabled = false
	l.position = Vector3(0, 1.0, 0)
	t.add_child(l)
	_flicker.append([l, fire, rng.randf() * 10.0])
	var sparks := CPUParticles3D.new()
	sparks.amount = 14
	sparks.lifetime = 1.4
	sparks.direction = Vector3.UP
	sparks.spread = 15.0
	sparks.gravity = Vector3(0, 1.2, 0)
	sparks.initial_velocity_min = 0.6
	sparks.initial_velocity_max = 1.4
	sparks.scale_amount_min = 0.05
	sparks.scale_amount_max = 0.12
	var qm := QuadMesh.new()
	qm.material = RoomUtil.additive_mat(RoomUtil.tex("res://assets/fx/soft.png"), pal["fire"], true, true)
	sparks.mesh = qm
	sparks.position = Vector3(0, 0.5, 0)
	t.add_child(sparks)


# ================================================================ кувшины
func _build_jars() -> void:
	var root := Node3D.new()
	root.name = "Jars"
	add_child(root)
	if String(layout_id) == "caravan":
		return
	var want := rng.randi_range(4, 8)
	var tries := 0
	while want > 0 and tries < 200:
		tries += 1
		var x := rng.randf_range(-_hx + 1.0, _hx - 1.0)
		var z := rng.randf_range(-_hz + 1.0, _hz - 1.0)
		# у стен и на ярусах — чаще
		if rng.randf() < 0.5:
			if rng.randf() < 0.5:
				z = -_hz + rng.randf_range(0.8, 1.6)
			else:
				x = -_hx + rng.randf_range(0.8, 1.6)
		if not in_bounds(x, z, 1.0) or is_pit(x, z, 1.0) or _near_obstacle(x, z, 1.0) or not _flat(x, z, 0.5):
			continue
		var h := height_at(x, z)
		var cluster := rng.randi_range(1, 3)
		for k in cluster:
			var off := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)) if k > 0 else Vector3.ZERO
			if height_at(x + off.x, z + off.z) != h:
				continue
			var j := ArenaBreakable.make_jar(pal, rng)
			root.add_child(j)
			j.position = Vector3(x, h, z) + off
			_obstacles.append([x + off.x, z + off.z, 0.4])
		want -= 1


# ================================================================ 2D-задники (параллакс)
func _build_backdrop() -> void:
	var root := Node3D.new()
	root.name = "Backdrop"
	add_child(root)
	# небо, степь и хребты Алатау — 2D-слой фона окружения (BG_CANVAS) с параллаксом: виден при любом наклоне камеры
	backdrop_2d = ArenaBackdrop.make(biome, pal["fog"])
	add_child(backdrop_2d)
	# дальние руины / курганы на равнине внизу (BILLBOARD_FIXED_Y), два слоя
	var far_names := []
	for i in 4:
		far_names.append(String(pal["ruins"]) % i)
	var near_names := ["kurgan_0", "kurgan_1", "kurgan_2", "stone_0", "stone_1", "stone_2", "stone_3", "kurgan_3", "kurgan_4", "kurgan_5"]
	# дальний пояс руин — редкий и ниже, чтобы не заслонять 2D-хребты за ним
	_backdrop_band(root, far_names, 50.0, -26.0, 0.08, 4, 0.55, 0.65)
	_backdrop_band(root, near_names, 32.0, -18.0, 0.045, 8, 0.3, 0.35)
	_backdrop_band(root, near_names, 21.0, -9.0, 0.04, 8, 0.12, 0.15)


func _backdrop_band(root: Node3D, names: Array, dist: float, y: float, px: float, count: int, factor: float, fog_mix: float) -> void:
	# дуга за северной и западной сторонами (в зоне видимости камеры)
	for i in count:
		var t := (i + rng.randf_range(0.1, 0.9)) / count
		var ang := lerpf(deg_to_rad(-200.0), deg_to_rad(-60.0), t)  # от юго-запада через северо-запад к северо-востоку
		var p := Vector3(cos(ang) * dist, y, sin(ang) * dist)
		# держим слой за пределами арены
		if p.x > -_hx - 4.0 and p.z > -_hz - 4.0:
			continue
		var tex := RoomUtil.tex("res://assets/bg/%s.png" % String(names[rng.randi_range(0, names.size() - 1)]))
		if tex == null:
			continue
		var s := Sprite3D.new()
		s.texture = tex
		s.pixel_size = px * rng.randf_range(0.8, 1.25)
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		s.offset = Vector2(0, tex.get_height() * 0.5)
		s.shaded = false
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.modulate = Color(1, 1, 1).lerp(pal["fog"], fog_mix)
		s.position = p
		root.add_child(s)
		_parallax.append({"node": s, "base": p, "factor": factor})


# ================================================================ частицы в воздухе
func _build_particles() -> void:
	var p := CPUParticles3D.new()
	p.name = "AirDust"
	p.amount = 70
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(_hx + 2.0, 4.0, _hz + 2.0)
	p.position = Vector3(0, 4.0, 0)
	p.direction = Vector3(1, 0.15, 0.4) if biome == 0 else Vector3(0, 1, 0)
	p.spread = 35.0
	p.gravity = Vector3(0.3, -0.05, 0.1) if biome == 0 else Vector3(0, 0.12, 0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.12
	var qm := QuadMesh.new()
	qm.material = RoomUtil.additive_mat(RoomUtil.tex("res://assets/fx/soft.png"), pal["particles"], true, true)
	p.mesh = qm
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0))
	grad.add_point(0.3, Color(1, 1, 1, 1))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = grad
	add_child(p)


# ================================================================ точки
func _compute_points() -> void:
	var sp: Array = layout.get("spawn", [0, 0, 8])
	spawn_player = Vector3(float(sp[0]), float(sp[1]) + 0.1, float(sp[2]))
	var rp: Array = layout.get("reward", [0, 0, 0])
	reward_point = Vector3(float(rp[0]), float(rp[1]), float(rp[2]))
	door_slots.clear()
	for d in layout.get("doors", []):
		door_slots.append(Vector3(float(d[0]), float(d[1]), float(d[2])))
	for k in ["merchant", "well", "boss"]:
		if layout.has(k):
			var a: Array = layout[k]
			extra_points[k] = Vector3(float(a[0]), float(a[1]), float(a[2]))
	if layout.has("goods"):
		var g := []
		for a in layout["goods"]:
			g.append(Vector3(float(a[0]), float(a[1]), float(a[2])))
		extra_points["goods"] = g
	if _round:
		bounds = AABB(Vector3(-_radius, -1, -_radius), Vector3(_radius * 2, 9, _radius * 2))
	else:
		bounds = AABB(Vector3(-_hx, -1, -_hz), Vector3(_hx * 2, 9, _hz * 2))
	# точки спавна врагов: ярусы + пол
	spawn_points.clear()
	var srng := RandomNumberGenerator.new()
	srng.seed = arena_seed + 7
	for b in layout.get("plats", []):
		var h := float(b[4])
		if h < 1.0:
			continue
		var x0 := float(b[0]) + 0.9
		var z0 := float(b[1]) + 0.9
		var x1 := float(b[2]) - 0.9
		var z1 := float(b[3]) - 0.9
		if x1 <= x0 or z1 <= z0:
			continue
		for k in 6:
			var x := srng.randf_range(x0, x1)
			var z := srng.randf_range(z0, z1)
			if _valid_spawn(x, z) and is_equal_approx(height_at(x, z), h):
				spawn_points.append(Vector3(x, h, z))
				break
	var tries := 0
	var ground := 0
	while ground < 12 and tries < 400:
		tries += 1
		var x := srng.randf_range(-_hx + 1.5, _hx - 1.5)
		var z := srng.randf_range(-_hz + 1.5, _hz - 1.5)
		if not _valid_spawn(x, z):
			continue
		var p := Vector3(x, height_at(x, z), z)
		if Vector2(p.x - spawn_player.x, p.z - spawn_player.z).length() < 5.0:
			continue
		var close := false
		for q in spawn_points:
			if q.distance_to(p) < 2.5:
				close = true
		if close:
			continue
		spawn_points.append(p)
		ground += 1


func _valid_spawn(x: float, z: float) -> bool:
	if not in_bounds(x, z, 1.2):
		return false
	if is_pit(x, z, 1.3) or _near_obstacle(x, z, 0.9):
		return false
	if not _flat(x, z, 0.7):
		return false
	for d in door_slots:
		if Vector2(x - d.x, z - d.z).length() < 2.5:
			return false
	return true


## Тайный ход: треснувшая плита у северной (иначе западной) кромки на ровном полу, вдали от дверей, стен и ярусов.
## Возвращает ArenaBreakable (kind "secret_wall") с meta "door_pos"/"door_rot" — где поставить дверь после разрушения;
## null — подходящего места нет.
func add_secret_wall(r: RandomNumberGenerator) -> ArenaBreakable:
	if _round:
		return null
	var spots: Array = []
	var x := -_hx + 2.0
	while x <= _hx - 2.0:
		spots.append([Vector3(x, 0, -_hz + 0.45), Vector3(x, 0, -_hz + 0.8), 0.0, Vector2(1, 0)])
		x += 0.5
	var z := -_hz + 2.5
	while z <= _hz - 2.5:
		spots.append([Vector3(-_hx + 0.45, 0, z), Vector3(-_hx + 0.8, 0, z), PI * 0.5, Vector2(0, 1)])
		z += 0.5
	# перемешать детерминированно
	for k in range(spots.size() - 1, 0, -1):
		var j := r.randi_range(0, k)
		var tmp = spots[k]
		spots[k] = spots[j]
		spots[j] = tmp
	for sp in spots:
		var wall_pos: Vector3 = sp[0]
		var door_pos: Vector3 = sp[1]
		var along: Vector2 = sp[3]
		if not _secret_spot_ok(door_pos, along):
			continue
		var b := ArenaBreakable.make_secret_wall(_m["stone"], _m["accent"])
		add_child(b)
		b.position = wall_pos
		b.rotation.y = float(sp[2])
		b.set_meta("door_pos", door_pos)
		b.set_meta("door_rot", float(sp[2]))
		_obstacles.append([wall_pos.x, wall_pos.z, 1.3])
		return b
	return null


func _secret_spot_ok(p: Vector3, along: Vector2) -> bool:
	# ровный пол шириной арки (±2.2 вдоль кромки) и 2 м перед ней
	for t in [-2.2, -1.1, 0.0, 1.1, 2.2]:
		for depth in [0.0, 1.0, 2.0]:
			var inward := Vector2(along.y, along.x)   # север → +Z, запад → +X
			var q: Vector2 = Vector2(p.x, p.z) + along * float(t) + inward * float(depth)
			if height_at(q.x, q.y) != 0.0 or is_pit(q.x, q.y, 0.8):
				return false
	# высокие стены стоят за кромкой — плита у их подножия выглядит естественно; мешают только колонны/факелы в проёме
	if _near_obstacle(p.x, p.z, 1.2):
		return false
	for d in door_slots:
		if Vector2(p.x - d.x, p.z - d.z).length() < 4.8:
			return false
	return true


## Точки спавна на ярусах не ниже min_h.
func tier_points(min_h: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in spawn_points:
		if p.y >= min_h - 0.01:
			out.append(p)
	return out


## Случайная ровная точка пола/яруса (для печати, наград и т.п.).
func random_floor_point(r: RandomNumberGenerator, avoid := Vector3.INF, min_dist := 0.0) -> Vector3:
	for i in 60:
		var x := r.randf_range(-_hx + 1.5, _hx - 1.5)
		var z := r.randf_range(-_hz + 1.5, _hz - 1.5)
		if not _valid_spawn(x, z):
			continue
		var p := Vector3(x, height_at(x, z), z)
		if avoid != Vector3.INF and Vector2(p.x - avoid.x, p.z - avoid.z).length() < min_dist:
			continue
		return p
	return spawn_points[r.randi_range(0, spawn_points.size() - 1)] if not spawn_points.is_empty() else Vector3.ZERO


# ================================================================ анимация
var _flicker: Array = []
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	for f in _flicker:
		var l: OmniLight3D = f[0]
		var s: Sprite3D = f[1]
		var ph: float = f[2]
		if is_instance_valid(l):
			l.light_energy = 1.6 + 0.35 * sin(_t * 9.0 + ph) + 0.2 * sin(_t * 23.0 + ph * 2.0)
		if is_instance_valid(s):
			var k := 1.0 + 0.12 * sin(_t * 11.0 + ph)
			s.scale = Vector3(k, k * 1.15, 1.0)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	if _cam_origin == null:
		_cam_origin = cam.global_position
	var off: Vector3 = cam.global_position - (_cam_origin as Vector3)
	if backdrop_2d and not cam.is_position_behind(global_position):
		var sp := cam.unproject_position(global_position)
		if _anchor_screen == null:
			_anchor_screen = sp
		backdrop_2d.set_shift(sp - (_anchor_screen as Vector2))
	for e in _parallax:
		var n: Node3D = e["node"]
		if is_instance_valid(n):
			var b: Vector3 = e["base"]
			var f2: float = e["factor"]
			n.position = b + Vector3(off.x * f2, off.y * f2 * 0.5, off.z * f2)
