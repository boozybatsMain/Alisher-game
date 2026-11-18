class_name RoomRewards
extends RefCounted
## Описания наград и типов комнат (для дверей, HUD, тостов) и процедурные 3D-иконки наград (модуль D).
##
##   RoomRewards.info(room) -> {title, sub, color, icon}  — что написать/показать над дверью
##   RoomRewards.make_icon(icon, color, god := "", god2 := "") -> Node3D  — мини-модель символа (≈0.8 м), сама вращается
##   RoomRewards.ash_amount(depth), gold_amount(depth, rng), price(kind, depth)

const TITLES := {
	"boon": "Дар духа", "ash": "Пепел Тамыра", "gold": "Золотые дирхемы", "merchant": "Лавка Караванщика",
	"upgrade": "Камень Силы", "heal": "Яство", "kui": "Забытая нота",
}
const COLORS := {
	"ash": Color(0.82, 0.84, 0.98), "gold": Color(1.0, 0.8, 0.3), "merchant": Color(1.0, 0.68, 0.32),
	"upgrade": Color(0.45, 0.78, 1.0), "heal": Color(1.0, 0.45, 0.4), "kui": Color(0.5, 1.0, 0.85),
	"boss": Color(1.0, 0.22, 0.18), "rest": Color(0.5, 0.9, 1.0),
}
const PRICES := {"boon": 80, "food": 40, "upgrade": 120}


static func info(room: Dictionary) -> Dictionary:
	var t := String(room.get("type", "combat"))
	var r := String(room.get("reward", "boon"))
	var god := String(room.get("god", ""))
	var out := {"title": String(TITLES.get(r, r)), "sub": "", "color": COLORS.get(r, Color(1, 0.9, 0.7)), "icon": r}
	match t:
		"boss":
			var bid := RoomUtil.boss_for(int(room.get("biome", 0)))
			out = {"title": "Владыка", "sub": RoomUtil.enemy_name(bid) if bid != "" else "Страж биома", "color": COLORS["boss"], "icon": "boss"}
		"merchant":
			out = {"title": "Лавка Караванщика", "sub": "товары за дирхемы", "color": COLORS["merchant"], "icon": "merchant"}
		"duel":
			var g2 := String(room.get("god2", ""))
			out = {"title": "Спор Духов", "sub": "%s и %s" % [RoomUtil.god_name(god), RoomUtil.god_name(g2)],
				"color": RoomUtil.god_color(god).lerp(RoomUtil.god_color(g2), 0.5), "icon": "duel"}
		"rest":
			out = {"title": "Привал", "sub": "целебный родник", "color": COLORS["rest"], "icon": "rest"}
		"secret":
			out = {"title": "Тайник предков", "sub": "Забытая нота" if r == "kui" else "испытание ловкости",
				"color": COLORS["kui"], "icon": "kui"}
		_:
			if r == "boon":
				out["title"] = "Дар: " + RoomUtil.god_name(god)
				out["color"] = RoomUtil.god_color(god)
				out["icon"] = "boon"
			if t == "elite":
				out["sub"] = "Элита Мглы · награда щедрее"
	return out


static func ash_amount(depth: int) -> int:
	return clampi(10 + depth * 1, 10, 30)


static func gold_amount(depth: int, rng: RandomNumberGenerator) -> int:
	return clampi(rng.randi_range(40, 60) + depth * 2, 40, 80)


static func price(kind: String, depth: int) -> int:
	return int(round(float(PRICES.get(kind, 50)) * (1.0 + 0.06 * depth) / 5.0) * 5.0)


