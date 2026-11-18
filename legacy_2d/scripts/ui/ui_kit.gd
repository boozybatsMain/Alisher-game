extends RefCounted
## Общий стиль интерфейса: шрифт, тема кнопок, панели с золотой рамкой.

const GOLD := Color(0.85, 0.7, 0.36)
const TEAL := Color(0.37, 0.9, 0.83)
const TEXT := Color(0.94, 0.89, 0.82)
const MUTED := Color(0.72, 0.62, 0.52)
const PANEL_TEX := preload("res://assets/ui/panel.png")

static var _boil: ShaderMaterial
static var _font: Font
static var _bold: Font
static var _theme: Theme


static func boil_mat() -> ShaderMaterial:
	## «Кипение линий» 8 раз в секунду — как у мира на арене. Один материал на все картинки интерфейса.
	if _boil == null:
		_boil = ShaderMaterial.new()
		_boil.shader = preload("res://shaders/world.gdshader")
	return _boil


static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Georgia", "Times New Roman", "Liberation Serif", "DejaVu Serif", "Noto Serif", "serif"])
		_font = f
	return _font


static func bold() -> Font:
	if _bold == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Georgia", "Times New Roman", "Liberation Serif", "DejaVu Serif", "Noto Serif", "serif"])
		f.font_weight = 700
		_bold = f
	return _bold


static func _box(bg: Color, border: Color, bw := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func theme() -> Theme:
	if _theme == null:
		var t := Theme.new()
		t.default_font = font()
		t.default_font_size = 20
		t.set_stylebox("normal", "Button", _box(Color(0.17, 0.1, 0.08, 0.95), GOLD))
		t.set_stylebox("hover", "Button", _box(Color(0.26, 0.15, 0.1, 0.98), TEAL))
		t.set_stylebox("pressed", "Button", _box(Color(0.12, 0.07, 0.05, 1.0), TEAL))
		t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), TEAL, 2))
		t.set_stylebox("disabled", "Button", _box(Color(0.12, 0.09, 0.08, 0.8), Color(0.4, 0.33, 0.25)))
		t.set_color("font_color", "Button", TEXT)
		t.set_color("font_hover_color", "Button", Color(1, 1, 1))
		t.set_color("font_pressed_color", "Button", TEAL)
		t.set_color("font_disabled_color", "Button", Color(0.5, 0.44, 0.38))
		t.set_color("font_color", "Label", TEXT)
		t.set_color("font_outline_color", "Label", Color(0.08, 0.04, 0.03))
		t.set_constant("outline_size", "Label", 4)
		_theme = t
	return _theme


static func panel(size: Vector2) -> NinePatchRect:
	var p := NinePatchRect.new()
	p.texture = PANEL_TEX
	p.patch_margin_left = 64
	p.patch_margin_right = 64
	p.patch_margin_top = 64
	p.patch_margin_bottom = 64
	p.size = size
	p.material = boil_mat()
	return p


static func label(text: String, size := 20, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


static func button(text: String, callback: Callable, min_width := 220) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 46)
	b.pressed.connect(callback)
	b.pressed.connect(func(): Sfx.play("ui_click"))
	b.mouse_entered.connect(func(): Sfx.play("ui_hover", -14.0))
	return b


static func dim(parent: Node, alpha := 0.6) -> ColorRect:
	## Затемнение экрана под меню.
	var r := ColorRect.new()
	r.color = Color(0.03, 0.01, 0.0, alpha)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(r)
	return r
