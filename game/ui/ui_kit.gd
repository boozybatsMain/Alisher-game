class_name UiKit
extends RefCounted
## Общий UI-кит «Тамыра»: палитра (тёмный войлок, золото, бирюза), шрифты, тема, панели и кнопки с орнаментом.
## Всё — статические функции, ресурсы кешируются.
##
## API:
##   Цвета: UiKit.FELT, FELT_DARK, FELT_LIGHT, GOLD, GOLD_DIM, TEAL, TEXT, MUTED, RED, GREEN, OCHRE
##   UiKit.GOD_COLORS[god_id] -> Color, UiKit.god_color(id) -> Color
##   UiKit.font() / bold() -> Font
##   UiKit.theme() -> Theme              — назначайте корневому Control: ctrl.theme = UiKit.theme()
##   UiKit.panel(min_size := Vector2.ZERO, accent := GOLD) -> PanelContainer   (с орнаментом-рамкой)
##   UiKit.button(text, on_press: Callable = Callable(), min_w := 260) -> Button  (звук ui_click/ui_hover)
##   UiKit.label(text, size := 20, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label
##   UiKit.title(text, size := 40, color := GOLD) -> Label   (жирный, с тенью, по центру)
##   UiKit.vbox(sep := 10) / hbox(sep := 10) -> BoxContainer
##   UiKit.dim(alpha := 0.6) -> ColorRect    (полноэкранное затемнение)
##   UiKit.center(child) -> CenterContainer  (полноэкранный, кладёт child по центру)
##   UiKit.box(bg, border, bw := 2, radius := 8) -> StyleBoxFlat
##   UiKit.ornament(color := GOLD) -> Control   (горизонтальная полоса «қошқар мүйіз» для разделителей)

const FELT := Color(0.16, 0.10, 0.08, 0.96)
const FELT_DARK := Color(0.09, 0.055, 0.045, 0.98)
const FELT_LIGHT := Color(0.27, 0.17, 0.12, 0.98)
const GOLD := Color(0.88, 0.72, 0.36)
const GOLD_DIM := Color(0.6, 0.47, 0.24)
const TEAL := Color(0.33, 0.85, 0.80)
const TEXT := Color(0.95, 0.90, 0.82)
const MUTED := Color(0.70, 0.62, 0.52)
const RED := Color(0.88, 0.25, 0.22)
const GREEN := Color(0.45, 0.85, 0.40)
const OCHRE := Color(0.80, 0.55, 0.25)

const GOD_COLORS := {
	"tengri": Color("#8cc8ff"), "ai_mergen": Color("#c9b3ff"), "umai": Color("#ff8a3d"),
	"zher_su": Color("#5fd3c4"), "erlik": Color("#9b4dff"), "kokbori": Color("#e04848"),
}
const GOD_TITLES := {
	"tengri": "Тенгри", "ai_mergen": "Ай-Мерген", "umai": "Умай",
	"zher_su": "Жер-Су", "erlik": "Ерлик", "kokbori": "Көкбөрі",
}

const _SERIF := ["Georgia", "Times New Roman", "Liberation Serif", "DejaVu Serif", "Noto Serif", "serif"]

static var _font: Font
static var _bold: Font
static var _theme: Theme


static func god_color(id: String) -> Color:
	return GOD_COLORS.get(id, GOLD)


static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(_SERIF)
		_font = f
	return _font


static func bold() -> Font:
	if _bold == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(_SERIF)
		f.font_weight = 700
		_bold = f
	return _bold


static func box(bg: Color, border: Color, bw := 2, radius := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 6
	sb.anti_aliasing = true
	return sb


static func theme() -> Theme:
	if _theme == null:
		var t := Theme.new()
		t.default_font = font()
		t.default_font_size = 22
		var normal := box(FELT, GOLD_DIM)
		var hover := box(FELT_LIGHT, TEAL)
		hover.shadow_color = Color(TEAL, 0.25)
		var pressed := box(FELT_DARK, TEAL)
		var focus := box(Color(0, 0, 0, 0), TEAL, 2)
		focus.shadow_size = 0
		var disabled := box(Color(0.12, 0.09, 0.08, 0.8), Color(0.35, 0.29, 0.22))
		t.set_stylebox("normal", "Button", normal)
		t.set_stylebox("hover", "Button", hover)
		t.set_stylebox("pressed", "Button", pressed)
		t.set_stylebox("focus", "Button", focus)
		t.set_stylebox("disabled", "Button", disabled)
		t.set_color("font_color", "Button", TEXT)
		t.set_color("font_hover_color", "Button", Color(1, 1, 1))
		t.set_color("font_pressed_color", "Button", TEAL)
		t.set_color("font_focus_color", "Button", Color(1, 0.97, 0.9))
		t.set_color("font_disabled_color", "Button", Color(0.5, 0.44, 0.38))
		t.set_font("font", "Button", bold())
		t.set_color("font_color", "Label", TEXT)
		t.set_color("font_outline_color", "Label", Color(0.07, 0.04, 0.03))
		t.set_constant("outline_size", "Label", 4)
		t.set_color("default_color", "RichTextLabel", TEXT)
		t.set_font("bold_font", "RichTextLabel", bold())
		t.set_font("normal_font", "RichTextLabel", font())
		t.set_stylebox("panel", "PanelContainer", box(FELT, GOLD, 2, 10))
		t.set_stylebox("panel", "Panel", box(FELT, GOLD, 2, 10))
		t.set_stylebox("panel", "TooltipPanel", box(FELT_DARK, GOLD_DIM, 1, 6))
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.05, 0.03, 0.03, 0.8)
		bg.set_corner_radius_all(4)
		var fill := StyleBoxFlat.new()
		fill.bg_color = GOLD
		fill.set_corner_radius_all(4)
		t.set_stylebox("background", "ProgressBar", bg)
		t.set_stylebox("fill", "ProgressBar", fill)
		t.set_constant("separation", "VBoxContainer", 10)
		t.set_constant("separation", "HBoxContainer", 10)
		_theme = t
	return _theme