# ================================================================ иконки
static func make_icon(icon: String, color: Color, god := "", god2 := "") -> Node3D:
	var root := _Spin.new()
	root.name = "Icon_" + icon
	match icon:
		"boon":
			_god_emblem(root, god, color, Vector3.ZERO)
		"duel":
			_god_emblem(root, god, RoomUtil.god_color(god), Vector3(-0.38, 0, 0), 0.75)
			_god_emblem(root, god2, RoomUtil.god_color(god2), Vector3(0.38, 0, 0), 0.75)
		"ash":
			var pile := RoomUtil.mesh(root, RoomUtil.cyl_mesh(0.02, 0.42, 0.4, 10), Vector3(0, -0.15, 0), RoomUtil.mat(Color(0.55, 0.55, 0.6), 1.0), false)
			pile.scale = Vector3(1, 1, 0.9)
			RoomUtil.mesh(root, _sphere(0.1), Vector3(0.05, 0.08, 0.05), RoomUtil.glow_mat(Color(1.0, 0.5, 0.2), 3.0), false)
			RoomUtil.mesh(root, _sphere(0.06), Vector3(-0.15, -0.05, 0.12), RoomUtil.glow_mat(Color(0.75, 0.8, 1.0), 2.5), false)
		"gold":
			var gm := RoomUtil.mat(Color(1.0, 0.78, 0.25), 0.3, Color(1.0, 0.7, 0.2), 0.6, 0.8)
			for i in 4:
				RoomUtil.mesh(root, RoomUtil.cyl_mesh(0.22, 0.22, 0.07, 14), Vector3(0.02 * i, -0.25 + i * 0.08, 0), gm, false)
			var c := RoomUtil.mesh(root, RoomUtil.cyl_mesh(0.22, 0.22, 0.07, 14), Vector3(0.25, 0.05, 0.1), gm, false)
			c.rotation = Vector3(PI * 0.5, 0, 0.3)
		"merchant":
			var sack := RoomUtil.mesh(root, _sphere(0.33), Vector3(0, -0.08, 0), RoomUtil.mat(Color(0.55, 0.36, 0.2), 1.0), false)
			sack.scale = Vector3(1, 0.9, 0.9)
			RoomUtil.mesh(root, RoomUtil.cyl_mesh(0.08, 0.14, 0.18, 8), Vector3(0, 0.28, 0), RoomUtil.mat(Color(0.5, 0.33, 0.18), 1.0), false)
			RoomUtil.mesh(root, RoomUtil.cyl_mesh(0.15, 0.15, 0.05, 10), Vector3(0, 0.2, 0), RoomUtil.mat(Color(0.8, 0.2, 0.15), 1.0), false)
			var coin := RoomUtil.mesh(root, RoomUtil.cyl_mesh(0.13, 0.13, 0.04, 12), Vector3(0, -0.05, 0.3), RoomUtil.mat(Color(1, 0.8, 0.3), 0.3, Color(1, 0.7, 0.2), 0.8, 0.8), false)
			coin.rotation.x = PI * 0.5
		"upgrade":
			var pm := PrismMesh.new()
			pm.size = Vector3(0.36, 0.55, 0.36)
			RoomUtil.mesh(root, pm, Vector3(0, 0.12, 0), RoomUtil.mat(color.darkened(0.2), 0.2, color, 2.0), false)
			var pm2 := PrismMesh.new()
			pm2.size = Vector3(0.36, 0.35, 0.36)
			var low := RoomUtil.mesh(root, pm2, Vector3(0, -0.33, 0), RoomUtil.mat(color.darkened(0.2), 0.2, color, 2.0), false)
			low.rotation.z = PI
		"heal":
			RoomUtil.mesh(root, RoomUtil.cyl_mesh(0.34, 0.22, 0.14, 12), Vector3(0, -0.25, 0), RoomUtil.mat(Color(0.5, 0.32, 0.2), 0.9), false)
			RoomUtil.mesh(root, _sphere(0.17), Vector3(-0.1, -0.06, 0), RoomUtil.mat(Color(0.85, 0.18, 0.15), 0.5), false)
			RoomUtil.mesh(root, _sphere(0.14), Vector3(0.14, -0.08, 0.06), RoomUtil.mat(Color(0.95, 0.85, 0.6), 0.7), false)
			RoomUtil.mesh(root, RoomUtil.box_mesh(Vector3(0.04, 0.14, 0.04)), Vector3(-0.1, 0.13, 0), RoomUtil.mat(Color(0.3, 0.5, 0.2)), false)
		"kui":
			var nm := RoomUtil.glow_mat(color, 2.4)
			var head := RoomUtil.mesh(root, _sphere(0.15), Vector3(-0.1, -0.22, 0), nm, false)
			head.scale = Vector3(1.3, 0.9, 0.7)
			RoomUtil.mesh(root, RoomUtil.box_mesh(Vector3(0.05, 0.6, 0.05)), Vector3(0.07, 0.07, 0), nm, false)
			var flag := RoomUtil.mesh(root, RoomUtil.box_mesh(Vector3(0.22, 0.07, 0.05)), Vector3(0.16, 0.32, 0), nm, false)
			flag.rotation.z = -0.5
		"boss":
			var bone := RoomUtil.mat(Color(0.92, 0.88, 0.8), 0.6)
			var skull := RoomUtil.mesh(root, _sphere(0.3), Vector3(0, 0.05, 0), bone, false)
			skull.scale = Vector3(1, 0.95, 0.95)
			RoomUtil.mesh(root, RoomUtil.box_mesh(Vector3(0.32, 0.16, 0.26)), Vector3(0, -0.24, 0.04), bone, false)
			for sx: float in [-0.11, 0.11]:
				RoomUtil.mesh(root, _sphere(0.075), Vector3(sx, 0.04, 0.25), RoomUtil.glow_mat(Color(1, 0.15, 0.1), 3.0), false)
			# корона
			var crown := RoomUtil.mat(Color(1, 0.75, 0.25), 0.3, Color(1, 0.6, 0.1), 0.8, 0.8)
			RoomUtil.mesh(root, RoomUtil.cyl_mesh(0.26, 0.28, 0.08, 12), Vector3(0, 0.3, 0), crown, false)
			for k in 5:
				var a := TAU * k / 5.0
				var pm3 := PrismMesh.new()
				pm3.size = Vector3(0.1, 0.16, 0.05)
				RoomUtil.mesh(root, pm3, Vector3(cos(a) * 0.24, 0.42, sin(a) * 0.24), crown, false)
		"rest":
			var wm := RoomUtil.mat(Color(0.4, 0.75, 1.0, 0.85), 0.1, Color(0.4, 0.8, 1.0), 1.2)
			RoomUtil.mesh(root, _sphere(0.24), Vector3(0, -0.12, 0), wm, false)
			RoomUtil.mesh(root, RoomUtil.cyl_mesh(0.0, 0.2, 0.32, 10), Vector3(0, 0.16, 0), wm, false)
		_:
			RoomUtil.mesh(root, _sphere(0.25), Vector3.ZERO, RoomUtil.glow_mat(color, 2.0), false)
	return root


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 7
	return s


static func _god_emblem(root: Node3D, god: String, color: Color, pos: Vector3, scale := 1.0) -> void:
	var tex := RoomUtil.god_icon(god)
	if tex:
		var s := Sprite3D.new()
		s.texture = tex
		s.pixel_size = 0.7 * scale / maxf(1.0, float(tex.get_width()))
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.position = pos
		s.no_depth_test = false
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		root.add_child(s)
	else:
		RoomUtil.mesh(root, _sphere(0.22 * scale), pos, RoomUtil.glow_mat(color, 2.5), false)
	var f := RoomUtil.flame_sprite(color, 0.009 * scale)
	f.position = pos + Vector3(0, -0.05, -0.05)
	root.add_child(f)


## Медленное вращение и покачивание иконки.
class _Spin extends Node3D:
	var t := randf() * 10.0
	var base_y := 0.0
	var spin := true

	func _ready() -> void:
		base_y = position.y

	func _process(delta: float) -> void:
		t += delta
		if spin:
			rotation.y += delta * 1.2
		position.y = base_y + sin(t * 2.0) * 0.08
