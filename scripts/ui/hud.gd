extends CanvasLayer
## HUD как в макете: рамка с бирюзовым камнем, красная полоса здоровья, бирюзовая — готовность кувырка,
## три ромба Даров, щит с перезарядкой, счётчик асыков справа сверху, название волны, полоса босса, баннеры.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Layout := preload("res://scripts/data/hud_layout.gd")
const Gifts := preload("res://scripts/data/gifts.gd")
const HUD_SCALE := 0.72

var hero: Node
var boss: Node
var root: Control
var hp_bar: TextureProgressBar
var st_bar: TextureProgressBar
var slot_icons: Array[TextureRect] = []
var slot_levels: Array[Label] = []
var shield_icon: Control
var tumar_icon: TextureRect
var asyk_label: Label
var wave_label: Label
var banner: Label
var banner_sub: Label
var boss_box: Control
var boss_name: Label
var boss_fill: ColorRect
var boss_ghost: ColorRect
var hurt_rect: ColorRect
var hint: Label
var _last_hp := -1.0


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme()
	add_child(root)

	hurt_rect = ColorRect.new()
	hurt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_rect.color = Color(0.8, 0.05, 0.02, 0.0)
	hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hurt_rect)

	# --- рамка здоровья
	var frame_root := Control.new()
	frame_root.position = Vector2(8, 4)
	frame_root.scale = Vector2(HUD_SCALE, HUD_SCALE)
	frame_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame_root)
	hp_bar = _bar("hp", Layout.HP_POS)
	frame_root.add_child(hp_bar)
	st_bar = _bar("st", Layout.ST_POS)
	frame_root.add_child(st_bar)
	var frame := TextureRect.new()
	frame.texture = preload("res://assets/ui/hud_frame.png")
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.material = UI.boil_mat()
	frame_root.add_child(frame)
	for i in 3:
		var s: Vector3 = Layout.SLOTS[i]
		var ic := TextureRect.new()
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size = Vector2(s.z * 1.02, s.z * 1.02)
		ic.position = Vector2(s.x, s.y) - ic.size * 0.5
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.material = UI.boil_mat()
		frame_root.add_child(ic)
		slot_icons.append(ic)
		var lv := UI.label("", 22, Color(1, 0.9, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
		lv.add_theme_font_override("font", UI.bold())
		lv.size = Vector2(60, 26)
		lv.position = Vector2(s.x - 30, s.y + s.z * 0.42)
		frame_root.add_child(lv)
		slot_levels.append(lv)
	shield_icon = preload("res://scripts/ui/cooldown_icon.gd").new()
	shield_icon.position = Vector2(Layout.SLOTS[2].x + 92, Layout.SLOTS[2].y)
	frame_root.add_child(shield_icon)
	tumar_icon = TextureRect.new()
	tumar_icon.texture = preload("res://assets/ui/icons/tumar.png")
	tumar_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tumar_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tumar_icon.size = Vector2(54, 54)
	tumar_icon.position = Vector2(Layout.SLOTS[2].x + 140, Layout.SLOTS[2].y - 27)
	tumar_icon.visible = false
	tumar_icon.material = UI.boil_mat()
	frame_root.add_child(tumar_icon)

	# --- асыки
	var asyk_box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.06, 0.05, 0.85)
	sb.border_color = UI.GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.corner_radius_top_left = 26
	sb.corner_radius_bottom_left = 26
	sb.content_margin_left = 22
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	asyk_box.add_theme_stylebox_override("panel", sb)
	asyk_box.position = Vector2(1080, 18)
	asyk_box.custom_minimum_size = Vector2(180, 56)
	root.add_child(asyk_box)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 10)
	asyk_box.add_child(hb)
	asyk_label = UI.label("0", 30, Color(1, 0.95, 0.85), HORIZONTAL_ALIGNMENT_RIGHT)
	asyk_label.add_theme_font_override("font", UI.bold())
	asyk_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(asyk_label)
	var aic := TextureRect.new()
	aic.texture = preload("res://assets/ui/icons/asyk.png")
	aic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	aic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	aic.custom_minimum_size = Vector2(52, 44)
	aic.material = UI.boil_mat()
	hb.add_child(aic)

	# --- волна, баннер, подсказка
	wave_label = UI.label("", 21, Color(1, 0.92, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	wave_label.size = Vector2(640, 30)
	wave_label.position = Vector2(320, 18)
	root.add_child(wave_label)
	banner = UI.label("", 54, Color(1, 0.88, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	banner.add_theme_font_override("font", UI.bold())
	banner.add_theme_constant_override("outline_size", 10)
	banner.size = Vector2(1280, 70)
	banner.position = Vector2(0, 230)
	banner.modulate.a = 0.0
	root.add_child(banner)
	banner_sub = UI.label("", 26, Color(0.95, 0.9, 0.82), HORIZONTAL_ALIGNMENT_CENTER)
	banner_sub.size = Vector2(1280, 36)
	banner_sub.position = Vector2(0, 300)
	banner_sub.modulate.a = 0.0
	root.add_child(banner_sub)
	hint = UI.label("", 18, Color(0.9, 0.82, 0.7, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	hint.size = Vector2(1280, 26)
	hint.position = Vector2(0, 686)
	root.add_child(hint)

	# --- полоса босса
	boss_box = Control.new()
	boss_box.position = Vector2(240, 640)
	boss_box.size = Vector2(800, 50)
	boss_box.visible = false
	root.add_child(boss_box)
	boss_name = UI.label("", 22, Color(1, 0.85, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	boss_name.add_theme_font_override("font", UI.bold())
	boss_name.size = Vector2(800, 28)
	boss_name.position = Vector2(0, -6)
	boss_box.add_child(boss_name)
	var back := ColorRect.new()
	back.color = Color(0.08, 0.03, 0.02, 0.9)
	back.position = Vector2(0, 26)
	back.size = Vector2(800, 18)
	boss_box.add_child(back)
	boss_ghost = ColorRect.new()
	boss_ghost.color = Color(1, 0.85, 0.6, 0.8)
	boss_ghost.position = Vector2(2, 28)
	boss_ghost.size = Vector2(796, 14)
	boss_box.add_child(boss_ghost)
	boss_fill = ColorRect.new()
	boss_fill.color = Color(0.82, 0.18, 0.12)
	boss_fill.position = Vector2(2, 28)
	boss_fill.size = Vector2(796, 14)
	boss_box.add_child(boss_fill)
	var border := ReferenceRect.new()
	border.border_color = UI.GOLD
	border.border_width = 2.0
	border.editor_only = false
	border.position = Vector2(-2, 24)
	border.size = Vector2(804, 22)
	boss_box.add_child(border)

	GameState.asyks_changed.connect(func(v): asyk_label.text = str(v))
	GameState.gifts_changed.connect(_refresh_gifts)
	asyk_label.text = str(GameState.asyks)
	_refresh_gifts()


func _bar(name: String, pos: Vector2) -> TextureProgressBar:
	var b := TextureProgressBar.new()
	b.texture_under = load("res://assets/ui/bar_%s_back.png" % name)
	b.texture_progress = load("res://assets/ui/bar_%s.png" % name)
	b.position = pos
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.001
	b.value = 1.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func bind(p_hero: Node) -> void:
	hero = p_hero
	hero.hp_changed.connect(_on_hp)
	_on_hp(hero.hp, hero.max_hp)


func _on_hp(hp: float, max_hp: float) -> void:
	var v := hp / max_hp
	if _last_hp >= 0.0 and v < _last_hp - 0.001:
		hurt_rect.color.a = 0.28
	_last_hp = v
	create_tween().tween_property(hp_bar, "value", v, 0.15)


func _refresh_gifts() -> void:
	for i in 3:
		var g := GameState.gift_god(i)
		slot_icons[i].texture = load(Gifts.icon_path(g, i)) if g != "" else null
		var lvl := GameState.gift_level(i)
		slot_levels[i].text = ["", "", "II", "III"][lvl]
	if tumar_icon:
		tumar_icon.visible = GameState.amulet


func _process(delta: float) -> void:
	hurt_rect.color.a = maxf(0.0, hurt_rect.color.a - delta * 1.2)
	if hero and is_instance_valid(hero):
		st_bar.value = 1.0 - hero.roll_cd / maxf(0.01, hero.roll_cd_max)
		st_bar.modulate = Color(1, 0.5, 0.45) if hero.deny_roll > 0.0 else Color.WHITE
		shield_icon.cd = hero.shield_cd
		shield_icon.cd_max = hero.shield_cd_max
		shield_icon.deny = hero.deny_shield
	if boss and is_instance_valid(boss):
		var v: float = clampf(boss.hp / boss.max_hp, 0.0, 1.0)
		boss_fill.size.x = 796.0 * v
		boss_ghost.size.x = lerpf(boss_ghost.size.x, boss_fill.size.x, minf(1.0, delta * 2.5))
		boss_fill.color = Color(0.95, 0.3, 0.1) if boss.enraged else Color(0.82, 0.18, 0.12)
	elif boss_box.visible:
		boss_box.visible = false


func set_wave(text: String) -> void:
	wave_label.text = text


func set_hint(text: String) -> void:
	hint.text = text


var _banner_tw: Tween


func hide_banner() -> void:
	if _banner_tw:
		_banner_tw.kill()
	banner.modulate.a = 0.0
	banner_sub.modulate.a = 0.0


func show_banner(text: String, sub := "", hold := 1.6) -> void:
	banner.text = text
	banner_sub.text = sub
	if _banner_tw:
		_banner_tw.kill()
	var tw := create_tween()
	_banner_tw = tw
	tw.tween_property(banner, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(banner_sub, "modulate:a", 1.0, 0.25)
	tw.tween_interval(hold)
	tw.tween_property(banner, "modulate:a", 0.0, 0.4)
	tw.parallel().tween_property(banner_sub, "modulate:a", 0.0, 0.4)


func show_boss(e: Node) -> void:
	boss = e
	boss_name.text = e.def["name"]
	boss_box.visible = true
	boss_box.modulate.a = 0.0
	create_tween().tween_property(boss_box, "modulate:a", 1.0, 0.5)