## Панель с рамкой-орнаментом (двойная рамка: золото снаружи + тонкая бирюзовая внутри, уголки-ромбы).
static func panel(min_size := Vector2.ZERO, accent := GOLD) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = theme()
	p.custom_minimum_size = min_size
	var sb := box(FELT, accent, 3, 10)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	sb.shadow_size = 12
	p.add_theme_stylebox_override("panel", sb)
	# Орнамент рисуется прямо на панели (поверх фона, под детьми), не участвует в раскладке.
	p.draw.connect(_draw_ornament.bind(p, accent))
	return p


static func button(text: String, on_press: Callable = Callable(), min_w := 260) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = theme()
	b.custom_minimum_size = Vector2(min_w, 52)
	b.add_theme_font_size_override("font_size", 24)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_entered.connect(func(): Sfx.play("ui_hover", -14.0))
	b.focus_entered.connect(func(): Sfx.play("ui_hover", -16.0))
	b.pressed.connect(func(): Sfx.play("ui_click", -6.0))
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


static func label(text: String, size := 20, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.theme = theme()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func title(text: String, size := 40, color := GOLD) -> Label:
	var l := label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", bold())
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func dim(alpha := 0.6) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.03, 0.02, 0.02, alpha)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


static func center(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.theme = theme()
	c.add_child(child)
	return c


static func ornament(color := GOLD) -> Control:
	var o := _Divider.new()
	o.color = color
	o.custom_minimum_size = Vector2(120, 16)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return o


## Уголки-ромбы, внутренняя тонкая бирюзовая рамка и «бараний рог» по центру верхней кромки.
static func _draw_ornament(c: Control, color: Color) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	if r.size.x < 40 or r.size.y < 40:
		return
	var inner := r.grow(-8)
	c.draw_rect(inner, Color(0.33, 0.85, 0.80, 0.35), false, 1.0)
	var s := 9.0
	for k: Vector2 in [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]:
		c.draw_colored_polygon(PackedVector2Array([k + Vector2(0, -s), k + Vector2(s, 0), k + Vector2(0, s), k + Vector2(-s, 0)]), color)
		c.draw_colored_polygon(PackedVector2Array([k + Vector2(0, -s * 0.45), k + Vector2(s * 0.45, 0), k + Vector2(0, s * 0.45), k + Vector2(-s * 0.45, 0)]), Color(0.16, 0.1, 0.08))
	var top := Vector2(r.size.x * 0.5, 8)
	c.draw_arc(top + Vector2(-9, 0), 7.0, 0.0, PI, 10, color, 2.0)
	c.draw_arc(top + Vector2(9, 0), 7.0, 0.0, PI, 10, color, 2.0)
	var bot := Vector2(r.size.x * 0.5, r.size.y - 8)
	c.draw_arc(bot + Vector2(-9, 0), 7.0, PI, TAU, 10, color, 2.0)
	c.draw_arc(bot + Vector2(9, 0), 7.0, PI, TAU, 10, color, 2.0)


class _Divider extends Control:
	var color := Color(0.88, 0.72, 0.36)

	func _draw() -> void:
		var y := size.y * 0.5
		var cx := size.x * 0.5
		draw_line(Vector2(0, y), Vector2(cx - 22, y), Color(color, 0.7), 1.5)
		draw_line(Vector2(cx + 22, y), Vector2(size.x, y), Color(color, 0.7), 1.5)
		draw_arc(Vector2(cx - 8, y), 7.0, PI, TAU, 10, color, 2.0)
		draw_arc(Vector2(cx + 8, y), 7.0, PI, TAU, 10, color, 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(cx, y - 5), Vector2(cx + 5, y), Vector2(cx, y + 5), Vector2(cx - 5, y)]), color)
