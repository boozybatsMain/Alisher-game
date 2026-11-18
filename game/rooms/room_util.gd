class_name RoomUtil
extends RefCounted
## Помощники модуля комнат (D): меши/материалы, цвета и имена духов, безопасный доступ к чужим модулям
## (BoonData, EnemyData, UiKit, BoonChoice) через ResourceLoader, чтобы комнаты не падали, если модуль меняется.

const BOON_DATA := "res://game/boons/boon_data.gd"
const BOON_CHOICE := "res://game/boons/boon_choice.gd"
const SPIRIT_TOTEM := "res://game/boons/spirit_totem.tscn"
const ENEMY_DATA := "res://game/enemies/enemy_data.gd"
const ENEMY_FACTORY := "res://game/enemies/enemy_factory.gd"
const UI_KIT := "res://game/ui/ui_kit.gd"
const GAME_CAMERA := "res://game/player/game_camera.gd"

const GODS := ["tengri", "ai_mergen", "umai", "zher_su", "erlik", "kokbori"]
const GOD_COLORS := {
	"tengri": Color("#8cc8ff"), "ai_mergen": Color("#c9b3ff"), "umai": Color("#ff8a3d"),
	"zher_su": Color("#5fd3c4"), "erlik": Color("#9b4dff"), "kokbori": Color("#e04848"),
}
const GOD_NAMES := {
	"tengri": "Тенгри", "ai_mergen": "Ай-Мерген", "umai": "Умай",
	"zher_su": "Жер-Су", "erlik": "Ерлик", "kokbori": "Көкбөрі",
}
const GOLD := Color(1.0, 0.78, 0.3)
const ASH := Color(0.85, 0.82, 0.9)
const BIOME_NAMES := ["Осквернённая степь", "Корни Байтерека", "Чертог Ерлика"]

static var _scripts := {}
static var _mats := {}


static func script_of(path: String) -> Variant:
	if _scripts.has(path):
		return _scripts[path]
	var s: Variant = null
	if ResourceLoader.exists(path):
		s = load(path)
	_scripts[path] = s
	return s


# ---------------------------------------------------------------- духи / дары
static func god_color(god: String) -> Color:
	return GOD_COLORS.get(god, Color(1, 0.9, 0.7))


static func god_name(god: String) -> String:
	var bd: Variant = script_of(BOON_DATA)
	if bd and bd.has_method("god_name"):
		var n := String(bd.god_name(god))
		if n != "" and n != god:
			return n
	return String(GOD_NAMES.get(god, god))


static func boon_title(id: String) -> String:
	var bd: Variant = script_of(BOON_DATA)
	if bd and bd.has_method("title_of"):
		return String(bd.title_of(id))
	return id


static func boon_desc(id: String, level := 1, rarity := "common") -> String:
	var bd: Variant = script_of(BOON_DATA)
	if bd and bd.has_method("describe"):
		return String(bd.describe(id, level, rarity))
	return ""


static func boon_god(id: String) -> String:
	var bd: Variant = script_of(BOON_DATA)
	if bd and bd.has_method("god_of"):
		return String(bd.god_of(id))
	return ""


static func boon_icon(id: String, rarity := "common") -> Texture2D:
	var bd: Variant = script_of(BOON_DATA)
	if bd and bd.has_method("icon"):
		return bd.icon(id, rarity) as Texture2D
	return null


static func god_icon(god: String) -> Texture2D:
	var bd: Variant = script_of(BOON_DATA)
	if bd and bd.has_method("god_icon"):
		return bd.god_icon(god) as Texture2D
	return null


## Список даров героя [{id, level, rarity}] (пусто, если BoonManager нет).
static func owned_boons() -> Array:
	if Run.boons and Run.boons.has_method("owned"):
		return Run.boons.owned()
	return []


## Прямо выдать случайный дар духа (без окна) — fallback, если окна выбора нет.
static func grant_random_boon(god: String) -> String:
	if Run.boons == null:
		return ""
	if Run.boons.has_method("roll_choices"):
		var ch: Array = Run.boons.roll_choices(god, 1)
		if not ch.is_empty():
			var c: Dictionary = ch[0]
			if Run.boons.has_method("take_choice"):
				Run.boons.take_choice(c)
			elif Run.boons.has_method("add_boon"):
				Run.boons.add_boon(String(c.get("id", "")))
			return String(c.get("id", ""))
	return ""


## Открыть окно выбора дара (BoonChoice) или выдать дар напрямую. on_done(choice: Dictionary).
static func open_boon_choice(host: Node, god: String, on_done: Callable, count := 3) -> void:
	var bc: Variant = script_of(BOON_CHOICE)
	if bc and bc.has_method("open"):
		var choices := []
		if Run.boons and Run.boons.has_method("roll_choices"):
			choices = Run.boons.roll_choices(god, count)
		var w: Variant = bc.open(host, god, on_done, choices)
		if w != null:
			return
	var id := grant_random_boon(god)
	if id != "":
		Bus.toast.emit("Дар: " + boon_title(id), god_color(god))
	on_done.call({"id": id} if id != "" else {})


