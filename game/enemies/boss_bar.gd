extends CanvasLayer
## Полоса босса внизу экрана: имя, HP, броня, отметка фазы. Создаётся боссом при активации
## (BossBase.show_bar). HUD может не рисовать свою полосу, если у босса own_bar == true.

var boss: Node = null
var _name: Label
var _hp_fill: ColorRect
var _hp_ghost: ColorRect
var _armor_fill: ColorRect
var _armor_bg: ColorRect
var _phase_mark: ColorRect
var _w := 720.0
var _ghost := 1.0


func _ready() -> void:
	add_to_group("boss_bar")
	layer = 20
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -_w * 0.5
	box.offset_right = _w * 0.5
	box.offset_top = -96
	box.offset_bottom = -24
	root.add_child(box)
	_name = Label.new()
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.size = Vector2(_w, 30)
	_name.position = Vector2(0, 0)
	_name.add_theme_font_size_override("font_size", 22)
	_name.add_theme_color_override("font_color", Color(1.0, 0.86, 0.6))
	_name.add_theme_color_override("font_outline_color", Color(0.08, 0.03, 0.05))
	_name.add_theme_constant_override("outline_size", 8)
	box.add_child(_name)
	var frame := ColorRect.new()
	frame.color = Color(0.9, 0.7, 0.35)
	frame.position = Vector2(-3, 31)
	frame.size = Vector2(_w + 6, 24)
	box.add_child(frame)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.04, 0.06)
	bg.position = Vector2(0, 34)
	bg.size = Vector2(_w, 18)
	box.add_child(bg)
	_hp_ghost = ColorRect.new()
	_hp_ghost.color = Color(1.0, 0.85, 0.6)
	_hp_ghost.position = bg.position
	_hp_ghost.size = bg.size
	box.add_child(_hp_ghost)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.78, 0.12, 0.16)
	_hp_fill.position = bg.position
	_hp_fill.size = bg.size
	box.add_child(_hp_fill)
	_phase_mark = ColorRect.new()
	_phase_mark.color = Color(1, 0.9, 0.7, 0.9)
	_phase_mark.size = Vector2(3, 18)
	_phase_mark.position = Vector2(_w * 0.5 - 1.5, 34)
	box.add_child(_phase_mark)
	_armor_bg = ColorRect.new()
	_armor_bg.color = Color(0.06, 0.06, 0.1)
	_armor_bg.position = Vector2(0, 56)
	_armor_bg.size = Vector2(_w, 8)
	box.add_child(_armor_bg)
	_armor_fill = ColorRect.new()
	_armor_fill.color = Color(0.8, 0.88, 1.0)
	_armor_fill.position = _armor_bg.position
	_armor_fill.size = _armor_bg.size
	box.add_child(_armor_fill)


func _process(delta: float) -> void:
	if boss == null or not is_instance_valid(boss):
		queue_free()
		return
	var hp := float(boss.get("hp"))
	var mhp := maxf(float(boss.get("max_hp")), 1.0)
	var ar := float(boss.get("armor"))
	var mar := float(boss.get("max_armor"))
	_name.text = String(boss.get("display_name"))
	var k := clampf(hp / mhp, 0.0, 1.0)
	_hp_fill.size.x = _w * k
	_ghost = move_toward(_ghost, k, delta * 0.35) if _ghost > k else k
	_hp_ghost.size.x = _w * _ghost
	_armor_bg.visible = mar > 0.0
	_armor_fill.visible = mar > 0.0
	if mar > 0.0:
		_armor_fill.size.x = _w * clampf(ar / mar, 0.0, 1.0)
	var pt = boss.get("phase_threshold")
	_phase_mark.visible = pt != null and int(boss.get("phase")) < 2
	if pt != null:
		_phase_mark.position.x = _w * float(pt) - 1.5
	if boss.has_method("is_dead") and boss.is_dead():
		_hp_fill.size.x = 0.0