# ---------------------------------------------------------------- враги
static func enemy_pool(biome: int) -> Array:
	var ed: Variant = script_of(ENEMY_DATA)
	if ed and ed.has_method("pool"):
		var p: Array = ed.pool(biome)
		if not p.is_empty():
			return p
	return [{"id": "wolf", "weight": 3}, {"id": "spirit", "weight": 2}, {"id": "balbal", "weight": 1}, {"id": "archer", "weight": 2}]


static func pick_enemy(biome: int, rng: RandomNumberGenerator, exclude: Array = []) -> String:
	var p := enemy_pool(biome)
	var total := 0.0
	for e in p:
		if String(e.get("id", "")) in exclude:
			continue
		total += float(e.get("weight", 1.0))
	if total <= 0.0:
		return String(p[0].get("id", "wolf"))
	var r := rng.randf() * total
	for e in p:
		if String(e.get("id", "")) in exclude:
			continue
		r -= float(e.get("weight", 1.0))
		if r <= 0.0:
			return String(e.get("id", "wolf"))
	return String(p[0].get("id", "wolf"))


static func boss_for(biome: int) -> String:
	var ed: Variant = script_of(ENEMY_DATA)
	if ed == null:
		return ""
	if ed.has_method("boss_for"):
		return String(ed.boss_for(biome))
	var cm: Dictionary = (ed as GDScript).get_script_constant_map()
	if cm.has("BOSSES") and cm["BOSSES"] is Array and not (cm["BOSSES"] as Array).is_empty():
		var b: Array = cm["BOSSES"]
		return String(b[clampi(biome, 0, b.size() - 1)])
	return ""


static func enemy_name(id: String) -> String:
	var ed: Variant = script_of(ENEMY_DATA)
	if ed and ed.has_method("display_name"):
		return String(ed.display_name(id))
	return id


static func spawn_enemy(type_id: String, parent: Node, pos: Vector3, mods := {}) -> Node3D:
	var ef: Variant = script_of(ENEMY_FACTORY)
	if ef and ef.has_method("spawn"):
		return ef.spawn(type_id, parent, pos, mods) as Node3D
	return null


static func is_alive(e: Variant) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	var n := e as Node
	if n == null or not n.is_inside_tree() or n.is_queued_for_deletion():
		return false
	if n.has_method("is_dead") and n.is_dead():
		return false
	return true


# ---------------------------------------------------------------- геометрия
static func mat(color: Color, rough := 0.9, emission := Color.BLACK, energy := 0.0, metal := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%s|%.2f|%.2f" % [color.to_html(), rough, emission.to_html(), energy, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	if color.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


static func glow_mat(color: Color, energy := 2.5) -> StandardMaterial3D:
	var key := "glow|%s|%.2f" % [color.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	if color.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


static func additive_mat(tex: Texture2D, color: Color, billboard := true, particles := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.albedo_color = color
	m.disable_fog = true
	if particles:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.vertex_color_use_as_albedo = true
	elif billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func cyl_mesh(top: float, bottom: float, h: float, segs := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func mesh(parent: Node, m: Mesh, pos: Vector3, material: Material, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Статический блок (MeshInstance + коллизия Box) — слой мира 1.
static func solid_box(parent: Node, center: Vector3, size: Vector3, material: Material, layer := 1, visible := true) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	sb.position = center
	parent.add_child(sb)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	if visible:
		mesh(sb, box_mesh(size), Vector3.ZERO, material)
	return sb


static func tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


static func label3d(text: String, color: Color, size := 48, px := 0.006) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = color
	l.outline_modulate = Color(0.05, 0.03, 0.02)
	l.outline_size = 10
	l.font_size = size
	l.pixel_size = px
	l.no_depth_test = true
	l.fixed_size = false
	var uk: Variant = script_of(UI_KIT)
	if uk and uk.has_method("bold"):
		var f: Variant = uk.bold()
		if f is Font:
			l.font = f
	return l


static func flame_sprite(color: Color, px := 0.008) -> Sprite3D:
	var s := Sprite3D.new()
	var t := tex("res://assets/fx/soft.png")
	s.texture = t
	s.pixel_size = px
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.material_override = additive_mat(t, color)
	return s


static func toast(text: String, color := Color(1, 0.93, 0.75)) -> void:
	Bus.toast.emit(text, color)


static func player(tree: SceneTree) -> Node3D:
	return tree.get_first_node_in_group("player") as Node3D if tree else null
